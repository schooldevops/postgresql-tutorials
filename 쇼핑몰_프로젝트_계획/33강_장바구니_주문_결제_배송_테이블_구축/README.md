# 33강: 장바구니, 주문, 결제, 배송 테이블 구축

## 개요 
이번 33강에서는 쇼핑몰 트랜잭션의 핵심인 고객 장바구니, 주문 데이터베이스, 그리고 결제 내역 테이블을 구축합니다. 주문(Orders) 테이블은 시간에 따라 누적되는 데이터량이 기하급수적이므로 처음부터 월별 `RANGE 파티셔닝`을 고려하여 설계합니다. 장바구니는 주기적인 TTL (Time To Live) 정리를 위한 구조를 설계합니다.

## 사용형식 / 메뉴얼 
- 주문 이력은 `PARTITION BY RANGE (order_date)` 를 선언하여 확장성을 열어둡니다.
- 장바구니(cart) 데이터는 캐시나 세션처럼 휘발성 데이터를 담으므로 `updated_at` 필드를 반드시 넣고, 유효기간(TTL)이 지나면 배치 프로세스 등을 통해 삭제하도록 구성합니다.
- 외래키(Foreign Key) 지정 시 자식 테이블의 무결성을 유지하되 파티션 테이블 간의 참조 관계를 명확히 해야합니다.

## 샘플예제 5선 

[샘플 예제 첫번째] 장바구니(Cart) 및 임시 저장 테이블 생성
```sql
CREATE TABLE carts (
    cart_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE cart_items (
    cart_id UUID REFERENCES carts(cart_id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(product_id),
    option_id UUID REFERENCES product_options(option_id),
    quantity INT DEFAULT 1,
    PRIMARY KEY(cart_id, product_id, option_id)
);
```
- 샘플 예제 설명: 사용자가 물건을 담을 때 1:N 관계로 cart_items 안에 옵션과 상품이 기록되는 장바구니 엔티티입니다.

[샘플 예제 두번째] 주문 (Orders) 파티셔닝 마스터 테이블
```sql
CREATE TABLE orders (
    order_id UUID NOT NULL,
    user_id UUID REFERENCES users(user_id) ON DELETE RESTRICT,
    total_amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING',
    order_date TIMESTAMP NOT NULL,
    PRIMARY KEY (order_id, order_date)
) PARTITION BY RANGE (order_date);
```
- 샘플 예제 설명: PostgreSQL에서 파티션 기준 칼럼(order_date)은 반드시 마스터 테이블의 PK에 포함되어야 합니다.

[샘플 예제 세번째] 월별 파티션 및 인덱스 추가
```sql
-- 2026년 2월 파티션 생성
CREATE TABLE orders_2026_02 PARTITION OF orders
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE INDEX idx_orders_user_id ON orders(user_id);
```
- 샘플 예제 설명: 위와 같은 방법으로 트래픽이 몰리기 전에 DBA가 스크립트나 PG Agent를 통해 월별로 파티션을 생성해줍니다.

[샘플 예제 네번째] 주문 상세와 복합 참조
```sql
CREATE TABLE order_items (
    order_item_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL,
    order_date TIMESTAMP NOT NULL,
    product_id UUID REFERENCES products(product_id),
    quantity INT NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL,
    -- 파티션 테이블을 가리키는 포괄적 FK 
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date)
);
```
- 샘플 예제 설명: `orders` 마스터를 바라보는 외래키(FK)를 생성하여 데이터 정합성을 지켜냅니다.

[샘플 예제 다섯번째] 결제 롤백 방지 테이블 & 배송
```sql
CREATE TABLE deliveries (
    delivery_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL,
    order_date TIMESTAMP NOT NULL,
    tracking_number VARCHAR(100),
    status VARCHAR(50) DEFAULT 'PREPARING',
    FOREIGN KEY (order_id, order_date) REFERENCES orders(order_id, order_date)
);
```
- 샘플 예제 설명: 결제가 끝난 뒤 택배사의 송장(Tracking) 정보와 배송 현황을 갱신하는 별개의 테이블 구조입니다.

## 주의사항 
- 파티셔닝을 설계할 때는 날짜 및 식별자가 함께 PK로 설정되므로 조인 연산 시 `order_date`를 서브 쿼리 필터에 포함시키지 않으면 파티션 프루닝(Pruning: 필요없는 파티션 테이블 조회를 스킵하는 기능)이 발생하지 않아 전체 스캔(Seq Scan)이 일어납니다.

## 성능 최적화 방안
[파티션 프루닝 성능 비교 및 쿼리]
```sql
-- 파티션 프루닝이 동작하여 2월 테이블만 스캔하는 좋은 예
SELECT * FROM orders WHERE order_date >= '2026-02-15' AND order_date < '2026-03-01' AND status = 'COMPLETED';
```
- 성능 개선이 되는 이유: `order_date` 필터 조건이 주어졌기 때문에 DBMS 옵티마이저는 모든 월 단위 테이블을 뒤지지 않고 `orders_2026_02` 파티션만 접근하므로 I/O 성능이 극도로 향상됩니다.
