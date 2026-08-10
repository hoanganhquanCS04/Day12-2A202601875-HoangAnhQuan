# Thông Tin Deploy — Checkpoint 5

> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Hoàng Anh Quân |
| Mã học viên | 2A202601875 |
| Repo | https://github.com/hoanganhquanCS04/Day12-2A202601875-HoangAnhQuan |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | *chưa có — đang dùng phương án dự phòng, xem mục cuối trang* |
| Địa chỉ đang chạy | http://localhost:8000 (agent), http://localhost:80 (qua Nginx load balancer) |
| Platform dự kiến | Railway (`railway.toml` đã cấu hình sẵn); Render là phương án hai (`render.yaml` đã cấu hình sẵn) |
| Ngày chạy | 2026-08-10 |
| Cách chạy | `docker compose up -d --scale agent=3` |

## Biến Môi Trường Đã Set

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Nguồn giá trị |
|------|--------|---------------|
| `PORT` | ✅ | compose set `8000`; trên cloud thì platform tự gán, app đọc `${PORT:-8000}` |
| `AGENT_API_KEY` | ✅ | sinh bằng `secrets.token_urlsafe(32)`, nằm trong `.env` ở máy (đã gitignore). Trên cloud sẽ đặt trong dashboard, không nằm trong repo |
| `REDIS_URL` | ✅ | `redis://redis:6379/0` — service `redis` trong compose. Trên cloud sẽ là Redis add-on của platform |
| `RATE_LIMIT_PER_MINUTE` | ✅ | 10 |
| `MONTHLY_BUDGET_USD` | ✅ | 10.0 |
| `LOG_LEVEL` | ✅ | INFO |

Không biến nào có giá trị nằm trong source code — đúng nguyên tắc 12-Factor:
cùng một image chạy ở laptop và trên cloud, chỉ khác biến môi trường.

## Lệnh Kiểm Tra

```bash
URL=http://localhost:8000

# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i $URL/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i $URL/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST $URL/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST $URL/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST $URL/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

```
$ docker compose ps
NAME                                     SERVICE   STATUS                    PORTS
day12-2a202601875-hoanganhquan-agent-1   agent     Up 2 minutes (healthy)    0.0.0.0:8000->8000/tcp
day12-2a202601875-hoanganhquan-agent-2   agent     Up 2 minutes (healthy)    0.0.0.0:8001->8000/tcp
day12-2a202601875-hoanganhquan-agent-3   agent     Up 2 minutes (healthy)    0.0.0.0:8002->8000/tcp
day12-2a202601875-hoanganhquan-nginx-1   nginx     Up 2 minutes              0.0.0.0:80->80/tcp
day12-2a202601875-hoanganhquan-redis-1   redis     Up 2 minutes (healthy)    0.0.0.0:6379->6379/tcp

$ docker images day12-agent:prod
day12-agent:prod   270MB          # bản 1-stage trước đó: 1.73GB

$ curl -i http://localhost:8000/health
HTTP/1.1 200 OK
content-type: application/json
{"status":"ok","service":"day12-agent","version":"1.0.0"}

$ curl -i http://localhost:8000/ready
HTTP/1.1 200 OK
content-type: application/json
{"status":"ready","redis":true}

$ # Không có API key
HTTP 401

$ # Sai API key
HTTP 401

$ # Đúng API key
{"answer":"Theo mình hiểu, Docker la gi liên quan tới cách hệ thống được đóng gói
và vận hành. Điểm mấu chốt là tách cấu hình ra khỏi code và giữ service ở trạng
thái stateless.","user_id":"sv01","history_length":0,"cost_usd":2.505e-05,
"tokens":{"in":3,"out":41}}

$ # Rate limit: 15 request liên tiếp, hạn mức 10/phút
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429

$ # Stateless: cùng một X-User-Id, gọi lần lượt vào 3 container khác nhau
  agent trên cổng 8000  ->  history_length = 0
  agent trên cổng 8001  ->  history_length = 2
  agent trên cổng 8002  ->  history_length = 4
  agent trên cổng 8000  ->  history_length = 6
  agent trên cổng 8001  ->  history_length = 8

$ docker compose exec redis redis-cli LLEN history:sv-state
10
```

## Ảnh Chụp Màn Hình

| File | Nội dung |
|------|----------|
| `screenshots/dashboard.png` | `docker compose ps` — 3 agent + redis + nginx, tất cả healthy; dung lượng image |
| `screenshots/health.png` | `/health` trả 200 và `/ready` trả 200 (đã nối được Redis) |
| `screenshots/api-security.png` | 401 khi thiếu/sai key, 200 khi đúng key, 429 khi vượt rate limit |
| `screenshots/stateless-scale.png` | Cùng user gọi vào 3 container khác nhau, `history_length` vẫn tăng đều |

---

## Phương Án Dự Phòng — Lý Do

Đang dùng phương án dự phòng (`LOCAL_FALLBACK=true`), CP5 tối đa 60% điểm.

```
Lý do: chưa deploy được lên Railway/Render vì bước đăng ký tài khoản cần xác
thực qua trình duyệt (đăng nhập GitHub OAuth + xác minh thanh toán để mở free
tier). Toàn bộ phần còn lại của CP5 đã sẵn sàng cho việc deploy:

  - Dockerfile multi-stage, đọc $PORT từ biến môi trường (không cố định 8000),
    bind 0.0.0.0, có HEALTHCHECK — đúng thứ Railway/Render yêu cầu.
  - railway.toml và render.yaml đã cấu hình đầy đủ (builder dockerfile,
    healthcheckPath /health, Redis add-on, AGENT_API_KEY khai báo sync: false
    nên Render hỏi giá trị lúc deploy chứ không lấy từ repo).
  - Không có secret nào nằm trong repo; tất cả đọc từ biến môi trường.

Stack đã chạy thật bằng docker compose với 3 instance agent + Redis + Nginx
load balancer, và đã kiểm tra đủ: /health 200, /ready 200 (nối được Redis),
/ask 401 khi thiếu key, 200 khi đúng key, 429 khi vượt rate limit, và lịch sử
hội thoại dùng chung giữa 3 container qua Redis.
```

### Khi deploy được lên cloud thì làm tiếp

```bash
# Railway
npm i -g @railway/cli
railway login
railway init
railway add --database redis            # tự sinh REDIS_URL
railway variables --set AGENT_API_KEY=<khóa của bạn> \
                  --set RATE_LIMIT_PER_MINUTE=10 \
                  --set MONTHLY_BUDGET_USD=10.0 \
                  --set LOG_LEVEL=INFO
railway up
railway domain                          # sinh URL công khai
```

Sau đó: điền URL thật vào mục **Public URL** ở đầu file, đặt lại
`LOCAL_FALLBACK=false` và điền `DEPLOY_API_KEY` trong `.env` (khóa của chính
service vừa deploy, không phải token của Railway), rồi chạy lại
`pytest tests/test_cp5.py -v`.
