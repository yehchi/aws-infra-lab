# ============================================================
# Dockerfile — IBM 證券交易紀錄查詢服務
# Multi-stage build：先裝 dependencies，再複製程式碼
# 這樣改程式碼時不用重新裝 dependencies，build 更快
# ============================================================

FROM python:3.12-slim AS base

# 設定工作目錄
WORKDIR /app

# 先複製 requirements.txt 並安裝（利用 Docker layer cache）
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 複製應用程式
COPY main.py .

# 開放 port 8000（FastAPI 預設）
EXPOSE 8000

# 啟動指令
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
