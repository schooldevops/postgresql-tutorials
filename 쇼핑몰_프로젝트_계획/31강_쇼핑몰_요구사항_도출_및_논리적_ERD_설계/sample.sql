-- 31강: 쇼핑몰 요구사항 도출 및 논리적 ERD 설계 예제 스크립트
-- 기초적인 구조를 잡아보기 위한 논리 모델 DDL 스크립트입니다.

-- 1. 회원 테이블 DDL 스케치
CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'CUSTOMER',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. 배송지 테이블 (1:N)
CREATE TABLE addresses (
    address_id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(user_id),
    address_line TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false
);

-- 3. 카테고리 확장을 위한 ltree 적용
CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    path ltree NOT NULL
);

-- 4. 상품 테이블
CREATE TABLE products (
    product_id UUID PRIMARY KEY,
    category_id INT REFERENCES categories(category_id),
    title VARCHAR(200) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    attributes JSONB
);

-- 5. 상품 옵션 (재고 처리용)
CREATE TABLE product_options (
    option_id UUID PRIMARY KEY,
    product_id UUID REFERENCES products(product_id),
    option_name VARCHAR(100),
    additional_price NUMERIC(10, 2) DEFAULT 0
);

-- 6. 재고(Inventory) 테이블
CREATE TABLE inventory (
    option_id UUID PRIMARY KEY REFERENCES product_options(option_id),
    stock_quantity INT NOT NULL DEFAULT 0
);

-- 7. 주문 테이블 파티셔닝 뼈대
CREATE TABLE orders (
    order_id UUID NOT NULL,
    user_id UUID REFERENCES users(user_id),
    total_amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING',
    order_date TIMESTAMP NOT NULL,
    PRIMARY KEY (order_id, order_date)
) PARTITION BY RANGE (order_date);

-- 8. 주문 파티션 테이블 생성 (1월)
CREATE TABLE orders_2026_01 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

-- 9. 주문 상세 (N:M 해소)
CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY,
    order_id UUID NOT NULL,
    order_date TIMESTAMP NOT NULL,
    product_id UUID REFERENCES products(product_id),
    option_id UUID REFERENCES product_options(option_id),
    quantity INT NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL,
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date)
);

-- 10. 결제(payments) 시 쿠폰 연동 스케치
CREATE TABLE payments (
    payment_id UUID PRIMARY KEY,
    order_id UUID NOT NULL,
    order_date TIMESTAMP NOT NULL,
    amount_paid NUMERIC(12, 2) NOT NULL,
    payment_method VARCHAR(50),
    paid_at TIMESTAMP,
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date)
);
