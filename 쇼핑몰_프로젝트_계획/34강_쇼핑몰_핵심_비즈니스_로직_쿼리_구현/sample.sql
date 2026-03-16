-- 34강: 쇼핑몰 핵심 비즈니스 로직 쿼리 구현 실전
-- DML 중심의 쿼리로 구성된 10개의 학습 샘플 스크립트입니다.

-- 1. 장바구니 중복 추가 방지 UPSERT (장바구니 뷰)
-- 장바구니 아이템 담기 (같은 상품 들어올 경우 +1 누적)
INSERT INTO cart_items (cart_id, product_id, option_id, quantity)
VALUES ('cart-id', 'prod-id', 'opt-id', 1)
ON CONFLICT (cart_id, product_id, option_id)
DO UPDATE SET quantity = cart_items.quantity + EXCLUDED.quantity;

-- 2. CTE를 활용한 회원과 기본 주소지 동시 등록
WITH new_user AS (
    INSERT INTO users (email, password_hash)
    VALUES ('hello@shop.co.kr', 'secure_pwd')
    RETURNING user_id
)
INSERT INTO addresses (user_id, address_line, is_default)
SELECT user_id, '부산광역시 해운대구', true
FROM new_user;

-- 3. Ltree 하위 카테고리 전체 상품 리스팅 (1.1 속한 모든 하위 아이템)
SELECT p.title, p.price, c.name as category_name, p.attributes
FROM products p
JOIN categories c ON p.category_id = c.category_id
WHERE c.path <@ '1.1'
ORDER BY p.price DESC;

-- 4. 특정 옵션을 포함하는 JSONB 아이템만 필터링 (GIN Search)
SELECT title, attributes 
FROM products 
WHERE attributes @> '{"brand": "NIKE", "is_limited": true}';

-- 5. 비관적 락(FOR UPDATE)을 이용한 재고 정합성 유지
BEGIN;
SELECT stock_quantity 
FROM inventory 
WHERE option_id = 'opt-uuid' FOR UPDATE;

UPDATE inventory 
SET stock_quantity = stock_quantity - 3, updated_at = NOW()
WHERE option_id = 'opt-uuid' AND stock_quantity >= 3;
COMMIT;

-- 6. 재고가 0이 되어 품절로 세팅하는 로직 (조건부 UPDATE)
UPDATE products 
SET is_active = false 
WHERE product_id IN (
    SELECT p.product_id
    FROM products p
    JOIN product_options po ON p.product_id = po.product_id
    JOIN inventory i ON po.option_id = i.option_id
    GROUP BY p.product_id
    HAVING SUM(i.stock_quantity) = 0
);

-- 7. 주문 취소 시 재고 원복(롤백 로직)과 파티션 테이블 UPDATE
BEGIN;
-- 파티션 테이블 업데이트
UPDATE orders SET status = 'CANCELED' 
WHERE order_id = 'order-id' AND order_date = '2026-02-15';

-- 재고 원상 복구
UPDATE inventory i
SET stock_quantity = stock_quantity + oi.quantity
FROM order_items oi
WHERE oi.order_id = 'order-id' AND i.option_id = oi.option_id;
COMMIT;

-- 8. JSONB 특정 키-값 지우기
-- 상품 옵션 중 color 정보만 누락시킬 때
UPDATE products 
SET attributes = attributes - 'color' 
WHERE product_id = 'prod-uuid';

-- 9. 회원이 소유한 배송지 리스트에서 기본 배송지를 강제로 하나로 맞추는 절차 (가짜 락)
BEGIN;
UPDATE addresses SET is_default = false WHERE user_id = 'user-id';
UPDATE addresses SET is_default = true WHERE address_id = 99 AND user_id = 'user-id';
COMMIT;

-- 10. 주문이 안된 방치된 장바구니 아이템 청소 (Clean up)
DELETE FROM carts WHERE last_updated < NOW() - INTERVAL '30 days';
