# PostgreSQL 실무 및 AI 검색 완벽 마스터 커리큘럼

## 1. 기본 강의 (1강 ~ 10강): PostgreSQL 입문 및 SQL 기초
데이터베이스의 기본기를 다지고 PostgreSQL의 표준 SQL 문법을 익히는 과정입니다.

| 강좌 | 주제 | 핵심 내용 |
| :--- | :--- | :--- |
| [**1강**](./1강_PostgreSQL_아키텍처와_시작/README.md) | PostgreSQL 아키텍처와 시작 | 설치, 기본 구조(Process, Memory), psql 도구 사용법 |
| [**2강**](./2강_데이터_타입과_DDL/README.md) | 데이터 타입과 DDL | 정수, 문자, 날짜형 및 테이블/스키마 생성과 수정 |
| [**3강**](./3강_데이터_조작어_DML/README.md) | 데이터 조작어 (DML) | INSERT, UPDATE, DELETE 기초 및 RETURNING 절 |
| **4강** | 조건부 검색과 연산자 | SELECT, WHERE, LIKE, IN, NULL 처리 방식 |
| **5강** | 데이터 정렬과 페이징 | ORDER BY, LIMIT, OFFSET을 활용한 실무 페이징 처리 |
| **6강** | 다중 테이블 연결 (JOIN) | INNER, LEFT/RIGHT OUTER, FULL OUTER JOIN |
| **7강** | 집계 함수와 데이터 그룹화 | GROUP BY, HAVING, COUNT, SUM, AVG 연산 |
| **8강** | 서브쿼리와 공통 테이블 식 | 스칼라/인라인 뷰 서브쿼리, CTE(WITH 절) 작성법 |
| **9강** | 무결성과 제약 조건 | Primary Key, Foreign Key, UNIQUE, CHECK 설정 |
| **10강** | 트랜잭션의 이해 | ACID 특성, COMMIT, ROLLBACK 기초 |

---

## 2. 고급 강의 (11강 ~ 20강): 아키텍처 최적화 및 운영
단순한 쿼리를 넘어, 대용량 데이터를 처리하고 성능을 튜닝하는 아키텍처 레벨의 기술을 다룹니다.

| 강좌 | 주제 | 핵심 내용 |
| :--- | :--- | :--- |
| **11강** | 인덱스 아키텍처와 종류 | B-Tree, Hash, GIN, GiST 인덱스의 이해와 선택 전략 |
| **12강** | 실행 계획과 쿼리 튜닝 | EXPLAIN ANALYZE 해석, 테이블 풀 스캔 방지 기법 |
| **13강** | 윈도우 함수 (Window Function) | 순위(RANK), 누적합, 이동 평균 등 고급 분석 쿼리 |
| **14강** | 대용량 데이터 파티셔닝 | Range, List 파티셔닝을 통한 테이블 분할 및 관리 |
| **15강** | 동시성 제어와 격리 수준 | MVCC 아키텍처, Deadlock 방지, 트랜잭션 격리 수준 |
| **16강** | 뷰와 구체화된 뷰 (Materialized View) | 복잡한 쿼리 단순화 및 REFRESH를 통한 성능 향상 |
| **17강** | 서버 사이드 프로그래밍 | PL/pgSQL을 활용한 스토어드 함수와 트리거(Trigger) |
| **18강** | NoSQL처럼 활용하기 | JSON/JSONB 데이터 타입 인덱싱 및 쿼리 처리 기법 |
| **19강** | 백업, 복구 및 접근 제어 | pg_dump, 역할(Role) 관리, RLS(행 수준 보안) |
| **20강** | 고가용성과 커넥션 풀링 | 스트리밍 레플리케이션 기초 및 PgBouncer 활용 |

---

## 3. pgvector (21강 ~ 25강): AI 및 벡터 데이터베이스 활용
AI 도구 연동 및 시맨틱 검색을 위한 벡터 데이터베이스 구축 과정을 학습합니다.

| 강좌 | 주제 | 핵심 내용 |
| :--- | :--- | :--- |
| **21강** | pgvector 소개 및 설치 | 확장(Extension) 활성화, Vector 데이터 타입의 구조 |
| **22강** | 임베딩 생성과 데이터 적재 | 텍스트 임베딩 모델 연동 후 벡터 데이터 INSERT |
| **23강** | 벡터 유사도 연산자 | L2 거리, 코사인 유사도, 내적(Inner Product) 계산 |
| **24강** | pgvector 인덱스 최적화 | IVFFlat, HNSW 알고리즘의 차이 및 인덱스 생성 기법 |
| **25강** | AI 모델 연동 실습 | LLM API와 연동하여 문서 기반 RAG 시스템 DB 구축 |

---

## 4. pgsearch (26강 ~ 30강): 전문 검색 및 하이브리드 검색
전통적인 RDBMS의 한계를 넘는 고성능 Full-Text Search와 BM25 기반 검색을 학습합니다.

| 강좌 | 주제 | 핵심 내용 |
| :--- | :--- | :--- |
| **26강** | 내장 Full-Text Search | TSVECTOR, TSQUERY 기초 및 텍스트 검색 아키텍처 |
| **27강** | 한국어 형태소 분석기 연동 | N-gram 및 형태소 분석기(은전한닢 등) 설정 및 적용 |
| **28강** | pg_search 확장 활용 | ParadeDB/pg_search 기반 BM25 알고리즘 검색 구현 |
| **29강** | 하이브리드 검색 구현 | 벡터 유사도(pgvector) + 키워드 검색(BM25) 스코어 결합 |
| **30강** | 검색 성능 및 랭킹 튜닝 | 검색 결과 가중치(Weight) 설정, 실시간 검색 인덱스 최적화 |

---

## 5. 실전 프로젝트: 쇼핑몰 DB 모델링 및 실무 쿼리 튜닝
앞서 배운 개념을 종합하여, 실제 서비스 가능한 수준의 이커머스 데이터베이스를 설계하고 복잡한 쿼리를 작성합니다.

### 5.1 데이터베이스 모델링 프로세스
| 단계 | 주요 작업 | 상세 설명 |
| :--- | :--- | :--- |
| **논리적 모델링** | 요구사항 분석 및 엔티티 도출 | 회원, 상품, 카테고리, 주문, 결제, 장바구니 엔티티 정의 |
| **물리적 모델링** | 데이터 타입 및 인덱스 설계 | 금액은 `NUMERIC`, 옵션은 `JSONB`, 식별자는 `UUID` 매핑 |
| **연관관계 설계** | 1:N, N:M 관계 및 FK 설정 | 회원-주문(1:N), 상품-주문상세(1:N), 다대다 관계 해소 |
| **실제 설계** | DDL 작성 및 최적화 | 파티셔닝 적용(월별 주문 이력) 및 GIN, B-Tree 인덱스 생성 |

### 5.2 주요 실무 및 복잡한 쿼리 예제

**1. 재고 차감 시 동시성 제어 (Pessimistic Locking)**
여러 사용자가 동시에 같은 상품을 구매할 때 재고가 음수가 되는 것을 방지합니다.
```sql
BEGIN;
-- 특정 상품의 레코드에 락을 걸어 다른 트랜잭션의 수정을 대기시킴
SELECT stock_quantity 
FROM products 
WHERE product_id = 'p_1001' FOR UPDATE;

UPDATE products 
SET stock_quantity = stock_quantity - 2 
WHERE product_id = 'p_1001';
COMMIT;
```

**2. 윈도우 함수를 활용한 사용자별 월별 누적 구매액 및 등급 산정**
최근 3개월간의 구매액을 누적 합산하여 실시간으로 유저의 등급을 계산합니다.
```sql
SELECT 
    user_id,
    order_month,
    monthly_total,
    SUM(monthly_total) OVER (
        PARTITION BY user_id 
        ORDER BY order_month 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) as rolling_3month_total
FROM (
    SELECT 
        user_id, 
        DATE_TRUNC('month', order_date) as order_month,
        SUM(total_amount) as monthly_total
    FROM orders
    GROUP BY user_id, DATE_TRUNC('month', order_date)
) sub;
```

**3. pgvector + pgsearch 하이브리드 상품 추천 쿼리**
키워드 검색(BM25)과 의미 기반 검색(HNSW Vector)을 결합하여 가장 관련성 높은 상품을 찾습니다.
```sql
WITH keyword_search AS (
    SELECT product_id, title, 
           bm25_score(search_vector, '스마트폰 무선 충전기') as rank_score
    FROM products
    WHERE search_vector @@ '스마트폰 & 무선 & 충전기'
),
vector_search AS (
    SELECT product_id, title,
           1 - (embedding <=> '[0.12, 0.45, ...]') as sim_score
    FROM products
    ORDER BY embedding <=> '[0.12, 0.45, ...]' LIMIT 50
)
SELECT k.title, (k.rank_score * 0.4) + (v.sim_score * 0.6) as final_score
FROM keyword_search k
FULL OUTER JOIN vector_search v ON k.product_id = v.product_id
ORDER BY final_score DESC NULLS LAST
LIMIT 10;
```