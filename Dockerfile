# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (bản production-ready)
#
#   [x] Multi-stage: `builder` cài dependency, `runtime` chỉ nhận kết quả
#   [x] Base image slim ở cả hai stage
#   [x] COPY requirements.txt + pip install TRƯỚC khi COPY source code
#   [x] Chạy bằng user thường `appuser` (uid 10001), không phải root
#   [x] HEALTHCHECK gọi vào /health
#   [x] Đọc cổng từ biến môi trường PORT (Railway/Render tự gán)
#
# Build thử: docker build -t day12-agent:prod .
#            docker images day12-agent:prod
# ═══════════════════════════════════════════════════════════════════

# ─────────────────────────── STAGE 1: builder ───────────────────────
# Stage này được phép nặng: nó có compiler, có cache của pip, và bị VỨT ĐI
# sau khi build xong. Chỉ stage cuối mới trở thành image thật.
FROM python:3.11-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

# Một số package cần biên dịch từ source khi không có wheel sẵn
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Chỉ copy requirements trước: layer này chỉ vỡ cache khi file này đổi,
# nên sửa một dòng trong app/main.py KHÔNG kéo theo việc cài lại thư viện.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ─────────────────────────── STAGE 2: runtime ───────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Container chạy root nghĩa là ai thoát được khỏi app cũng là root trong
# container — và với một lỗ hổng kernel/misconfig thì thành root trên host.
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

# Chỉ mang KẾT QUẢ cài đặt sang, không mang theo compiler và apt cache
COPY --from=builder /install /usr/local

# Source code copy SAU cùng — thứ thay đổi nhiều nhất nằm ở layer cuối
COPY app ./app
COPY utils ./utils

USER appuser

EXPOSE 8000

# Docker tự gọi endpoint này; 3 lần liên tiếp lỗi → container bị đánh dấu unhealthy
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.getenv('PORT', '8000') + '/health').read()" || exit 1

# 0.0.0.0 chứ không phải 127.0.0.1 (bind localhost = ngoài container gọi không tới).
# ${PORT:-8000} vì Railway/Render/Cloud Run tự gán cổng lúc chạy.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
