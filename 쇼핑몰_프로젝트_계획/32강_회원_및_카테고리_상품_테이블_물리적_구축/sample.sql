-- 32강: 회원 및 카테고리/상품 테이블 물리적 구축 샘플 쿼리
-- 이 스크립트는 실제 데이터베이스 인스턴스에 적용할 수 있는 초기 뼈대 생성 쿼리입니다.

-- 1. 확장을 설치합니다.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS ltree;

-- 2. 회원 테이블 생성 및 더미데이터 삽입
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'CUSTOMER',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (email, password_hash) VALUES ('test@shop.com', 'hashed_pw_123');

-- 3. 배송지 테이블 (부분 인덱스 활용)
CREATE TABLE addresses (
    address_id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    address_line TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false
);

CREATE UNIQUE INDEX unq_user_default_addr 
ON addresses(user_id) 
WHERE is_default = true;

-- 4. 카테고리 테이블 (Ltree 구조)
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    path ltree NOT NULL
);

CREATE INDEX idx_categories_path ON categories USING GIST (path);

-- 더미 카테고리 데이터
INSERT INTO categories (name, path) VALUES 
('의류', '1'), 
('남성의류', '1.1'), 
('자켓', '1.1.1');

-- 5. 상품 테이블 (JSONB 및 NUMERIC)
CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id INT REFERENCES categories(category_id),
    title VARCHAR(200) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    attributes JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT true
);

-- 6. 상품 속성에 GIN 인덱스 사용
CREATE INDEX idx_products_attributes ON products USING GIN (attributes);

-- 7. 옵션 및 재고 (동시성 제어를 위한 기초)
CREATE TABLE product_options (
    option_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES products(product_id),
    sku VARCHAR(100) UNIQUE,
    option_name VARCHAR(100) NOT NULL, -- 예: 'Red - L 짜리'
    additional_price NUMERIC(10, 2) DEFAULT 0
);

-- 8. 재고 분리 테이블
CREATE TABLE inventory (
    option_id UUID PRIMARY KEY REFERENCES product_options(option_id),
    stock_quantity INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. 부분 인덱스 테스트 쿼리
SELECT * FROM addresses WHERE user_id = (SELECT user_id FROM users LIMIT 1) AND is_default = true;

-- 10. Ltree 하위 카테고리 검색 테스트 쿼리
SELECT name FROM categories WHERE path <@ '1.1'; -- 남성의류 하위 카테고리 모두 검색
