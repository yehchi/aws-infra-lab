# ============================================================
# 翰寧證券 — 交易紀錄查詢服務
# FastAPI + PostgreSQL (via Secrets Manager)
# ============================================================

import os
import uuid
from datetime import datetime
from typing import Optional

import asyncpg
from fastapi import FastAPI, HTTPException, Query, Response
from pydantic import BaseModel, Field

# ----- App 設定 -----
app = FastAPI(
    title="翰寧證券交易紀錄查詢服務",
    description="交易紀錄的新增、查詢、篩選 API",
    version="1.0.0",
)

# ----- 資料庫連線池（讀寫分離）-----
# 寫入走主庫（DB_HOST）；查詢走讀取 endpoint（DB_READ_HOST）
# prod 的 DB_READ_HOST 指向 Read Replica；dev 沒有複本，兩者相同 → 共用同一個連線池
db_pool = None
read_pool = None

DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_READ_HOST = os.environ.get("DB_READ_HOST") or DB_HOST
READ_FROM = "replica" if DB_READ_HOST != DB_HOST else "primary"


async def _create_pool(host):
    return await asyncpg.create_pool(
        host=host,
        port=int(os.environ.get("DB_PORT", "5432")),
        database=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "dbadmin"),
        password=os.environ.get("DB_PASSWORD", ""),
        min_size=2,
        max_size=10,
    )


async def get_db_pool():
    """主庫連線池（寫入、建表），連線資訊由 Secrets Manager 注入"""
    global db_pool
    if db_pool is None:
        db_pool = await _create_pool(DB_HOST)
    return db_pool


async def get_read_pool():
    """讀取連線池：有 Read Replica 就連複本，否則直接用主庫的連線池"""
    global read_pool
    if READ_FROM == "primary":
        return await get_db_pool()
    if read_pool is None:
        read_pool = await _create_pool(DB_READ_HOST)
    return read_pool


# ----- 啟動時建立資料表 -----
@app.on_event("startup")
async def startup():
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS trades (
                trade_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                stock_symbol   VARCHAR(10) NOT NULL,
                stock_name     VARCHAR(50) NOT NULL,
                trade_type     VARCHAR(4) NOT NULL CHECK (trade_type IN ('BUY', 'SELL')),
                quantity        INTEGER NOT NULL CHECK (quantity > 0),
                price          NUMERIC(12, 2) NOT NULL CHECK (price > 0),
                total_amount   NUMERIC(15, 2) GENERATED ALWAYS AS (quantity * price) STORED,
                trade_time     TIMESTAMP NOT NULL DEFAULT NOW(),
                account_id     VARCHAR(20) NOT NULL,
                status         VARCHAR(10) NOT NULL DEFAULT 'completed'
                               CHECK (status IN ('pending', 'completed', 'cancelled'))
            );

            -- 建立索引加速查詢
            CREATE INDEX IF NOT EXISTS idx_trades_account ON trades(account_id);
            CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades(stock_symbol);
            CREATE INDEX IF NOT EXISTS idx_trades_time ON trades(trade_time);
        """)


@app.on_event("shutdown")
async def shutdown():
    if read_pool:
        await read_pool.close()
    if db_pool:
        await db_pool.close()


# ----- Pydantic Models -----
class TradeCreate(BaseModel):
    """新增交易的請求格式"""
    stock_symbol: str = Field(..., example="2330", max_length=10)
    stock_name: str = Field(..., example="台積電", max_length=50)
    trade_type: str = Field(..., example="BUY", pattern="^(BUY|SELL)$")
    quantity: int = Field(..., example=1000, gt=0)
    price: float = Field(..., example=580.0, gt=0)
    account_id: str = Field(..., example="ACC-001", max_length=20)
    status: str = Field(default="completed", pattern="^(pending|completed|cancelled)$")


class TradeResponse(BaseModel):
    """交易紀錄的回傳格式"""
    trade_id: str
    stock_symbol: str
    stock_name: str
    trade_type: str
    quantity: int
    price: float
    total_amount: float
    trade_time: datetime
    account_id: str
    status: str


# ----- Helper -----
def row_to_dict(row) -> dict:
    """把 asyncpg Record 轉成 dict"""
    return {
        "trade_id": str(row["trade_id"]),
        "stock_symbol": row["stock_symbol"],
        "stock_name": row["stock_name"],
        "trade_type": row["trade_type"],
        "quantity": row["quantity"],
        "price": float(row["price"]),
        "total_amount": float(row["total_amount"]),
        "trade_time": row["trade_time"],
        "account_id": row["account_id"],
        "status": row["status"],
    }


# ----- API Endpoints -----

@app.get("/health/live")
async def liveness():
    """存活檢查（ALB 用）：只確認程式本身能回應，不檢查資料庫

    刻意不查資料庫：如果資料庫故障切換的 1-2 分鐘內這裡回錯誤，
    ALB 會判定所有 task 不健康，ECS 就會把全部 task 砍掉重建（連鎖故障）。
    資料庫的狀態交給 /health 與 CloudWatch 告警處理。
    """
    return {"status": "alive"}


@app.get("/health")
async def health_check():
    """完整健康檢查：程式 + 資料庫連線（部署驗證、監控用）"""
    try:
        pool = await get_db_pool()
        async with pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        rpool = await get_read_pool()
        async with rpool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        return {
            "status": "healthy",
            "service": "Hanning Securities Trade API",
            "read_from": READ_FROM,
            "timestamp": datetime.utcnow(),
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database connection failed: {str(e)}")


@app.get("/trades", response_model=list[TradeResponse])
async def list_trades(
    response: Response,
    account_id: Optional[str] = Query(None, description="依客戶帳號篩選"),
    stock_symbol: Optional[str] = Query(None, description="依股票代號篩選"),
    start_date: Optional[str] = Query(None, description="開始日期 (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="結束日期 (YYYY-MM-DD)"),
    limit: int = Query(50, ge=1, le=200, description="回傳筆數上限"),
):
    """列出交易紀錄（支援篩選）— 查詢走讀取連線池"""
    pool = await get_read_pool()
    response.headers["X-DB-Read"] = READ_FROM  # 讓呼叫端看得出這次查詢讀的是主庫還是複本

    query = "SELECT * FROM trades WHERE 1=1"
    params = []
    param_idx = 0

    if account_id:
        param_idx += 1
        query += f" AND account_id = ${param_idx}"
        params.append(account_id)

    if stock_symbol:
        param_idx += 1
        query += f" AND stock_symbol = ${param_idx}"
        params.append(stock_symbol)

    if start_date:
        param_idx += 1
        query += f" AND trade_time >= ${param_idx}"
        params.append(datetime.strptime(start_date, "%Y-%m-%d"))

    if end_date:
        param_idx += 1
        query += f" AND trade_time < ${param_idx}"
        params.append(datetime.strptime(end_date, "%Y-%m-%d"))

    param_idx += 1
    query += f" ORDER BY trade_time DESC LIMIT ${param_idx}"
    params.append(limit)

    async with pool.acquire() as conn:
        rows = await conn.fetch(query, *params)

    return [row_to_dict(row) for row in rows]


@app.post("/trades", response_model=TradeResponse, status_code=201)
async def create_trade(trade: TradeCreate):
    """新增交易紀錄"""
    pool = await get_db_pool()

    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            INSERT INTO trades (stock_symbol, stock_name, trade_type, quantity, price, account_id, status)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING *
            """,
            trade.stock_symbol,
            trade.stock_name,
            trade.trade_type,
            trade.quantity,
            trade.price,
            trade.account_id,
            trade.status,
        )

    return row_to_dict(row)


@app.get("/trades/{trade_id}", response_model=TradeResponse)
async def get_trade(trade_id: str, response: Response):
    """查詢單筆交易 — 查詢走讀取連線池

    注意：複本是非同步複製，剛寫入的資料可能有毫秒級延遲才查得到。
    交易查詢服務可以接受；若業務要求「寫完立刻讀到」，該查詢應改走主庫。
    """
    pool = await get_read_pool()
    response.headers["X-DB-Read"] = READ_FROM

    try:
        trade_uuid = uuid.UUID(trade_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid trade_id format")

    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM trades WHERE trade_id = $1", trade_uuid)

    if row is None:
        raise HTTPException(status_code=404, detail="Trade not found")

    return row_to_dict(row)
