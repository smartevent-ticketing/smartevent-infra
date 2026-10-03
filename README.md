# Smart Event Ticketing Platform — Infrastructure

Repository này quản lý hạ tầng dùng chung cho môi trường phát triển local của Smart Event Ticketing Platform. Mã nguồn ứng dụng không nằm trong repository này.

## Hệ thống ba repository

| Repository | Trách nhiệm |
|---|---|
| [smartevent-backend](https://github.com/smartevent-ticketing/smartevent-backend) | Spring Boot API, nghiệp vụ, Flyway migration, test backend và tài liệu module |
| [smartevent-web](https://github.com/smartevent-ticketing/smartevent-web) | Next.js UI, client API, UX và test frontend |
| [smartevent-infra](https://github.com/smartevent-ticketing/smartevent-infra) | Docker Compose, PostgreSQL, Redis, RabbitMQ, MinIO và runbook local |

Nguyên tắc quan trọng: Flyway migration trong backend là nguồn chuẩn duy nhất của database schema. Infra chỉ cấp PostgreSQL rỗng và không tự chạy `init_schema.sql`.

## Khởi động nhanh

Yêu cầu: Docker Desktop hoặc Docker Engine có Docker Compose.

```bash
cp .env.example .env
docker compose up -d
docker compose ps
```

Trên Windows PowerShell:

```powershell
Copy-Item .env.example .env
docker compose up -d
docker compose ps
```

Đổi các giá trị `change_me_local` trong `.env` trước khi chạy. File `.env` chỉ dùng local và đã bị Git bỏ qua.

## Dịch vụ local

| Dịch vụ | Địa chỉ mặc định | Dữ liệu bền vững |
|---|---|---|
| PostgreSQL | `localhost:5432` | `smartevent-postgres-data` |
| Redis | `localhost:6379` | `smartevent-redis-data` |
| RabbitMQ AMQP | `localhost:5672` | `smartevent-rabbitmq-data` |
| RabbitMQ UI | `http://localhost:15672` | dùng tài khoản trong `.env` |
| MinIO API | `http://localhost:9000` | `smartevent-minio-data` |
| MinIO Console | `http://localhost:9001` | dùng tài khoản trong `.env` |

Các port mặc định chỉ bind vào `127.0.0.1`, tránh vô tình mở database và trang quản trị ra mạng LAN. Có thể đổi port trong `.env` khi máy đã có dịch vụ khác sử dụng.

## Kết nối backend

Backend chạy trực tiếp trên máy dùng các host `localhost`. Các giá trị database, RabbitMQ và MinIO trong `smartevent-backend/.env` phải khớp với file `.env` của infra.

Nếu sau này backend chạy bằng container, attach container vào network `smartevent-network` và dùng hostname `postgres`, `redis`, `rabbitmq`, `minio` thay cho `localhost`.

## Lệnh vận hành

```bash
# Xem trạng thái và health check
docker compose ps

# Xem log một dịch vụ
docker compose logs -f postgres

# Dừng nhưng giữ dữ liệu
docker compose down

# Cập nhật image rồi khởi động lại
docker compose pull
docker compose up -d
```

`docker compose down -v` xóa toàn bộ volume local. Chỉ dùng khi chủ động muốn reset dữ liệu và đã sao lưu phần cần giữ.

## Tài liệu

- [Học cấu hình infra trên Windows: từng bước và so sánh với VPS](docs/infra/learning-local.md)
- [Chuẩn bị bản demo trên một VPS](deploy/README.md)

- [Ranh giới và cách phối hợp ba repository](docs/infra/repository-boundaries.md)
- [Thiết lập môi trường local](docs/infra/local-development.md)
- [Runbook hạ tầng local](docs/infra/operations-runbook.md)

Tài liệu nghiệp vụ, kiến trúc backend và báo cáo Phase 1 được duy trì tại `smartevent-backend/docs`.

## Phạm vi

Cấu hình này phục vụ development/demo của đồ án, chưa phải cấu hình production. Production cần thêm secret manager, TLS, backup tự động, monitoring/alerting, giới hạn tài nguyên, high availability và quy trình phục hồi đã diễn tập.
