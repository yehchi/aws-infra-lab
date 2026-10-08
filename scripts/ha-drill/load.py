#!/usr/bin/env python3
"""
壓力測試 — 模擬結算日尖峰流量，把 ECS 的 CPU 推高以觸發 Auto Scaling

用法：
  python3 load.py http://<alb_dns_name> --threads 60 --duration 600

每 10 秒印一次吞吐量與錯誤數。只用 Python 標準函式庫。
"""

import argparse
import threading
import time
import urllib.request


def worker(url, timeout, stop, stats, lock):
    while not stop.is_set():
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                r.read()
                ok = r.status == 200
        except Exception:
            ok = False
        with lock:
            stats["ok" if ok else "err"] += 1


def main():
    ap = argparse.ArgumentParser(description="壓力測試（觸發 Auto Scaling）")
    ap.add_argument("base_url")
    ap.add_argument("--path", default="/trades?limit=50", help="壓測路徑（預設會查資料庫的 /trades）")
    ap.add_argument("--threads", type=int, default=60, help="同時連線數（預設 60）")
    ap.add_argument("--duration", type=int, default=600, help="持續秒數（預設 600 = 10 分鐘）")
    ap.add_argument("--timeout", type=float, default=10.0)
    args = ap.parse_args()

    url = args.base_url.rstrip("/") + args.path
    stop = threading.Event()
    lock = threading.Lock()
    stats = {"ok": 0, "err": 0}
    threads = [threading.Thread(target=worker, args=(url, args.timeout, stop, stats, lock), daemon=True)
               for _ in range(args.threads)]

    print(f"壓測 {url}：{args.threads} 個連線，持續 {args.duration} 秒（Ctrl+C 可提前結束）")
    for t in threads:
        t.start()

    start = time.time()
    last_ok = last_err = 0
    try:
        while time.time() - start < args.duration:
            time.sleep(10)
            with lock:
                ok, err = stats["ok"], stats["err"]
            elapsed = time.time() - start
            rps = (ok - last_ok) / 10
            print(f"[{elapsed:5.0f}s] {rps:7.1f} req/s · 錯誤 {err - last_err:4d} · 累計成功 {ok}", flush=True)
            last_ok, last_err = ok, err
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()

    total = time.time() - start
    print(f"\n結束：{total:.0f} 秒 · 成功 {stats['ok']} · 錯誤 {stats['err']} · 平均 {stats['ok'] / total:.1f} req/s")


if __name__ == "__main__":
    main()
