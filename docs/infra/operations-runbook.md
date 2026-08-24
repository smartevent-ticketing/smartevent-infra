# Local infrastructure runbook

## Kiểm tra trạng thái

```bash
docker compose ps
docker compose logs --tail=200 postgres
docker compose logs --tail=200 rabbitmq
```

Nếu service unhealthy, kiểm tra port bị chiếm, giá trị `.env`, dung lượng ổ đĩa và log của đúng service trước khi reset volume.

## Dừng và khởi động lại

```bash
docker compose down
docker compose up -d
```

Lệnh trên giữ nguyên named volume. Không cần xóa database mỗi lần đổi mã nguồn backend; Flyway sẽ chạy migration còn thiếu khi backend khởi động.

## Sao lưu PostgreSQL local

```bash
docker compose exec -T postgres pg_dump -U smartevent -d smart_event_db -Fc > smart_event_db.dump
```

Tên user/database phải khớp `.env`. File dump có thể chứa dữ liệu nhạy cảm và không được commit.

## Reset toàn bộ dữ liệu local

```bash
docker compose down -v
docker compose up -d
```

Đây là thao tác phá hủy PostgreSQL, Redis, RabbitMQ và MinIO local. Chỉ chạy sau khi đã xác nhận không cần dữ liệu hoặc đã sao lưu.

## Nguyên tắc production

Compose này không phải deployment production. Trước production cần ít nhất: secret manager, TLS, backup định kỳ có kiểm thử restore, metrics/alerting, giới hạn CPU/RAM, image digest hoặc version cố định, network policy và kế hoạch high availability.

