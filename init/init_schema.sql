-- ============================================================================
-- SMART EVENT TICKETING PLATFORM - INITIAL CONSOLIDATED DATABASE SCHEMA (PHASE 1)
-- ============================================================================
-- Hệ quản trị CSDL: PostgreSQL 16
-- Phiên bản Schema: Phase 1 (Core Ticketing - 32 Bảng)
-- Mục đích: File SQL tổng hợp dùng để đọc, tham khảo hoặc khởi tạo CSDL thủ công
-- ============================================================================

-- ============================================================================
-- 0. EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ============================================================================
-- 1. PHÂN HỆ NGƯỜI DÙNG & XÁC THỰC (IDENTITY & RBAC)
-- ============================================================================

-- 1.1. Bảng lưu trữ tệp (Storage Files Metadata - Đặt trước để users tham chiếu avatar)
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID, -- Sẽ được thêm FOREIGN KEY sau khi bảng users được tạo
    bucket_name VARCHAR(100) NOT NULL,
    object_name VARCHAR(500) NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    content_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,
    checksum VARCHAR(64),
    visibility VARCHAR(30) NOT NULL DEFAULT 'PRIVATE', -- PUBLIC, PRIVATE
    scan_status VARCHAR(30) NOT NULL DEFAULT 'PENDING', -- PENDING, CLEAN, INFECTED
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE files IS 'Metadata tệp tin lưu trữ tại MinIO (banner, avatar, vé QR, hóa đơn)';
COMMENT ON COLUMN files.bucket_name IS 'Tên bucket trong MinIO (event-assets, ticket-documents...)';
COMMENT ON COLUMN files.object_name IS 'Đường dẫn chính xác của tệp trong MinIO storage';

-- 1.2. Bảng người dùng (Users)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(30),
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, DISABLED, DELETED
    avatar_file_id UUID REFERENCES files(id) ON DELETE SET NULL,
    deleted_at TIMESTAMPTZ, -- Xóa mềm (soft delete)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS 'Tài khoản người dùng (Khách hàng, Ban tổ chức, Quản trị viên)';
COMMENT ON COLUMN users.avatar_file_id IS 'Khóa ngoại trỏ đến ảnh đại diện trong bảng files';
COMMENT ON COLUMN users.deleted_at IS 'Thời điểm xóa mềm (nếu user yêu cầu ẩn tài khoản)';

-- Thêm khóa ngoại cho owner_id của bảng files trỏ về users
ALTER TABLE files ADD CONSTRAINT fk_files_owner FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX idx_files_owner_id ON files(owner_id);
CREATE INDEX idx_files_bucket_object ON files(bucket_name, object_name);

-- 1.3. Bảng vai trò hệ thống (Roles)
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE, -- CUSTOMER, ORGANIZER, ADMIN
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE roles IS 'Danh mục vai trò hệ thống (CUSTOMER, ORGANIZER, ADMIN)';

-- 1.4. Bảng phân quyền người dùng (User Roles - N:N)
CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, role_id)
);

COMMENT ON TABLE user_roles IS 'Bảng trung gian phân quyền N:N giữa người dùng và vai trò';

-- 1.5. Bảng hồ sơ Ban Tổ Chức (Organizer Profiles)
CREATE TABLE organizer_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
    company_name VARCHAR(255) NOT NULL,
    tax_code VARCHAR(50),
    business_address TEXT,
    bank_account_status VARCHAR(50) NOT NULL DEFAULT 'PENDING', -- PENDING, VERIFIED, REJECTED
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE organizer_profiles IS 'Hồ sơ pháp nhân và tài khoản ngân hàng của Ban Tổ Chức';
CREATE INDEX idx_organizer_profiles_user_id ON organizer_profiles(user_id);

-- 1.6. Bảng phiên làm việc dài hạn (Refresh Tokens)
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE refresh_tokens IS 'Quản lý Refresh Token JWT dài hạn, hỗ trợ thu hồi khi Logout';
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at) WHERE revoked_at IS NULL;

-- Dữ liệu mẫu khởi tạo vai trò mặc định
INSERT INTO roles(id, name) VALUES
    (gen_random_uuid(), 'CUSTOMER'),
    (gen_random_uuid(), 'ORGANIZER'),
    (gen_random_uuid(), 'ADMIN')
ON CONFLICT (name) DO NOTHING;


-- ============================================================================
-- 2. PHÂN HỆ ĐỊA ĐIỂM, DANH MỤC & SỰ KIỆN (EVENT & VENUE)
-- ============================================================================

-- 2.1. Bảng địa điểm tổ chức (Venues - Do Admin quản lý)
CREATE TABLE venues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    address VARCHAR(500) NOT NULL,
    city VARCHAR(100) NOT NULL,
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    capacity INT,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, INACTIVE
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_venue_capacity CHECK (capacity IS NULL OR capacity > 0)
);

COMMENT ON TABLE venues IS 'Địa điểm tổ chức sự kiện do Quản trị viên (Admin) tạo';
CREATE INDEX idx_venues_city ON venues(city);
CREATE INDEX idx_venues_status ON venues(status);

-- 2.2. Bảng danh mục sự kiện (Categories)
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, INACTIVE
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE categories IS 'Danh mục thể loại sự kiện (Âm nhạc, Thể thao, Hội thảo...)';
CREATE INDEX idx_categories_slug ON categories(slug);

-- 2.3. Bảng sự kiện (Events)
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organizer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    venue_id UUID REFERENCES venues(id) ON DELETE RESTRICT,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT', -- DRAFT, PENDING_APPROVAL, PUBLISHED, CANCELLED, COMPLETED
    resale_enabled BOOLEAN NOT NULL DEFAULT false,
    max_resale_price_multiplier NUMERIC(5,2), -- Trần giá bán lại (VD: 1.20 = 120%)
    resale_deadline_hours_before INT, -- Hạn chót được bán lại vé (số giờ trước giờ bắt đầu)
    virtual_queue_enabled BOOLEAN NOT NULL DEFAULT false, -- Bật phòng chờ ảo chống sập khi mở bán vé hot
    queue_batch_size INT DEFAULT 50,
    city VARCHAR(100), -- Denormalized từ venue để tìm kiếm siêu tốc
    search_vector TSVECTOR, -- Dữ liệu chỉ mục tìm kiếm Full-Text Search
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_events_time CHECK (end_time > start_time),
    CONSTRAINT chk_events_multiplier CHECK (max_resale_price_multiplier IS NULL OR max_resale_price_multiplier > 0),
    CONSTRAINT chk_events_resale_deadline CHECK (resale_deadline_hours_before IS NULL OR resale_deadline_hours_before >= 0),
    -- Chống trùng lịch sự kiện tại cùng 1 địa điểm bằng PostgreSQL Exclusion Constraint
    EXCLUDE USING gist (
        venue_id WITH =,
        tstzrange(start_time, end_time) WITH &&
    ) WHERE (status IN ('PUBLISHED', 'PENDING_APPROVAL') AND venue_id IS NOT NULL)
);

COMMENT ON TABLE events IS 'Sự kiện do Ban Tổ Chức đăng ký và mở bán';
CREATE INDEX idx_events_organizer_id ON events(organizer_id);
CREATE INDEX idx_events_venue_id ON events(venue_id);
CREATE INDEX idx_events_status ON events(status);
CREATE INDEX idx_events_start_time ON events(start_time);
CREATE INDEX idx_events_city ON events(city);
CREATE INDEX idx_events_search ON events USING GIN(search_vector);

-- Trigger tự động cập nhật search_vector khi thêm/sửa sự kiện
CREATE OR REPLACE FUNCTION events_search_vector_update() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('simple', COALESCE(NEW.name, '')), 'A') ||
        setweight(to_tsvector('simple', COALESCE(NEW.city, '')), 'B') ||
        setweight(to_tsvector('simple', COALESCE(NEW.description, '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_events_search_vector
    BEFORE INSERT OR UPDATE OF name, city, description
    ON events
    FOR EACH ROW
    EXECUTE FUNCTION events_search_vector_update();

-- 2.4. Bảng liên kết Sự kiện - Danh mục (Event Categories - N:N)
CREATE TABLE event_categories (
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    PRIMARY KEY (event_id, category_id)
);

CREATE INDEX idx_event_categories_category_id ON event_categories(category_id);

-- 2.5. Bảng khu vực sự kiện (Event Areas)
CREATE TABLE event_areas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL, -- Khán đài A, Khu VIP Fanzone...
    area_type VARCHAR(30) NOT NULL DEFAULT 'STANDING', -- STANDING (Vé đứng) hoặc SEATED (Ghế ngồi)
    capacity INT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_area_capacity CHECK (capacity > 0)
);

COMMENT ON TABLE event_areas IS 'Phân vùng khán đài trong sự kiện (STANDING hoặc SEATED)';
CREATE INDEX idx_event_areas_event_id ON event_areas(event_id);

-- 2.6. Bảng ghế ngồi chi tiết (Event Seats - Chỉ dùng cho SEATED)
CREATE TABLE event_seats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_area_id UUID NOT NULL REFERENCES event_areas(id) ON DELETE CASCADE,
    row_name VARCHAR(50) NOT NULL, -- Hàng A, Hàng B
    seat_number VARCHAR(50) NOT NULL, -- Ghế 01, Ghế 02
    label VARCHAR(100), -- Nhãn hiển thị A-01
    status VARCHAR(30) NOT NULL DEFAULT 'AVAILABLE', -- AVAILABLE, HELD, SOLD, BLOCKED
    hold_expires_at TIMESTAMPTZ, -- Hạn giữ ghế 10 phút
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (event_area_id, row_name, seat_number)
);

COMMENT ON TABLE event_seats IS 'Ghế ngồi cụ thể trong khu vực có loại SEATED';
CREATE INDEX idx_event_seats_area_status ON event_seats(event_area_id, status);
CREATE INDEX idx_event_seats_hold_expires ON event_seats(hold_expires_at) WHERE status = 'HELD';

-- 2.7. Bảng tệp đính kèm sự kiện (Event Files)
CREATE TABLE event_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE RESTRICT,
    file_type VARCHAR(30) NOT NULL, -- BANNER, GALLERY, SEAT_MAP, DOCUMENT
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE event_files IS 'Danh sách hình ảnh banner, poster, sơ đồ ghế đính kèm sự kiện';
CREATE INDEX idx_event_files_event_id ON event_files(event_id);

-- 2.8. Bảng phương thức thanh toán của sự kiện (Event Payment Methods)
CREATE TABLE event_payment_methods (
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    method VARCHAR(30) NOT NULL, -- VNPAY, MOMO, BANK_TRANSFER
    enabled BOOLEAN NOT NULL DEFAULT true,
    config_json JSONB,
    PRIMARY KEY (event_id, method)
);

COMMENT ON TABLE event_payment_methods IS 'Các cổng thanh toán được cấu hình cho từng sự kiện';


-- ============================================================================
-- 3. PHÂN HỆ ĐỢT MỞ BÁN & TỒN KHO (TICKETING & INVENTORY)
-- ============================================================================

-- 3.1. Bảng loại vé (Ticket Types)
CREATE TABLE ticket_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    event_area_id UUID NOT NULL REFERENCES event_areas(id) ON DELETE RESTRICT,
    name VARCHAR(100) NOT NULL, -- VIP, Standard, Early Access
    description TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, INACTIVE
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ticket_types IS 'Danh mục loại vé áp dụng theo từng khu vực';
CREATE INDEX idx_ticket_types_event_id ON ticket_types(event_id);
CREATE INDEX idx_ticket_types_area_id ON ticket_types(event_area_id);

-- 3.2. Bảng đợt mở bán vé (Ticket Sale Phases - Nơi duy nhất chứa Giá và Số Lượng)
CREATE TABLE ticket_sale_phases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_type_id UUID NOT NULL REFERENCES ticket_types(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL, -- Đợt Early Bird, Đợt Mở Bán Chính Thức
    price DECIMAL(15,2) NOT NULL, -- Giá vé (VNĐ)
    quantity INT NOT NULL, -- Số lượng vé mở bán trong đợt
    sale_start_at TIMESTAMPTZ NOT NULL,
    sale_end_at TIMESTAMPTZ NOT NULL,
    sold_out_at TIMESTAMPTZ,
    max_per_order INT NOT NULL DEFAULT 4, -- Số vé tối đa trên 1 đơn hàng
    max_per_user INT, -- Số vé tối đa 1 người được mua trong đợt
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT', -- DRAFT, SCHEDULED, ACTIVE, PAUSED, CLOSED, SOLD_OUT
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_phase_price CHECK (price >= 0),
    CONSTRAINT chk_phase_quantity CHECK (quantity > 0),
    CONSTRAINT chk_phase_max_per_order CHECK (max_per_order > 0),
    CONSTRAINT chk_phase_max_per_user CHECK (max_per_user IS NULL OR max_per_user > 0),
    CONSTRAINT chk_phase_sale_time CHECK (sale_end_at > sale_start_at)
);

COMMENT ON TABLE ticket_sale_phases IS 'Cấu hình giá vé, lịch mở bán và số lượng vé phát hành theo từng đợt';
CREATE INDEX idx_ticket_sale_phases_ticket_type ON ticket_sale_phases(ticket_type_id);
CREATE INDEX idx_ticket_sale_phases_status ON ticket_sale_phases(status);
CREATE INDEX idx_ticket_sale_phases_timing ON ticket_sale_phases(sale_start_at, sale_end_at);

-- 3.3. Bảng quy tắc nâng cao đợt bán (Ticket Phase Rules)
CREATE TABLE ticket_phase_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_phase_id UUID NOT NULL REFERENCES ticket_sale_phases(id) ON DELETE CASCADE,
    rule_type VARCHAR(50) NOT NULL, -- ACCESS_CODE, MEMBER_ONLY, EARLY_ACCESS
    rule_value TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ticket_phase_rules IS 'Quy tắc mở rộng như mã code mua sớm, quyền ưu tiên thành viên';
CREATE INDEX idx_ticket_phase_rules_phase_id ON ticket_phase_rules(sale_phase_id);

-- 3.4. Bảng quản lý tồn kho vé (Inventory Counters - Nguồn sự thật chống Oversell)
CREATE TABLE inventory_counters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    event_area_id UUID NOT NULL REFERENCES event_areas(id) ON DELETE RESTRICT,
    ticket_type_id UUID NOT NULL REFERENCES ticket_types(id) ON DELETE CASCADE,
    sale_phase_id UUID NOT NULL UNIQUE REFERENCES ticket_sale_phases(id) ON DELETE CASCADE,
    total_quantity INT NOT NULL,
    held_quantity INT NOT NULL DEFAULT 0, -- Số vé đang bị giữ chỗ tạm thời (10p)
    sold_quantity INT NOT NULL DEFAULT 0, -- Số vé đã thanh toán thành công
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_inv_held CHECK (held_quantity >= 0),
    CONSTRAINT chk_inv_sold CHECK (sold_quantity >= 0),
    CONSTRAINT chk_inv_total CHECK (held_quantity + sold_quantity <= total_quantity)
);

COMMENT ON TABLE inventory_counters IS 'Nguồn sự thật quản lý số lượng vé STANDING; Cập nhật bằng Atomic Conditional UPDATE';
CREATE INDEX idx_inventory_counters_event_id ON inventory_counters(event_id);
CREATE INDEX idx_inventory_counters_phase_id ON inventory_counters(sale_phase_id);

-- 3.5. Bảng đếm vé theo người dùng (User Sale Phase Counters)
CREATE TABLE user_sale_phase_counters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sale_phase_id UUID NOT NULL REFERENCES ticket_sale_phases(id) ON DELETE CASCADE,
    held_quantity INT NOT NULL DEFAULT 0,
    purchased_quantity INT NOT NULL DEFAULT 0,
    refunded_quantity INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, sale_phase_id),
    CONSTRAINT chk_user_counter_held CHECK (held_quantity >= 0),
    CONSTRAINT chk_user_counter_purchased CHECK (purchased_quantity >= 0),
    CONSTRAINT chk_user_counter_refunded CHECK (refunded_quantity >= 0)
);

COMMENT ON TABLE user_sale_phase_counters IS 'Kiểm soát hạn mức mua vé tối đa của từng người dùng trong mỗi đợt';
CREATE INDEX idx_user_phase_counters_user ON user_sale_phase_counters(user_id);
CREATE INDEX idx_user_phase_counters_phase ON user_sale_phase_counters(sale_phase_id);


-- ============================================================================
-- 4. PHÂN HỆ GIỮ CHỖ & ĐƠN HÀNG (RESERVATION & ORDERING)
-- ============================================================================

-- 4.1. Bảng phiên giữ chỗ (Reservations - Giữ vé trong 10 phút)
CREATE TABLE reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE RESTRICT,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING', -- PENDING, CONFIRMED, EXPIRED, CANCELLED
    expires_at TIMESTAMPTZ NOT NULL, -- NOW() + 10 phút
    idempotency_key VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_reservation_expiry CHECK (expires_at > created_at)
);

COMMENT ON TABLE reservations IS 'Lệnh giữ chỗ ghế / vé trong 10 phút để người dùng thanh toán';
CREATE INDEX idx_reservations_user_id ON reservations(user_id);
CREATE INDEX idx_reservations_event_id ON reservations(event_id);
CREATE INDEX idx_reservations_status_expires ON reservations(status, expires_at);
CREATE INDEX idx_reservations_idempotency ON reservations(idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Partial unique index: Mỗi người dùng chỉ được có tối đa 1 phiên giữ chỗ PENDING cho mỗi sự kiện
CREATE UNIQUE INDEX idx_reservations_active_per_user_event 
    ON reservations(user_id, event_id) 
    WHERE status = 'PENDING';

-- 4.2. Bảng chi tiết mục giữ chỗ (Reservation Items)
CREATE TABLE reservation_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id UUID NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    ticket_type_id UUID NOT NULL REFERENCES ticket_types(id) ON DELETE RESTRICT,
    sale_phase_id UUID NOT NULL REFERENCES ticket_sale_phases(id) ON DELETE RESTRICT,
    event_seat_id UUID REFERENCES event_seats(id) ON DELETE RESTRICT, -- NULL nếu là vé STANDING
    quantity INT NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_res_item_quantity CHECK (quantity > 0),
    CONSTRAINT chk_res_item_price CHECK (unit_price >= 0)
);

COMMENT ON TABLE reservation_items IS 'Chi tiết từng ghế hoặc số lượng vé đứng được giữ chỗ';
CREATE INDEX idx_reservation_items_res_id ON reservation_items(reservation_id);
CREATE INDEX idx_reservation_items_seat_id ON reservation_items(event_seat_id) WHERE event_seat_id IS NOT NULL;

-- 4.3. Bảng đơn hàng (Orders)
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reservation_id UUID REFERENCES reservations(id) ON DELETE RESTRICT,
    order_code VARCHAR(50) NOT NULL UNIQUE, -- ORD-20260815-ABCD
    subtotal DECIMAL(15,2) NOT NULL,
    discount_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    fee_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'VND',
    payment_deadline TIMESTAMPTZ,
    customer_note TEXT,
    coupon_id UUID, -- Sẽ liên kết bảng coupons ở Phase 2
    selected_payment_method VARCHAR(30),
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING_PAYMENT', -- PENDING_PAYMENT, PAID, CANCELLED, EXPIRED, PARTIALLY_REFUNDED, REFUNDED
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_orders_amounts CHECK (
        subtotal >= 0 AND 
        total_amount >= 0 AND 
        discount_amount >= 0 AND 
        fee_amount >= 0
    )
);

COMMENT ON TABLE orders IS 'Đơn hàng mua vé của khách hàng';
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_reservation_id ON orders(reservation_id);
CREATE INDEX idx_orders_order_code ON orders(order_code);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_deadline ON orders(payment_deadline) WHERE status = 'PENDING_PAYMENT';

-- 4.4. Bảng chi tiết đơn hàng (Order Items)
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    ticket_type_id UUID NOT NULL REFERENCES ticket_types(id) ON DELETE RESTRICT,
    sale_phase_id UUID NOT NULL REFERENCES ticket_sale_phases(id) ON DELETE RESTRICT,
    event_seat_id UUID REFERENCES event_seats(id) ON DELETE RESTRICT,
    quantity INT NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    total_price DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_order_item_qty CHECK (quantity > 0),
    CONSTRAINT chk_order_item_price CHECK (unit_price >= 0 AND total_price >= 0)
);

COMMENT ON TABLE order_items IS 'Chi tiết các dòng vé trong đơn hàng (Lưu snapshot giá tại thời điểm mua)';
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_ticket_type ON order_items(ticket_type_id);
CREATE INDEX idx_order_items_sale_phase ON order_items(sale_phase_id);
CREATE INDEX idx_order_items_seat_id ON order_items(event_seat_id) WHERE event_seat_id IS NOT NULL;


-- ============================================================================
-- 5. PHÂN HỆ THANH TOÁN (PAYMENT & WEBHOOK)
-- ============================================================================

-- 5.1. Bảng lịch sử giao dịch thanh toán (Payments)
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    payment_method VARCHAR(30) NOT NULL,
    provider VARCHAR(30) NOT NULL DEFAULT 'VNPAY', -- VNPAY Sandbox
    transaction_id VARCHAR(100), -- Mã giao dịch từ VNPAY
    amount DECIMAL(15,2) NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'VND',
    status VARCHAR(30) NOT NULL DEFAULT 'INITIATED', -- INITIATED, PENDING, SUCCESS, FAILED, CANCELLED, REFUNDED
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_payments_amount CHECK (amount > 0)
);

COMMENT ON TABLE payments IS 'Lịch sử từng lượt giao dịch thanh toán qua cổng VNPAY';
CREATE INDEX idx_payments_order_id ON payments(order_id);
CREATE INDEX idx_payments_provider_tx ON payments(provider, transaction_id) WHERE transaction_id IS NOT NULL;
CREATE INDEX idx_payments_status ON payments(status);

-- 5.2. Bảng sự kiện webhook IPN từ Cổng thanh toán (Payment Webhook Events)
CREATE TABLE payment_webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider VARCHAR(30) NOT NULL, -- VNPAY
    provider_event_id VARCHAR(100) NOT NULL,
    transaction_id VARCHAR(100),
    payload_hash VARCHAR(64),
    payload_json JSONB,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    status VARCHAR(30) NOT NULL DEFAULT 'RECEIVED', -- RECEIVED, PROCESSED, IGNORED, FAILED
    UNIQUE (provider, provider_event_id)
);

COMMENT ON TABLE payment_webhook_events IS 'Nhật ký callback webhook (IPN) từ VNPAY - Đảm bảo xử lý Idempotent';
CREATE INDEX idx_webhook_events_provider_event ON payment_webhook_events(provider, provider_event_id);
CREATE INDEX idx_webhook_events_status ON payment_webhook_events(status);


-- ============================================================================
-- 6. PHÂN HỆ VÉ ĐIỆN TỬ & SOÁT VÉ (TICKET & CHECK-IN)
-- ============================================================================

-- 6.1. Bảng vé điện tử (Tickets)
CREATE TABLE tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_item_id UUID NOT NULL REFERENCES order_items(id) ON DELETE RESTRICT,
    current_owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT, -- Chủ sở hữu hiện tại
    original_buyer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT, -- Người mua đầu tiên
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE RESTRICT,
    event_seat_id UUID REFERENCES event_seats(id) ON DELETE RESTRICT,
    event_area_id UUID REFERENCES event_areas(id) ON DELETE RESTRICT,
    ticket_type_id UUID REFERENCES ticket_types(id) ON DELETE RESTRICT,
    sale_phase_id UUID REFERENCES ticket_sale_phases(id) ON DELETE RESTRICT,
    ticket_code VARCHAR(100) NOT NULL UNIQUE, -- TICK-2026-X89J21
    status VARCHAR(30) NOT NULL DEFAULT 'ISSUED', -- ISSUED, USED, CANCELLED, REFUNDED, RESALE_LISTED, TRANSFERRED
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE tickets IS 'Vé điện tử phát hành cho người tham dự sau khi thanh toán thành công';
CREATE INDEX idx_tickets_current_owner ON tickets(current_owner_user_id);
CREATE INDEX idx_tickets_event_id ON tickets(event_id);
CREATE INDEX idx_tickets_order_item_id ON tickets(order_item_id);
CREATE INDEX idx_tickets_ticket_code ON tickets(ticket_code);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_tickets_seat_id ON tickets(event_seat_id) WHERE event_seat_id IS NOT NULL;
CREATE INDEX idx_tickets_area_id ON tickets(event_area_id);

-- 6.2. Bảng mã QR bảo mật của vé (Ticket QR Tokens)
CREATE TABLE ticket_qr_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, REVOKED
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

COMMENT ON TABLE ticket_qr_tokens IS 'Mã hash bảo mật cho QR vé vào cổng; Thu hồi khi chuyển nhượng/bán lại';
CREATE INDEX idx_qr_tokens_ticket_id ON ticket_qr_tokens(ticket_id);
CREATE INDEX idx_qr_tokens_hash ON ticket_qr_tokens(token_hash);
CREATE INDEX idx_qr_tokens_active ON ticket_qr_tokens(ticket_id, status) WHERE status = 'ACTIVE';

-- 6.3. Bảng lịch sử quét vé vào cổng (Ticket Check-ins)
CREATE TABLE ticket_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE RESTRICT,
    event_id UUID NOT NULL REFERENCES events(id) ON DELETE RESTRICT,
    checked_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- Nhân viên soát vé
    gate_name VARCHAR(100), -- Cổng A1, Cổng VIP
    result VARCHAR(30) NOT NULL, -- SUCCESS, INVALID, DUPLICATE
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ticket_checkins IS 'Lịch sử toàn bộ lượt quét vé tại cửa ra vào';
CREATE INDEX idx_ticket_checkins_ticket_id ON ticket_checkins(ticket_id);
CREATE INDEX idx_ticket_checkins_event_id ON ticket_checkins(event_id);
CREATE INDEX idx_ticket_checkins_time ON ticket_checkins(checked_at);

-- 6.4. Bảng lịch sử chuyển nhượng vé (Ticket Transfers)
CREATE TABLE ticket_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE RESTRICT,
    from_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    to_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    source_type VARCHAR(30) NOT NULL, -- RESALE, ADMIN, REFUND_REISSUE
    source_id UUID,
    status VARCHAR(30) NOT NULL DEFAULT 'COMPLETED',
    transferred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE ticket_transfers IS 'Nhật ký đổi chủ sở hữu vé điện tử';
CREATE INDEX idx_ticket_transfers_ticket ON ticket_transfers(ticket_id);
CREATE INDEX idx_ticket_transfers_from_user ON ticket_transfers(from_user_id);
CREATE INDEX idx_ticket_transfers_to_user ON ticket_transfers(to_user_id);


-- ============================================================================
-- 7. PHÂN HỆ HÓA ĐƠN ĐIỆN TỬ (BILLING & INVOICE)
-- ============================================================================

-- 7.1. Bảng hóa đơn điện tử (Invoices - Exactly-once per order)
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE RESTRICT, -- Khóa duy nhất đảm bảo xuất đúng 1 hóa đơn
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    invoice_code VARCHAR(100) NOT NULL UNIQUE, -- INV-20260815-9982
    billing_email VARCHAR(255) NOT NULL,
    subtotal DECIMAL(15,2) NOT NULL,
    discount_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    fee_amount DECIMAL(15,2) NOT NULL DEFAULT 0,
    total_amount DECIMAL(15,2) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ISSUED', -- ISSUED, VOID
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    file_id UUID REFERENCES files(id) ON DELETE SET NULL, -- Tệp PDF hóa đơn trong MinIO
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_invoices_amounts CHECK (
        subtotal >= 0 AND 
        total_amount >= 0 AND 
        discount_amount >= 0 AND 
        fee_amount >= 0
    )
);

COMMENT ON TABLE invoices IS 'Hóa đơn thanh toán phát hành cho khách hàng';
CREATE INDEX idx_invoices_order_id ON invoices(order_id);
CREATE INDEX idx_invoices_user_id ON invoices(user_id);
CREATE INDEX idx_invoices_invoice_code ON invoices(invoice_code);
CREATE INDEX idx_invoices_status ON invoices(status);

-- 7.2. Bảng chi tiết hóa đơn (Invoice Items)
CREATE TABLE invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    order_item_id UUID REFERENCES order_items(id) ON DELETE SET NULL,
    description VARCHAR(255) NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(15,2) NOT NULL,
    total_price DECIMAL(15,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_invoice_item_qty CHECK (quantity > 0),
    CONSTRAINT chk_invoice_item_price CHECK (unit_price >= 0 AND total_price >= 0)
);

COMMENT ON TABLE invoice_items IS 'Chi tiết các dòng dịch vụ ghi nhận trên hóa đơn';
CREATE INDEX idx_invoice_items_invoice_id ON invoice_items(invoice_id);

-- 7.3. Bảng lịch sử gửi email hóa đơn (Invoice Deliveries)
CREATE TABLE invoice_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    channel VARCHAR(30) NOT NULL DEFAULT 'EMAIL',
    recipient_email VARCHAR(255) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING', -- PENDING, SENT, FAILED
    sent_at TIMESTAMPTZ,
    provider_message_id VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE invoice_deliveries IS 'Nhật ký gửi email đính kèm hóa đơn PDF bất đồng bộ';
CREATE INDEX idx_invoice_deliveries_invoice_id ON invoice_deliveries(invoice_id);
CREATE INDEX idx_invoice_deliveries_status ON invoice_deliveries(status);


-- ============================================================================
-- 8. PHÂN HỆ THÔNG ĐIỆP ĐỒNG BỘ (MESSAGING & OUTBOX PATTERN)
-- ============================================================================

-- 8.1. Bảng sự kiện giao dịch Outbox (Outbox Events)
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(50) NOT NULL, -- ORDER, TICKET, EVENT, PAYMENT
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL, -- OrderPaidEvent, TicketIssuedEvent
    payload_json JSONB NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING', -- PENDING, PUBLISHED, FAILED
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    retry_count INT NOT NULL DEFAULT 0,
    last_error TEXT
);

COMMENT ON TABLE outbox_events IS 'Transactional Outbox Pattern - Đảm bảo dữ liệu và RabbitMQ Events đồng bộ 100%';
CREATE INDEX idx_outbox_events_status_created ON outbox_events(status, created_at) WHERE status = 'PENDING';
CREATE INDEX idx_outbox_events_aggregate ON outbox_events(aggregate_type, aggregate_id);
CREATE INDEX idx_outbox_events_type ON outbox_events(event_type);

-- ============================================================================
-- KẾT THÚC SCHEMA GIAI ĐOẠN 1 (32 BẢNG)
-- ============================================================================
