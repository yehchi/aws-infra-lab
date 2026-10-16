"""
收盤後批次作業 — 由 Step Functions 依序呼叫，每一步是一個獨立的 ECS 排程任務

  python -m batch.run settlement   日終結算：當日成交依帳戶、股票彙總（寫主庫）
  python -m batch.run clearing     交割作業：依結算結果產生 T+2 交割款項（寫主庫）
  python -m batch.run report       法規報表：從 Read Replica 讀取彙總、產生當日報表（讀複本、結果寫主庫）

設計重點：
  1. 冪等（idempotent）：每一步都是「刪掉當日舊結果 → 重新計算寫入」，包在同一個交易裡。
     重跑幾次結果都一樣，失敗時也不會留下半套資料（交易整筆 rollback）。
  2. 可從中斷步驟續跑：每一步只依賴前一步寫進資料庫的結果，不依賴記憶體狀態。
  3. 演練開關放在 SSM Parameter Store，不用改程式或重新部署：
       /infra-lab/<env>/batch/fail-step            設成 settlement / clearing / report 即在該步驟模擬失敗
       /infra-lab/<env>/batch/report-load-seconds  報表步驟額外對複本施加 N 秒重查詢，模擬大型報表

環境變數：
  DB_HOST / DB_READ_HOST / DB_PORT / DB_NAME / DB_USER / DB_PASSWORD（由 Secrets Manager 注入）
  TRADE_DATE（YYYY-MM-DD，由 Step Functions 傳入；沒給就用台灣時間的今天）
  DRILL_PARAM_PREFIX（例如 /infra-lab/dev/batch，沒設定就不讀演練開關）
"""

import asyncio
import json
import os
import sys
import time
from datetime import date, datetime, timedelta, timezone

import asyncpg

TAIPEI = timezone(timedelta(hours=8))
STEPS = ("settlement", "clearing", "report")

# 交易時間存的是 UTC（RDS 預設時區），換算成台灣日期再比對
TRADE_DATE_SQL = "(trade_time AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Taipei')::date"

DDL = """
CREATE TABLE IF NOT EXISTS daily_settlement (
    trade_date    DATE           NOT NULL,
    account_id    VARCHAR(20)    NOT NULL,
    stock_symbol  VARCHAR(10)    NOT NULL,
    buy_qty       INTEGER        NOT NULL,
    sell_qty      INTEGER        NOT NULL,
    buy_amount    NUMERIC(15, 2) NOT NULL,
    sell_amount   NUMERIC(15, 2) NOT NULL,
    net_amount    NUMERIC(15, 2) NOT NULL,   -- 賣出 - 買進：正數 = 客戶應收，負數 = 客戶應付
    created_at    TIMESTAMP      NOT NULL DEFAULT NOW(),
    PRIMARY KEY (trade_date, account_id, stock_symbol)
);
CREATE TABLE IF NOT EXISTS settlement_instructions (
    trade_date    DATE           NOT NULL,
    settle_date   DATE           NOT NULL,   -- T+2（遇週末順延）
    account_id    VARCHAR(20)    NOT NULL,
    net_amount    NUMERIC(15, 2) NOT NULL,
    direction     VARCHAR(8)     NOT NULL CHECK (direction IN ('RECEIVE', 'PAY', 'NONE')),
    created_at    TIMESTAMP      NOT NULL DEFAULT NOW(),
    PRIMARY KEY (trade_date, account_id)
);
CREATE TABLE IF NOT EXISTS daily_reports (
    trade_date      DATE           PRIMARY KEY,
    total_trades    INTEGER        NOT NULL,
    total_accounts  INTEGER        NOT NULL,
    total_buy       NUMERIC(15, 2) NOT NULL,
    total_sell      NUMERIC(15, 2) NOT NULL,
    total_pay       NUMERIC(15, 2) NOT NULL,
    total_receive   NUMERIC(15, 2) NOT NULL,
    read_from       VARCHAR(10)    NOT NULL,  -- 報表資料是從 replica 還是 primary 讀的
    generated_at    TIMESTAMP      NOT NULL DEFAULT NOW()
);
"""


def log(step, msg, **kw):
    """一行一筆 JSON，CloudWatch Logs Insights 可以直接查"""
    rec = {"time": datetime.now(TAIPEI).strftime("%H:%M:%S"), "step": step, "msg": msg, **kw}
    print(json.dumps(rec, ensure_ascii=False, default=str), flush=True)


def trade_date_from_env():
    raw = os.environ.get("TRADE_DATE", "").strip()
    return date.fromisoformat(raw) if raw else datetime.now(TAIPEI).date()


def settle_date_of(trade_date):
    """T+2 個營業日（只跳過週末；國定假日不在這次範圍內）"""
    d, n = trade_date, 0
    while n < 2:
        d += timedelta(days=1)
        if d.weekday() < 5:
            n += 1
    return d


def drill_param(name, default):
    """讀 SSM 演練開關；沒設定前綴或讀不到就用預設值（正式執行不受影響）"""
    prefix = os.environ.get("DRILL_PARAM_PREFIX")
    if not prefix:
        return default
    try:
        import boto3

        ssm = boto3.client("ssm")
        return ssm.get_parameter(Name=f"{prefix}/{name}")["Parameter"]["Value"].strip()
    except Exception as e:  # 演練開關失效不應該讓正式批次失敗
        log("init", "讀取演練開關失敗，使用預設值", param=name, error=str(e))
        return default


async def connect(host):
    return await asyncpg.connect(
        host=host,
        port=int(os.environ.get("DB_PORT", "5432")),
        database=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "dbadmin"),
        password=os.environ.get("DB_PASSWORD", ""),
        timeout=10,
    )


def maybe_fail(step, fail_step):
    """在交易 commit 之前丟出例外 → 整筆 rollback，證明失敗不會留下半套資料"""
    if fail_step == step:
        raise RuntimeError(f"演練：在 {step} 步驟模擬失敗（SSM fail-step = {step}）")


# ---------------------------------------------------------------- 步驟 1
async def settlement(conn, trade_date, fail_step, **_):
    async with conn.transaction():
        await conn.execute("DELETE FROM daily_settlement WHERE trade_date = $1", trade_date)
        result = await conn.execute(
            f"""
            INSERT INTO daily_settlement
                (trade_date, account_id, stock_symbol, buy_qty, sell_qty, buy_amount, sell_amount, net_amount)
            SELECT $1, account_id, stock_symbol,
                   COALESCE(SUM(quantity)     FILTER (WHERE trade_type = 'BUY'),  0),
                   COALESCE(SUM(quantity)     FILTER (WHERE trade_type = 'SELL'), 0),
                   COALESCE(SUM(total_amount) FILTER (WHERE trade_type = 'BUY'),  0),
                   COALESCE(SUM(total_amount) FILTER (WHERE trade_type = 'SELL'), 0),
                   COALESCE(SUM(total_amount) FILTER (WHERE trade_type = 'SELL'), 0)
                 - COALESCE(SUM(total_amount) FILTER (WHERE trade_type = 'BUY'),  0)
            FROM trades
            WHERE status = 'completed' AND {TRADE_DATE_SQL} = $1
            GROUP BY account_id, stock_symbol
            """,
            trade_date,
        )
        rows = int(result.split()[-1])
        maybe_fail("settlement", fail_step)
    return {"rows": rows}


# ---------------------------------------------------------------- 步驟 2
async def clearing(conn, trade_date, fail_step, **_):
    async with conn.transaction():
        settled = await conn.fetchval("SELECT COUNT(*) FROM daily_settlement WHERE trade_date = $1", trade_date)
        if settled == 0 and await conn.fetchval(
            f"SELECT COUNT(*) FROM trades WHERE status = 'completed' AND {TRADE_DATE_SQL} = $1", trade_date
        ):
            # 有交易卻沒有結算結果 → 前一步沒跑成功，不能硬算交割
            raise RuntimeError("找不到當日結算結果，請先完成 settlement 步驟")
        await conn.execute("DELETE FROM settlement_instructions WHERE trade_date = $1", trade_date)
        result = await conn.execute(
            """
            INSERT INTO settlement_instructions (trade_date, settle_date, account_id, net_amount, direction)
            SELECT $1, $2, account_id, SUM(net_amount),
                   CASE WHEN SUM(net_amount) > 0 THEN 'RECEIVE'
                        WHEN SUM(net_amount) < 0 THEN 'PAY' ELSE 'NONE' END
            FROM daily_settlement
            WHERE trade_date = $1
            GROUP BY account_id
            """,
            trade_date,
            settle_date_of(trade_date),
        )
        rows = int(result.split()[-1])
        maybe_fail("clearing", fail_step)
    return {"rows": rows, "settle_date": settle_date_of(trade_date)}


# ---------------------------------------------------------------- 步驟 3
async def report(conn, trade_date, fail_step, read_conn, read_from, load_seconds, **_):
    # 大型報表模擬：只壓在讀取端（prod = 複本），驗證主庫與線上寫入不受影響
    loops = 0
    if load_seconds > 0:
        log("report", "開始模擬大型報表查詢", seconds=load_seconds, read_from=read_from)
        end = time.monotonic() + load_seconds
        while time.monotonic() < end:
            await read_conn.fetchval(
                "SELECT COUNT(*) FROM trades t CROSS JOIN generate_series(1, 300) g "
                "WHERE t.price * g > 0"
            )
            loops += 1

    s = await read_conn.fetchrow(
        f"""
        SELECT COUNT(*) AS trades, COUNT(DISTINCT account_id) AS accounts,
               COALESCE(SUM(total_amount) FILTER (WHERE trade_type = 'BUY'),  0) AS buy,
               COALESCE(SUM(total_amount) FILTER (WHERE trade_type = 'SELL'), 0) AS sell
        FROM trades WHERE status = 'completed' AND {TRADE_DATE_SQL} = $1
        """,
        trade_date,
    )
    c = await read_conn.fetchrow(
        """
        SELECT COALESCE(SUM(-net_amount) FILTER (WHERE direction = 'PAY'), 0)     AS pay,
               COALESCE(SUM(net_amount)  FILTER (WHERE direction = 'RECEIVE'), 0) AS receive
        FROM settlement_instructions WHERE trade_date = $1
        """,
        trade_date,
    )
    async with conn.transaction():
        await conn.execute(
            """
            INSERT INTO daily_reports
                (trade_date, total_trades, total_accounts, total_buy, total_sell, total_pay, total_receive, read_from)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (trade_date) DO UPDATE SET
                total_trades = EXCLUDED.total_trades, total_accounts = EXCLUDED.total_accounts,
                total_buy = EXCLUDED.total_buy, total_sell = EXCLUDED.total_sell,
                total_pay = EXCLUDED.total_pay, total_receive = EXCLUDED.total_receive,
                read_from = EXCLUDED.read_from, generated_at = NOW()
            """,
            trade_date, s["trades"], s["accounts"], s["buy"], s["sell"], c["pay"], c["receive"], read_from,
        )
        maybe_fail("report", fail_step)
    return {"trades": s["trades"], "accounts": s["accounts"], "buy": s["buy"], "sell": s["sell"],
            "pay": c["pay"], "receive": c["receive"], "read_from": read_from, "load_loops": loops}


async def main(step):
    trade_date = trade_date_from_env()
    fail_step = drill_param("fail-step", "none")
    load_seconds = int(drill_param("report-load-seconds", "0") or 0) if step == "report" else 0

    host = os.environ.get("DB_HOST", "localhost")
    read_host = os.environ.get("DB_READ_HOST") or host
    read_from = "replica" if read_host != host else "primary"

    log(step, "開始", trade_date=trade_date, fail_step=fail_step, read_from=read_from)
    started = time.monotonic()
    conn = await connect(host)
    read_conn = await connect(read_host) if step == "report" and read_from == "replica" else conn
    try:
        await conn.execute(DDL)
        func = {"settlement": settlement, "clearing": clearing, "report": report}[step]
        result = await func(conn, trade_date, fail_step,
                            read_conn=read_conn, read_from=read_from, load_seconds=load_seconds)
        log(step, "完成", seconds=round(time.monotonic() - started, 1), **result)
    finally:
        if read_conn is not conn:
            await read_conn.close()
        await conn.close()


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in STEPS:
        print(f"用法：python -m batch.run {{{'|'.join(STEPS)}}}", file=sys.stderr)
        sys.exit(2)
    try:
        asyncio.run(main(sys.argv[1]))
    except Exception as e:
        log(sys.argv[1], "失敗", error=str(e))
        sys.exit(1)  # 非 0 結束碼 → ECS task 失敗 → Step Functions 判定這一步失敗、觸發重試
