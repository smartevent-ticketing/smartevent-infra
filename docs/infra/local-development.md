# Local development

## 1. Clone ba repository cạnh nhau

```text
SmartEventRepos/
├── smartevent-backend/
├── smartevent-web/
└── smartevent-infra/
```

```bash
git clone https://github.com/smartevent-ticketing/smartevent-backend.git
git clone https://github.com/smartevent-ticketing/smartevent-web.git
git clone https://github.com/smartevent-ticketing/smartevent-infra.git
```

## 2. Khởi động hạ tầng

Trong `smartevent-infra`:

```bash
cp .env.example .env
docker compose up -d
docker compose ps
```

Chờ bốn service chuyển sang trạng thái healthy trước khi chạy backend.

## 3. Cấu hình backend

Trong `smartevent-backend`, tạo `.env` từ `.env.example`. Các giá trị sau phải khớp với infra:

```dotenv
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/smart_event_db
SPRING_DATASOURCE_USERNAME=smartevent
SPRING_DATASOURCE_PASSWORD=change_me_local
SPRING_RABBITMQ_HOST=localhost
SPRING_RABBITMQ_PORT=5672
SPRING_RABBITMQ_USERNAME=smartevent
SPRING_RABBITMQ_PASSWORD=change_me_local
APP_MINIO_ENDPOINT=http://localhost:9000
APP_MINIO_ACCESS_KEY=smartevent
APP_MINIO_SECRET_KEY=change_me_local_minio
APP_MINIO_BUCKET=smart-event-bucket
```

Gradle không tự nạp `.env`. Hãy đưa các biến vào Run/Debug Configuration của IDE hoặc environment của shell đang chạy ứng dụng.

```bash
./gradlew test
./gradlew bootRun
```

## 4. Chạy frontend

Trong `smartevent-web`:

```bash
npm install
cp .env.example .env.local
npm run dev
```

Mặc định frontend chạy tại `http://localhost:3000`, backend tại `http://localhost:8080`.

## 5. Kiểm tra nhanh

- `docker compose ps` hiển thị PostgreSQL, Redis, RabbitMQ và MinIO healthy.
- Swagger UI mở tại `http://localhost:8080/swagger-ui.html`.
- RabbitMQ UI mở tại `http://localhost:15672`.
- MinIO Console mở tại `http://localhost:9001`.
- Frontend mở tại `http://localhost:3000`.

