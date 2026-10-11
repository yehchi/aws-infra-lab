#!/usr/bin/env python3
"""
塞測試用交易資料，讓查詢與壓測更接近真實情境

用法：
  python3 seed.py http://<alb_dns_name> --count 200
"""

import argparse
import json
import random
import sys
import urllib.request

STOCKS = [
    ("2330", "台積電", 580), ("2317", "鴻海", 105), ("2454", "聯發科", 1250),
    ("2308", "台達電", 380), ("2881", "富邦金", 85), ("2882", "國泰金", 62),
    ("2412", "中華電", 125), ("2603", "長榮", 190),
]

# Windows 終端機（Big5 編碼）印不出部分符號時，以 ? 取代而不是整個程式當掉
sys.stdout.reconfigure(errors="replace")


def main():
    ap = argparse.ArgumentParser(description="塞測試交易資料")
    ap.add_argument("base_url")
    ap.add_argument("--count", type=int, default=200)
    args = ap.parse_args()

    url = args.base_url.rstrip("/") + "/trades"
    ok = 0
    for i in range(args.count):
        symbol, name, base_price = random.choice(STOCKS)
        body = {
            "stock_symbol": symbol,
            "stock_name": name,
            "trade_type": random.choice(["BUY", "SELL"]),
            "quantity": random.choice([100, 500, 1000, 2000]),
            "price": round(base_price * random.uniform(0.95, 1.05), 2),
            "account_id": f"ACC-{random.randint(1, 20):03d}",
        }
        req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                ok += r.status == 201
        except Exception as e:
            print(f"第 {i + 1} 筆失敗：{e}")
    print(f"完成：成功寫入 {ok} / {args.count} 筆")


if __name__ == "__main__":
    main()
