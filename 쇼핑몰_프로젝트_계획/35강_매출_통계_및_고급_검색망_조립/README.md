# 35강: 매출 통계 및 고급 검색망 조립

## 개요 
이번 35강은 그동안 만들어온 쇼핑몰을 고도화하고 완성하는 작업입니다. 쇼핑몰 운영에 필요한 각종 통계(월별 매출, 누적 판매량)를 추출하기 위한 SQL 집계 함수와 `ROLLUP` 쿼리를 학습합니다. 추가로, 이전에 학습했던 전문 검색(`tsvector`, `pg_search`) 및 벡터 데이터베이스(`pgvector`)를 접목시켜 하이브리드 검색망까지 함께 구상해봅니다.

## 사용형식 / 메뉴얼 
- 소계 및 총계를 함께 다뤄야 할 때 `GROUP BY ROLLUP`을 활용합니다.
- `pgvector` 확장을 사용한 시맨틱(의미 기반) 상품 추천 기능과 형태소 기반(`BM25`)의 키워드 검색을 함께 스코어 기반으로 가중치를 두고 결합해 최상의 검색 결과를 제공합니다.

## 샘플예제 5선 

[샘플 예제 첫번째] 카테고리별 누적 판매량 조회 (단일 뷰)
```sql
SELECT 
    c.name AS category_name,
    SUM(oi.quantity) AS total_sold,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN categories c ON p.category_id = c.category_id
GROUP BY c.name
ORDER BY revenue DESC;
```
- 샘플 예제 설명: 어느 카테고리의 상품이 제일 잘 팔렸는지를 직관적으로 보여주는 그룹화 쿼리입니다.

[샘플 예제 두번째] ROLLUP을 활용한 소계 기능 구현
```sql
SELECT
    DATE_TRUNC('month', order_date) AS month,
    status AS order_status,
    COUNT(*) AS total_orders,
    SUM(total_amount) AS monthly_revenue
FROM orders
GROUP BY ROLLUP(DATE_TRUNC('month', order_date), status)
ORDER BY month, order_status;
```
- 샘플 예제 설명: 각 월별 주문 상태별 매출에 추가하여 '전체 합산(null)' 열을 보여줘 보고서용 데이터 포맷을 쉽게 뽑아냅니다.

[샘플 예제 세번째] 윈도우 함수를 이용한 고객의 누적 구매액 
```sql
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
```
- 샘플 예제 설명: 특정 고객의 일평생 쇼핑몰 내 누적 구매금액(LTV)을 시간 흐름별로 보여줍니다.

[샘플 예제 네번째] pgvector + tsvector 상품 테이블 구조 생성 
```sql
ALTER TABLE products ADD COLUMN embedding vector(768);
ALTER TABLE products ADD COLUMN search_vector tsvector;
-- GIN 및 HNWS 인덱스 추가 생략
```
- 샘플 예제 설명: 상품 테이블을 확장시켜 LLM이 만든 상품 정보 벡터 배열과 BM25 인덱스용 벡터를 추가로 기록합니다.

[샘플 예제 다섯번째] 하이브리드 통합 검색망 구축
```sql
WITH keyword_search AS (
    SELECT product_id, title, price,
           ts_rank(search_vector, to_tsquery('여름 & 린넨 & 셔츠')) as rank_score
    FROM products
    WHERE search_vector @@ to_tsquery('여름 & 린넨 & 셔츠')
),
vector_search AS (
    SELECT product_id, title, price,
           1 - (embedding <=> '[0.1, 0.4, ...]') as sim_score
    FROM products
    ORDER BY embedding <=> '[0.1, 0.4, ...]' LIMIT 50
)
SELECT k.title, k.price, (k.rank_score * 0.4) + (v.sim_score * 0.6) as final_score
FROM keyword_search k
FULL OUTER JOIN vector_search v ON k.product_id = v.product_id
ORDER BY final_score DESC NULLS LAST
LIMIT 10;
```
- 샘플 예제 설명: 정확한 키워드 매칭(tsvector) 점수와 맥락이 비슷한(pgvector) 점수에 각각 가중치를 곱하고 더해 추천 결과를 끌어냅니다.

## 주의사항 
- 벡터 검색(HNWS) 인덱스는 삽입이 느리고 메모리를 많이 차지하므로 빈번하게 업데이트되는 상품의 트랜잭션 도메인과 분리해서 Elasticsearch와 같은 타 DB에 동기화하거나 읽기 전용으로 백그라운드 갱신하는 것이 안전합니다.
- ROLLUP이나 윈도우 함수(`OVER(...)`)는 매우 무거운 정렬과 스캔을 유발하므로 실시간 애플리케이션보다는 배치 작업(DW)에서 캐싱해두고 사용하는 것을 권장합니다.

## 성능 최적화 방안
[Materialized View 기반의 통계 캐싱]
```sql
-- 매일 자정마다 REFRESH 하는 뷰
CREATE MATERIALIZED VIEW mv_monthly_sales AS
SELECT DATE_TRUNC('month', order_date), SUM(total_amount)
FROM orders GROUP BY 1;

REFRESH MATERIALIZED VIEW mv_monthly_sales;
```
- 성능 개선이 되는 이유: 실시간 누적 스캔 방식(매번 GROUP BY를 수행)은 I/O를 소모하지만 `Materialized View`는 계산이 끝난 정적인 표 형태를 가지고 있어서 매우 높은 읽기 성능을 달성합니다.
