# Local development

## Yêu cầu

- JDK 17.
- Docker Desktop hoặc Docker Engine + Compose.
- Git.
- Cổng trống: `5432`, `5672`, `6379`, `8080`, `9000`, `9001`, `15672`.

## 1. Cấu hình môi trường

Tại thư mục gốc:

```bash
cp .env.example .env
```

Trên Windows Command Prompt:

```bat
copy .env.example .env
```

Thay các placeholder của PostgreSQL, JWT, MinIO, SMTP và payment sandbox. Không commit `.env`; không tái sử dụng secret của môi trường thật cho local/test.

Lưu ý: Docker Compose tự đọc `.env`, nhưng Spring Boot chạy từ Gradle **không tự đọc file này**. Cần khai báo các biến trong Run/Debug Configuration của IDE hoặc nạp chúng vào process shell.

Ví dụ PowerShell an toàn để nạp `.env` vào process hiện tại:

```powershell
Get-Content .env |
  Where-Object { $_ -and -not $_.StartsWith('#') } |
  ForEach-Object {
    $name, $value = $_.Split('=', 2)
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
  }
```

## 2. Khởi động hạ tầng

```bash
docker compose up -d
docker compose ps
```

| Dịch vụ | Port | Mục đích |
|---|---:|---|
| PostgreSQL | 5432 | Database chính |
| Redis | 6379 | Cache/counter |
| RabbitMQ AMQP | 5672 | Message broker |
| RabbitMQ UI | 15672 | Quan sát queue/DLQ |
| MinIO API | 9000 | Object storage |
| MinIO Console | 9001 | Quản trị object storage |

Compose hiện chỉ chạy hạ tầng; application Spring Boot vẫn chạy trực tiếp bằng Gradle/IDE.

## 3. Chạy test

```bash
cd ticketing
./gradlew test
```

Windows:

```bat
cd ticketing
gradlew.bat test
```

Test context hiện cần PostgreSQL local và Flyway migration. Cấu hình có thể được override qua `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, `SPRING_RABBITMQ_HOST` và `SPRING_REDIS_HOST`.

Report HTML sau khi chạy: `ticketing/build/reports/tests/test/index.html`.

## 4. Chạy application

```bash
cd ticketing
./gradlew bootRun
```

Endpoints kiểm tra:

- `GET http://localhost:8080/actuator/health`
- `http://localhost:8080/swagger-ui.html`
- `http://localhost:8080/v3/api-docs`

## 5. Smoke test đề xuất

1. Health trả `UP`.
2. Đăng ký/đăng nhập và gọi `/api/v1/auth/me` với JWT.
3. Tạo category/venue/event bằng role phù hợp, sau đó publish event.
4. Tạo area, seat, ticket type, sale phase và inventory.
5. Giữ một ghế; request thứ hai vào cùng ghế phải bị từ chối.
6. Tạo order/payment sandbox và xử lý IPN hợp lệ.
7. Kiểm tra ticket, invoice PDF và outbox event.
8. Kiểm tra queue/consumer; invoice delivery chuyển `PENDING → SENT` hoặc `FAILED`.
9. Check-in cùng vé hai lần; lần sau phải là `DUPLICATE`.

## 6. Lỗi thường gặp

### Application không kết nối PostgreSQL

- xác nhận `docker compose ps`;
- đối chiếu tên database/user/password giữa `.env` và biến của process Spring;
- kiểm tra port 5432 chưa bị PostgreSQL khác chiếm.

### Flyway validate lỗi

Không sửa schema thủ công để “cho chạy”. So sánh `flyway_schema_history`, migration trong `src/main/resources/db/migration` và database đang kết nối.

### RabbitMQ có message nhưng không gửi mail

Kiểm tra SMTP credentials, consumer log, queue `invoice.created.queue` và `smartevent.dead.letter.queue`. Xem [reliability runbook](reliability-runbook.md).

### Upload MinIO thất bại

Kiểm tra bucket đã tồn tại, endpoint/access key/secret key và giới hạn file: tối đa 10 MB; chỉ JPG/JPEG/PNG/WEBP/PDF; SVG bị chặn.

### Redis không kết nối khi đóng gói app trong container

Main profile hiện đặt host Redis là `localhost`. Nếu application chạy trong container, cần sửa thành tên service/config qua environment; đây là mục backlog trong [known limitations](../03-quality/known-limitations.md).
