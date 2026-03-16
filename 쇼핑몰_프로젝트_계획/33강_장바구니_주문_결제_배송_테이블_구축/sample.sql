-- 33강: 장바구니, 주문, 결제, 배송 테이블 구축 실전 쿼리
-- 이 스크립트에는 파티셔닝과 TTL, 외래키 매핑에 대한 10개의 예제가 담겨있습니다.

-- 1. 장바구니 마스터 테이블 (세션화)
CREATE TABLE carts (
    cart_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. 장바구니 아이템 담기 테이블 (복합키 제약)
CREATE TABLE cart_items (
    cart_id UUID REFERENCES carts(cart_id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(product_id),
    option_id UUID REFERENCES product_options(option_id),
    quantity INT DEFAULT 1,
    PRIMARY KEY(cart_id, product_id, option_id)
);

-- 3. 주문 마스터 (파티셔닝 선언)
CREATE TABLE orders (
    order_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id) ON DELETE RESTRICT,
    total_amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING',
    order_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, order_date)
) PARTITION BY RANGE (order_date);

-- 4. 2026년 상반기용 파티션 연속 생성 1월~2월
CREATE TABLE orders_2026_01 PARTITION OF orders FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE orders_2026_02 PARTITION OF orders FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE orders_2026_03 PARTITION OF orders FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- 5. 주문 상세 정보 (1:N)
CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL,
    order_date TIMESTAMP NOT NULL,
    product_id UUID REFERENCES products(product_id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL,
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date)
);

-- 6. 결제 이력 (Payments) 관리 
CREATE TABLE payments (
    payment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL,
    order_date TIMESTAMP NOT NULL,
    coupon_id UUID NULL,
    amount_paid NUMERIC(12, 2) NOT NULL,
    payment_method VARCHAR(50),
    paid_at TIMESTAMP,
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date)
);

-- 7. 배송(Delivery) 현황 테이블
CREATE TABLE deliveries (
    delivery_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL,
    order_date TIMESTAMP NOT NULL,
    address_id INT REFERENCES addresses(address_id),
    tracking_number VARCHAR(100),
    status VARCHAR(50) DEFAULT 'PREPARING',
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date)
);

-- 8. 오래된 장바구니를 검색하는 관리자용 쿼리 (TTL 배치용)
SELECT cart_id, user_id FROM carts WHERE last_updated < NOW() - INTERVAL '30 days';

-- 9. 주문 파티션 테이블 성능 테스트 (Pruning) 
EXPLAIN SELECT * FROM orders WHERE order_date >= '2026-02-01' AND order_date < '2026-03-01';
-- 예상 결과: orders_2026_02 테이블만 스캔

-- 10. 주문 테이블에 B-Tree 인덱스 지정 (각 파티션에 자동 적용)
CREATE INDEX idx_orders_status ON orders(status);
