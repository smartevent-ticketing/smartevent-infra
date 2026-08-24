# Legacy schema snapshot

`init_schema.sql` là snapshot lịch sử từ monorepo và không được mount bởi Docker Compose.

Nguồn chuẩn hiện tại của database schema là chuỗi Flyway migration tại `smartevent-backend/src/main/resources/db/migration`. Không chỉnh sửa hoặc chạy song song file snapshot này trong luồng phát triển thông thường.
