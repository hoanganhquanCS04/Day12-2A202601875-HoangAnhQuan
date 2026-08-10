# Phiếu Phản Ánh — K3 Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Họ và tên: Hoàng Anh Quân  Mã học viên: 2A202601875

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Tình huống mình vừa gặp thật khi dựng compose: lúc đầu mình chưa tạo file
> `.env` mà chạy luôn `docker compose up -d`. Container `agent` start rồi tắt
> ngay, `docker compose logs agent` in ra `ValidationError: agent_api_key Field
> required`. Mình biết ngay thiếu gì và sửa trong 30 giây, khi vẫn còn đang nhìn
> màn hình.
>
> Nếu để mặc định `"changeme"` thì kịch bản đổi hoàn toàn: container start
> **thành công**, `/health` trả 200, healthcheck xanh, Railway báo "Deployed".
> Mọi dấu hiệu đều nói rằng mọi thứ ổn. Nhưng khóa bảo vệ `/ask` lúc đó là
> `changeme` — chuỗi nằm sẵn trong source code của một repo public, và cũng là
> một trong những chuỗi đầu tiên mà bot quét Internet thử. Người lạ gọi `/ask`
> được, mỗi lần gọi là một lần mình trả tiền LLM, và cost guard cũng không cứu
> được vì họ gửi `X-User-Id` khác nhau nên mỗi "user" có một ngân sách riêng.
>
> Điểm mấu chốt: lỗi cấu hình thì luôn xảy ra, chỉ khác nhau ở chỗ nó **hiện ra
> lúc nào**. Không có mặc định = lỗi hiện lúc deploy. Có mặc định = lỗi hiện lúc
> nhìn hóa đơn cuối tháng, và lúc đó khóa đã bị lộ nhiều ngày rồi.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log thật lấy từ `docker compose logs agent`:
>
> ```json
> {"event": "ask_completed", "level": "info", "timestamp": "2026-08-10T08:11:04.948132+00:00", "user_id": "sv-state-86205", "tokens_in": 131, "tokens_out": 44, "cost_usd": 4.605e-05}
> ```
>
> **Việc 1 — Tổng hợp chi phí theo user.** Vì `cost_usd` và `user_id` là hai
> trường riêng biệt có kiểu dữ liệu rõ ràng, mình trả lời được câu "hôm nay user
> nào tiêu nhiều tiền nhất" bằng một câu truy vấn (`group by user_id, sum
> cost_usd`), không cần đọc log bằng mắt. Với `print("đã trả lời xong")` thì
> trong dòng log không hề có con số chi phí — thông tin đó đã mất hẳn, không có
> cách nào lấy lại.
>
> **Việc 2 — Đặt cảnh báo tự động.** `level` và `event` là trường có giá trị cố
> định, nên mình đặt được rule kiểu "nếu số dòng `level=error` trong 5 phút vượt
> 20 thì bắn cảnh báo", hoặc "nếu 10 phút không có dòng `ask_completed` nào thì
> service có thể đang chết ngầm". `print()` in ra một chuỗi tự do — muốn đếm thì
> phải viết regex, và regex đó vỡ ngay lần đầu ai đó sửa lại câu chữ trong
> `print`.
>
> Một điểm nữa mình để ý khi làm: phải in **một dòng duy nhất** (`json.dumps`
> không `indent`) và bật `flush=True`. Cloud gom log theo từng dòng, JSON xuống
> dòng sẽ bị cắt thành nhiều mảnh không parse được; còn không flush thì Python
> giữ log trong buffer, container bị kill là mất luôn những dòng cuối — đúng
> những dòng cần nhất khi đi tìm nguyên nhân sự cố.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu, `FROM python:3.11`) | **1730 MB** (1.73 GB) |
| Multi-stage (`FROM python:3.11-slim`) | **270 MB** |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Chênh lệch ~1460 MB đến từ ba nguồn, xếp theo mức độ đóng góp:
>
> **1. Base image (~1000 MB).** `python:3.11` bản đầy đủ dựng trên Debian
> full: có gcc, make, git, các thư viện dev, tài liệu man. `python:3.11-slim`
> bỏ hết những thứ đó, chỉ giữ đủ để chạy Python. Đây là khoản lớn nhất và chỉ
> tốn đúng một chữ `-slim`.
>
> **2. Toolchain build bị vứt đi (~300 MB).** Stage `builder` của mình có
> `apt-get install build-essential` để phòng khi package nào không có wheel sẵn.
> Nhưng stage runtime chỉ `COPY --from=builder /install /usr/local` — tức là chỉ
> lấy **kết quả** cài đặt, còn compiler, header file, apt cache ở lại stage
> builder và không bao giờ trở thành layer của image cuối.
>
> **3. Build context thừa (vài chục MB).** Bản 1 stage dùng `COPY . .` nên nuốt
> luôn `.git` (toàn bộ lịch sử commit), `tests/`, `screenshots/`, `.venv` nếu có.
> Bản multi-stage chỉ `COPY app ./app` và `COPY utils ./utils`, cộng với
> `.dockerignore` chặn sẵn `.env`, `.git`, `__pycache__`, `.venv`.
>
> Vì sao con số này quan trọng chứ không chỉ để cho đẹp: mỗi lần deploy là một
> lần đẩy image qua mạng lên registry rồi kéo về node. 1.73 GB so với 270 MB là
> khác biệt giữa deploy 5 phút và deploy 40 giây — nhân với số lần deploy trong
> ngày. Chưa kể mục 3 còn là vấn đề bảo mật: thiếu `.dockerignore` thì `.env`
> nằm luôn trong image gửi lên registry.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Mình thêm đúng một dòng comment vào cuối `app/main.py` rồi `docker build` lại.
> Output thật:
>
> ```
> [builder 2/5] RUN apt-get install build-essential      CACHED
> [builder 4/5] COPY requirements.txt .                  CACHED
> [builder 5/5] RUN pip install --prefix=/install ...    CACHED
> [runtime  2/6] RUN useradd --uid 10001 appuser         CACHED
> [runtime  4/6] COPY --from=builder /install /usr/local CACHED
> [runtime  5/6] COPY app ./app                          chạy lại
> [runtime  6/6] COPY utils ./utils                      chạy lại
> ```
>
> Toàn bộ phần cài dependency được dùng lại, chỉ hai layer copy source chạy lại.
> Build hoàn tất trong khoảng 4 giây.
>
> **Cơ chế:** Docker cache theo từng layer, và huỷ cache **từ layer đầu tiên bị
> thay đổi trở đi** — mọi layer sau đó đều bị coi là không còn tin được. Với
> `COPY requirements.txt` thì cache chỉ vỡ khi chính file đó đổi; sửa code không
> đụng gì tới nó nên toàn bộ dây chuyền phía trên đứng yên.
>
> **Nếu đặt `COPY . .` trước `RUN pip install`:** layer `COPY . .` vỡ cache mỗi
> lần bất kỳ file nào trong repo đổi — kể cả sửa README hay thêm một dấu phẩy.
> Vì `RUN pip install` nằm **sau** nó, layer pip cũng bị huỷ theo và phải tải
> lại toàn bộ thư viện từ PyPI. Đây chính là Dockerfile ban đầu của lab, và mình
> đo được nó mất khoảng 40–60 giây mỗi lần build thay vì 4 giây. Trong CI, con
> số đó nhân với mọi commit của mọi người trong team.
>
> Quy tắc rút ra: **xếp lệnh theo tần suất thay đổi, ít đổi nhất lên trên.**
> Base image → hệ thống → dependency → code.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Chuỗi sự kiện, từng bước một:
>
> 1. **Có lỗ hổng trong app.** Ví dụ một endpoint nhận input rồi đưa vào
>    `subprocess`/`eval`, hoặc một thư viện deserialization dính CVE. Kẻ tấn
>    công chạy được lệnh tuỳ ý *bên trong* container.
> 2. **Leo quyền trong container.** Nếu process là root, kẻ tấn công có UID 0:
>    ghi được vào `/usr/local`, `/etc`, cài thêm công cụ bằng `apt`, sửa cả code
>    Python của app để cắm backdoor bền vững qua các lần restart.
> 3. **Vượt ra khỏi container.** Đây là bước cần root. Container không phải máy
>    ảo — nó dùng chung kernel với host, chỉ bị ngăn cách bằng namespace,
>    cgroup và capability. Có UID 0 nghĩa là giữ được các capability nguy hiểm
>    (`CAP_SYS_ADMIN`, `CAP_DAC_OVERRIDE`...) để khai thác lỗ hổng kernel, hoặc
>    lạm dụng cấu hình sai phổ biến: volume mount `/var/run/docker.sock` (điều
>    khiển được toàn bộ Docker daemon của host), mount `/` vào container, hoặc
>    cờ `--privileged`.
> 4. **Root trên host.** UID 0 trong container ánh xạ thẳng thành UID 0 trên
>    host (trừ khi bật user namespace remapping — mặc định là tắt). Thoát ra là
>    thành root thật.
>
> **`USER appuser` cắt đứt ở bước 2 → 3.** Sau khi mình `RUN useradd --uid 10001
> appuser` và `USER appuser`, process uvicorn chạy với UID 10001. Kẻ tấn công
> chiếm được app thì cũng chỉ là user 10001: không ghi được vào `/usr/local`,
> không `apt install` được, không có capability nào để đụng tới kernel, và nếu
> có sock/volume mount sai thì cũng bị chặn bởi quyền file. Kịch bản tệ nhất tụt
> từ "root trên host" xuống "đọc được code app trong một container".
>
> Đây là defence in depth: `USER` **không** vá lỗ hổng ở bước 1, nó chỉ giới hạn
> thiệt hại khi bước 1 đã xảy ra. Và vì lỗ hổng ở bước 1 kiểu gì cũng có (thư
> viện nào chả có CVE), phần giới hạn thiệt hại mới là phần dùng đến thật.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> **20 request trong 2 giây** — gấp đôi hạn mức.
>
> Cách đạt được: bộ đếm theo phút đồng hồ dùng key kiểu `ratelimit:u1:10:00`,
> và nó về 0 tại đúng giây `:00` của phút kế tiếp. Kẻ gọi chỉ cần canh mốc đó:
>
> ```
> 10:00:59.0 → gửi 10 request  → bộ đếm phút 10:00 = 10/10, vừa chạm trần
> 10:01:00.0 → bộ đếm reset, key mới là 10:01
> 10:01:01.0 → gửi tiếp 10 request → bộ đếm phút 10:01 = 10/10, vẫn "đúng luật"
> ```
>
> Cả 20 request nằm trong khoảng ~2 giây, và không có bộ đếm nào bị vượt: bộ đếm
> phút 10:00 thấy 10, bộ đếm phút 10:01 thấy 10. Lỗ hổng nằm ở chỗ **ranh giới
> cửa sổ là cố định và ai cũng đoán được** — cứ giây `:00`.
>
> Với sliding window mình cài, mọi request được lưu vào ZSET với `score =
> timestamp`, và mỗi lần kiểm tra đều `zremrangebyscore(key, 0, now - 60)` để
> vứt phần đã trôi ra khỏi cửa sổ rồi mới `zcard`. Ở thời điểm 10:01:01, cửa sổ
> là `[10:00:01, 10:01:01]` — 10 request lúc 10:00:59 vẫn nằm trong đó, nên bộ
> đếm đọc ra 10 và request thứ 11 bị chặn ngay. Không có mốc reset cố định nào
> để canh, vì cửa sổ trượt theo từng request.
>
> Cái giá phải trả: lưu từng timestamp tốn bộ nhớ hơn một biến đếm. Nên mình
> `expire(key, 60)` để Redis tự dọn key của user đã ngừng gọi.
>
> Hai chi tiết mình suýt làm sai:
> - **Kiểm tra trước, ghi nhận sau.** Nếu `zadd` trước rồi mới `zcard`, request
>   thứ 10 tự đếm cả chính nó thành 10 và bị chặn — hạn mức thật thành 9.
> - **Member phải duy nhất** (`f"{now}:{uuid4().hex}"`). Hai request cùng
>   timestamp mà trùng member thì ZSET chỉ giữ một, đếm bị thiếu.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Khác nhau ở **đơn vị đo** và ở **thứ mà chúng bảo vệ**:
>
> | | Rate limit | Cost guard |
> |---|---|---|
> | Đếm cái gì | số request | số tiền (USD) |
> | Cửa sổ | 60 giây trượt | tháng dương lịch (`cost:<user>:2026-08`) |
> | Bảo vệ khỏi | quá tải, spam, scraping | vỡ ngân sách |
> | Mã lỗi | 429 | 402 |
>
> Mấu chốt là **số request và số tiền không tỉ lệ với nhau**: một request có thể
> tốn 20 token, request khác tốn 50.000 token. Đo một chiều thì chiều kia trôi
> tự do.
>
> **Rate limit cho qua, cost guard phải chặn:** user dán vào một tài liệu 40 trang
> rồi hỏi "tóm tắt giúp mình", mỗi request ~50.000 token input. Gửi 8 request
> trong một phút — rate limit thấy 8 < 10, cho qua hết. Nhưng 8 × 50.000 =
> 400.000 token, tính theo giá gpt-4o-mini là vài chục cent chỉ trong một phút;
> duy trì nhịp đó vài giờ là hết sạch ngân sách 10 USD. Cost guard là thứ duy
> nhất nhìn thấy điều này, vì nó cộng dồn `cost_usd` thật do LLM trả về chứ
> không đếm số lần gọi.
>
> **Cost guard cho qua, rate limit phải chặn:** một script bị lỗi vòng lặp gọi
> `/ask` 200 lần/giây với câu hỏi ngắn "hi". Mỗi request tốn ~0,00002 USD, tổng
> tiền cả phút chưa tới 1 cent — cost guard nhìn vào thấy `spent` còn cách
> budget rất xa nên vui vẻ cho qua. Nhưng 200 req/s làm ngập uvicorn, nuốt hết
> connection pool của Redis, và user khác gọi vào thì timeout. Ở đây vấn đề
> không phải tiền mà là **tài nguyên và tính sẵn sàng** — chỉ rate limit chặn được.
>
> Vì vậy trong `/ask` mình gọi cả hai, và gọi **trước** `ask_llm`:
> `limiter.check()` → `guard.check()` → mới gọi LLM. Chặn sau khi đã gọi LLM thì
> vừa mất tiền vừa trả lỗi cho user — tệ hơn cả hai đằng.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Thứ tự sự kiện:
>
> 1. **t=0s** — Redis mất kết nối (failover, restart, nấc mạng). Endpoint gộp
>    trên **cả 3** container cùng gọi `ping()` và cùng thất bại → cả 3 trả 503.
>    Điểm chết người: 3 container không hỏng độc lập, chúng hỏng **cùng lúc** vì
>    dùng chung một dependency.
> 2. **t≈0–15s** — Orchestrator đọc 503 từ **liveness** probe và hiểu là "process
>    hỏng, cần restart" (đó là ý nghĩa của liveness). Sau đủ số lần retry, nó
>    ra lệnh restart. Cả 3 container cùng bị giết trong vòng vài giây.
> 3. **t≈15–30s** — Cả 3 container khởi động lại. Không còn instance nào phục
>    vụ: **downtime 100%**, dù nguyên nhân gốc chỉ là Redis nấc 30 giây. Mọi
>    request đang xử lý dở bị cắt giữa chừng.
> 4. **t≈30s** — Container mới lên, gọi Redis, Redis **vẫn chưa** hồi (mới 30
>    giây). Health check lại 503 → orchestrator restart tiếp. Vòng lặp
>    `CrashLoopBackOff`: restart → fail → restart, mỗi vòng backoff dài thêm.
> 5. **t≈30s+** — Redis hồi, nhưng 3 container đang ở giữa chu kỳ backoff (có
>    thể 40–80 giây). Service vẫn chết thêm một lúc nữa **sau khi** nguyên nhân
>    gốc đã hết.
> 6. Nếu ứng dụng có warm-up (nạp cache, mở connection pool), 3 container cùng
>    khởi động lại còn tạo một đợt tải dồn vào Redis vừa hồi, đủ để dìm nó xuống
>    lần nữa.
>
> Tổng kết: **Redis nấc 30 giây → service chết 1–2 phút.** Sự cố nhỏ được khuếch
> đại thành sự cố toàn hệ thống, và thủ phạm chính là cái health check.
>
> Tách đúng thì chuyện diễn ra thế này: `/health` (liveness) không đụng Redis nên
> vẫn 200 → **không container nào bị restart**. `/ready` (readiness) trả 503 →
> load balancer **ngừng gửi** request mới vào (không giết container). Redis hồi
> ở giây 30, `/ready` trả 200 lại, LB đưa cả 3 instance về vòng xoay. Tổng thiệt
> hại: 30 giây trả lỗi, không có restart, không có crash loop.
>
> Một câu để nhớ: 503 ở liveness nghĩa là **"giết tôi đi"**, 503 ở readiness
> nghĩa là **"khoan gửi khách cho tôi"**. Trộn hai câu đó làm một là biến mọi
> trục trặc dependency thành một đợt restart toàn cụm.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Kết quả thật của mình. Mình gọi lần lượt vào **3 container khác nhau** (compose
> map ra cổng 8000/8001/8002) với cùng một `X-User-Id`:
>
> ```
> agent trên cổng 8000  ->  history_length = 0
> agent trên cổng 8001  ->  history_length = 2
> agent trên cổng 8002  ->  history_length = 4
> agent trên cổng 8000  ->  history_length = 6
> agent trên cổng 8001  ->  history_length = 8
>
> $ docker compose exec redis redis-cli LLEN history:sv-state
> 10
> ```
>
> Tăng đều 0 → 2 → 4 → 6 → 8, mỗi lượt +2 (một message `user` + một message
> `assistant`), **bất kể request rơi vào container nào**. Redis giữ đúng 10
> message. Đó là điều mình muốn thấy: 3 container nhưng chỉ một nguồn sự thật.
>
> **Nếu lưu bằng dict Python trong process**, mỗi container có RAM riêng nên mỗi
> container đếm riêng. Với LB round-robin, cùng dãy request đó sẽ ra:
>
> ```
> request 1 → container A → history_length = 0   (A: 0 → 2)
> request 2 → container B → history_length = 0   (B chưa biết gì về A!)
> request 3 → container C → history_length = 0   (C cũng vậy)
> request 4 → container A → history_length = 2
> request 5 → container B → history_length = 2
> ```
>
> Con số **nhảy lung tung và lặp lại** thay vì tăng đều: 0, 0, 0, 2, 2… Về phía
> người dùng, triệu chứng là agent "mất trí nhớ" ngẫu nhiên — hỏi tiếp một câu
> thì nó quên mất mình vừa nói gì, nhưng lần khác lại nhớ. Loại bug này rất khó
> bắt vì **nó không xảy ra khi chạy 1 instance ở laptop**; chỉ hiện ra khi lên
> production có nhiều instance, và hiện ra một cách ngẫu nhiên.
>
> Còn một hệ quả nữa: container bị restart (deploy bản mới, OOM, node bảo trì)
> là toàn bộ dict bay sạch. Với Redis thì lịch sử sống sót qua restart, và mình
> còn đặt được `ltrim` giữ 20 message gần nhất (chặn prompt phình vô hạn = chặn
> tiền token phình vô hạn) và `expire` 7 ngày để Redis không đầy dần.
>
> Đây chính là nguyên tắc "processes are stateless" trong 12-Factor: state phải
> nằm ở backing service mà mọi instance cùng nhìn thấy. Có vậy mới scale ngang
> được, và mới restart container thoải mái mà không mất dữ liệu.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> Nói thẳng trước: mình **chưa deploy lên được cloud** (lý do ghi trong
> `DEPLOYMENT.md`), nên lỗi dưới đây là lỗi mình gặp thật ở bước dựng stack bằng
> Docker — cùng loại "chạy ở chỗ khác thì hỏng" mà CP5 nói tới.
>
> **Thông báo lỗi:**
>
> ```
> error during connect: Get "http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/v1.51/info":
> open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
> ```
>
> **Cách tìm ra nguyên nhân:** thoạt nhìn mình tưởng Docker chưa cài, nhưng
> `docker --version` vẫn in ra `28.5.1` bình thường. Chi tiết đó tách được vấn
> đề làm hai: **client** có, **daemon** không. Đọc kỹ thông báo thì thấy nó
> không phải lỗi cú pháp mà là lỗi **kết nối** tới named pipe
> `dockerDesktopLinuxEngine` — tức là client tìm daemon ở đúng chỗ nhưng không
> có ai trả lời. Kiểm tra `Get-Process "Docker Desktop"` → không có tiến trình
> nào. Vậy là Docker Desktop chưa khởi động.
>
> **Cách sửa:** khởi động Docker Desktop, chờ engine lên (`docker info` trả về
> `28.5.1` thay vì lỗi), rồi chạy lại `docker build`. Hậu quả kèm theo: trong
> lúc daemon chưa lên, các test có mark `docker` trong `test_cp2.py` bị **skip**
> chứ không phải fail — nên nhìn qua tưởng đã xong CP2, thực ra chưa có gì được
> build. Sau khi bật daemon lên chạy lại thì cả hai test build mới thật sự chạy
> và pass, image đo được 270MB.
>
> **Điều rút ra:** thông báo lỗi hạ tầng hầu như luôn chỉ đúng chỗ hỏng nếu chịu
> đọc hết — chữ "connect" và tên pipe đã nói rõ đây là lỗi kết nối tới daemon,
> không phải lỗi Dockerfile. Và bài học thứ hai đắt hơn: **test bị skip không
> phải test pass.** Đó cũng là lý do CI phải chạy trên máy sạch có Docker thật —
> để không ai vô tình "xanh" nhờ một bước bị bỏ qua.
>
> Về phía cloud, hai lỗi mình đã chủ động phòng trước trong Dockerfile vì biết
> chúng là nguyên nhân phổ biến nhất làm health check timeout:
> `--host 0.0.0.0` (bind `127.0.0.1` thì ngoài container gọi không tới) và
> `--port ${PORT:-8000}` (Railway/Render tự gán cổng, cố định 8000 là platform
> gọi vào chỗ không có ai nghe).
