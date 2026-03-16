-- 35강: 매출 통계 및 고급 검색망 조립 샘플 쿼리
-- 통계/집계 및 고급 추천, 검색 시스템의 10가지 활용 예시들입니다.

-- 1. 카테고리별 누적 판매량 및 매출 조회 (JOIN, 집계 함수)
SELECT 
    c.name AS category_name,
    SUM(oi.quantity) AS total_sold,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN categories c ON p.category_id = c.category_id
GROUP BY c.name
ORDER BY revenue DESC;

-- 2. 제품 옵션별 재고 현황 (GROUP BY)
SELECT
    po.option_name,
    i.stock_quantity
FROM inventory i
JOIN product_options po ON i.option_id = po.option_id
WHERE i.stock_quantity < 10
ORDER BY i.stock_quantity ASC;

-- 3. ROLLUP을 활용한 소계 기능 구현 (월별/주문상태별 합산 및 총합)
SELECT
    DATE_TRUNC('month', order_date) AS month,
    status AS order_status,
    COUNT(*) AS total_orders,
    SUM(total_amount) AS monthly_revenue
FROM orders
GROUP BY ROLLUP(DATE_TRUNC('month', order_date), status)
ORDER BY month, order_status;

-- 4. 윈도우 함수: 고객의 개인별 생애 가치(LTV, 누적 구매액) 
SELECT 
    user_id,
    order_date,
    total_amount,
    SUM(total_amount) OVER (
        PARTITION BY user_id 
        ORDER BY order_date 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) as lifetime_value
FROM orders
ORDER BY user_id, order_date;

-- 5. pgvector 확장이 있다고 가정한 뒤, 상품 테이블 확장하기 (DDL)
ALTER TABLE products ADD COLUMN embedding vector(768);
ALTER TABLE products ADD COLUMN search_vector tsvector;

-- 6. 형태소 분석 정보를 search_vector에 밀어 넣는 예시 (Korean)
-- UPDATE products SET search_vector = to_tsvector('korean', title || ' ' || (attributes->>'description'));

-- 7. BM25 키워드 랭킹 스코어만 조회
SELECT product_id, title,
       ts_rank(search_vector, to_tsquery('여름 & 린넨 & 셔츠')) as rank_score
FROM products
WHERE search_vector @@ to_tsquery('여름 & 린넨 & 셔츠');

-- 8. pgvector: 나의 장바구니에 담은 유사 속성의 상품 10개 추천 받기 (코사인 거리)
SELECT product_id, title,
       1 - (embedding <=> (SELECT embedding FROM products WHERE product_id = 'my-liked-item-id') ) as sim_score
FROM products
WHERE product_id != 'my-liked-item-id'
ORDER BY embedding <=> (SELECT embedding FROM products WHERE product_id = 'my-liked-item-id')
LIMIT 10;

-- 9. 하이브리드 검색망 (keyword_search CTE + vector_search CTE) - 본문 참조
-- 이전에 설명한 두 개의 쿼리를 조인하여 (k.rank_score * 0.4) + (v.sim_score * 0.6) 공식을 적용하여 점수를 정렬시킵니다.

-- 10. Materialized View(구체화된 뷰)를 활용한 통계 캐싱 처리
CREATE MATERIALIZED VIEW mv_monthly_sales AS
SELECT DATE_TRUNC('month', order_date) as t_month, SUM(total_amount) as sales
FROM orders GROUP BY 1;

-- 매일 또는 매시각 실행시 뷰 갱신:
-- REFRESH MATERIALIZED VIEW mv_monthly_sales;
