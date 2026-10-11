#!/usr/bin/env python3
"""
HA 演練探測器 — 持續打 API，記錄每次成功 / 失敗，結束時算出中斷時間

同時探測兩個路徑，用來區分「哪一層出問題」：
  /health/live      只檢查程式存活（不碰資料庫）
  /trades?limit=1   會實際查資料庫

用法（Ctrl+C 結束並印出統計）：
  python3 probe.py http://<alb_dns_name>
  python3 probe.py http://<alb_dns_name> --interval 0.5 --timeout 3 --log probe.csv

只用 Python 標準函式庫，CloudShell 可以直接執行。
"""

import argparse
import csv
import signal
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime

PATHS = {
    "live": "/health/live",
    "db": "/trades?limit=1",
}

# Windows 終端機（Big5 編碼）印不出部分符號時，以 ? 取代而不是整個程式當掉
sys.stdout.reconfigure(errors="replace")


def probe_once(url, timeout):
    """打一次請求，回傳 (ok, status, latency_ms, error)"""
    start = time.monotonic()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            resp.read()
            ms = (time.monotonic() - start) * 1000
            return resp.status == 200, resp.status, ms, ""
    except urllib.error.HTTPError as e:
        ms = (time.monotonic() - start) * 1000
        return False, e.code, ms, f"HTTP {e.code}"
    except Exception as e:  # timeout、連線被拒等
        ms = (time.monotonic() - start) * 1000
        return False, 0, ms, type(e).__name__


class Tracker:
    """追蹤某個路徑的成功 / 失敗，並記錄每一段連續失敗（中斷區間）"""

    def __init__(self, name):
        self.name = name
        self.ok = 0
        self.fail = 0
        self.outages = []  # [(start_ts, end_ts, fail_count, errors)]
        self._cur_start = None
        self._cur_fails = 0
        self._cur_errors = set()
        self.max_ms = 0.0

    def record(self, ts, ok, ms, err):
        self.max_ms = max(self.max_ms, ms)
        if ok:
            self.ok += 1
            if self._cur_start is not None:
                self.outages.append((self._cur_start, ts, self._cur_fails, sorted(self._cur_errors)))
                self._cur_start, self._cur_fails, self._cur_errors = None, 0, set()
        else:
            self.fail += 1
            if self._cur_start is None:
                self._cur_start = ts
            self._cur_fails += 1
            self._cur_errors.add(err)

    def close(self, ts):
        if self._cur_start is not None:
            self.outages.append((self._cur_start, ts, self._cur_fails, sorted(self._cur_errors) + ["(結束時仍未恢復)"]))


def fmt(ts):
    return datetime.fromtimestamp(ts).strftime("%H:%M:%S.%f")[:-3]


def main():
    ap = argparse.ArgumentParser(description="HA 演練探測器")
    ap.add_argument("base_url", help="例如 http://aws-infra-lab-prod-alb-xxxx.ap-northeast-1.elb.amazonaws.com")
    ap.add_argument("--interval", type=float, default=0.5, help="探測間隔秒數（預設 0.5）")
    ap.add_argument("--timeout", type=float, default=3.0, help="單次請求逾時秒數（預設 3）")
    ap.add_argument("--log", default="probe.csv", help="逐筆紀錄輸出檔（預設 probe.csv）")
    args = ap.parse_args()

    base = args.base_url.rstrip("/")
    trackers = {k: Tracker(k) for k in PATHS}
    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())

    started = time.time()
    print(f"開始探測 {base}（每 {args.interval}s，逾時 {args.timeout}s）— Ctrl+C 結束")
    print("時間          live   db     db延遲")

    with open(args.log, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["timestamp", "path", "ok", "status", "latency_ms", "error"])
        while not stop.is_set():
            tick = time.time()
            line = [fmt(tick)]
            for key, path in PATHS.items():
                ok, status, ms, err = probe_once(base + path, args.timeout)
                trackers[key].record(tick, ok, ms, err)
                w.writerow([f"{tick:.3f}", path, int(ok), status, f"{ms:.0f}", err])
                line.append(("OK " if ok else "FAIL") + "  ")
                if key == "db":
                    line.append(f"{ms:6.0f}ms" + ("" if ok else f"  {err}"))
            f.flush()
            print("  ".join(line), flush=True)
            elapsed = time.time() - tick
            stop.wait(max(0.0, args.interval - elapsed))

    end = time.time()
    for t in trackers.values():
        t.close(end)

    print("\n" + "=" * 60)
    print(f"探測時間：{fmt(started)} → {fmt(end)}（共 {end - started:.0f} 秒）")
    for key, t in trackers.items():
        total = t.ok + t.fail
        rate = 100.0 * t.ok / total if total else 0
        print(f"\n[{key}] {PATHS[key]}")
        print(f"  成功 {t.ok} / 失敗 {t.fail}（可用率 {rate:.2f}%）· 最慢一次 {t.max_ms:.0f} ms")
        if not t.outages:
            print("  中斷區間：無 ✅")
        for s, e, n, errs in t.outages:
            print(f"  中斷 {fmt(s)} → {fmt(e)}：{e - s:.1f} 秒（連續失敗 {n} 次，{', '.join(errs)}）")
    print("=" * 60)
    print(f"逐筆紀錄：{args.log}")


if __name__ == "__main__":
    sys.exit(main())
