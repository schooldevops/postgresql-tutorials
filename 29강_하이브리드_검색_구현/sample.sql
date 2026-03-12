-- =========================================================================
-- [29강] 하이브리드 검색 구현 (Vector + Keyword) - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: (25강 하이브리드 기초판과 연계) 키워드 서치의 정밀함과
-- 벡터 서치의 문맥적 유연성을 RRF(Reciprocal Rank Fusion) 알고리즘으로
-- 합체시켜, 어떤 질문에도 무너지지 않는 궁극의 RAG 검색을 완성합니다.

-- [사전 준비] FTS 기반과 Vector 기반이 조화된 3차원 문서 테이블
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;

CREATE TEMP TABLE hc_documents (
    doc_id SERIAL PRIMARY KEY,
    title VARCHAR(100),
    content TEXT,
    embedding VECTOR(3),
    tenant_id INT
);

INSERT INTO hc_documents (title, content, embedding, tenant_id) VALUES 
('환불 정책', '구입일로부터 30일 이내에 영수증 지참 시 가능', '[0.9, 0.8, 0.7]', 101),
('포인트 환급', '결제 시 사용한 포인트는 24시간 내 반환됩니다.', '[0.8, 0.9, 0.6]', 101),
('배송 관련', '오후 2시 이전 결제 시 당일 출고.', '[-0.5, -0.6, -0.7]', 101),
('반품불가', '할인 상품이나 전자기기는 단순변심 시 불가', '[0.75, 0.85, 0.75]', 102);

-- 인덱스
CREATE INDEX idx_hc_vector ON hc_documents USING hnsw (embedding vector_cosine_ops);
CALL paradedb.create_bm25(index_name => 'idx_hc_bm25', table_name => 'hc_documents', key_field => 'doc_id', text_fields => '{title, content}');


-- [샘플 예제 1: Vector 단독 검색의 약점 (오직 의미만 추적)]
-- "환불 규정" 에 대한 질문을 벡터로 변환('[0.8, 0.8, 0.8]')해서 던졌을 때,
-- "반품불가" 나 "포인트 환급" 이라도 방향이 비슷하면 점수를 주어 상위로 올려버립니다.
SELECT title, (embedding <=> '[0.8, 0.8, 0.8]') AS vector_dist
FROM hc_documents
ORDER BY vector_dist ASC 
LIMIT 3;


-- [샘플 예제 2: 키워드(BM25) 단독 검색의 약점 (유의어 인지 불가)]
-- "돈 돌려받고 싶어요" 라고 물으면 본문이나 제목에 '돈' 이라는 글씨가 한 자도 없어서
-- 정답인 환불 규정을 아예 검색 풀에서 배제시켜 버립니다 (0건 출력).
SELECT title 
FROM hc_documents 
WHERE doc_id @@@ paradedb.parse('돈');


-- [샘플 예제 3: RRF (Reciprocal Rank Fusion) 골격 완성 쿼리]
-- 벡터와 BM25 양쪽의 순위표(등수)를 각각 뽑고 FULL JOIN 하여 수식으로 합체(Fusion).
-- (사용자 질문: "환불", 임베딩: '[0.9, 0.9, 0.7]')
WITH bm25_search AS (
    SELECT doc_id, ROW_NUMBER() OVER(ORDER BY paradedb.score('idx_hc_bm25', doc_id) DESC) as rank_b
    FROM hc_documents WHERE doc_id @@@ paradedb.parse('환불') 
    LIMIT 20
),
vector_search AS (
    SELECT doc_id, ROW_NUMBER() OVER(ORDER BY embedding <=> '[0.9, 0.9, 0.7]' ASC) as rank_v
    FROM hc_documents 
    LIMIT 20
)
SELECT d.title,
       -- RRF Score 계산! (상수 60 을 씁니다)
       COALESCE(1.0 / (60 + b.rank_b), 0.0) + COALESCE(1.0 / (60 + v.rank_v), 0.0) AS rrf_score
FROM hc_documents d
LEFT JOIN bm25_search b ON d.doc_id = b.doc_id
LEFT JOIN vector_search v ON d.doc_id = v.doc_id
WHERE b.rank_b IS NOT NULL OR v.rank_v IS NOT NULL
ORDER BY rrf_score DESC 
LIMIT 3;


-- [샘플 예제 4: 하이브리드 결합 내 메타데이터 필터링(Tenant 분리로 보안 강화)]
-- 서브쿼리 각각의 공간 내부에서 "101 번 고객"만 뒤지게끔 철통 방어선을 칩니다.
WITH bm25 AS (
    SELECT doc_id, ROW_NUMBER() OVER(ORDER BY paradedb.score('idx_hc_bm25', doc_id) DESC) as r_b
    FROM hc_documents WHERE doc_id @@@ paradedb.parse('환불') AND tenant_id = 101 LIMIT 10
),
vec AS (
    SELECT doc_id, ROW_NUMBER() OVER(ORDER BY embedding <=> '[0.9, 0.9, 0.7]' ASC) as r_v
    FROM hc_documents WHERE tenant_id = 101 LIMIT 10
)
SELECT d.doc_id, d.title
FROM hc_documents d
LEFT JOIN bm25 b ON d.doc_id = b.doc_id
LEFT JOIN vec v ON d.doc_id = v.doc_id
WHERE (b.r_b IS NOT NULL OR v.r_v IS NOT NULL) AND d.tenant_id = 101
ORDER BY COALESCE(1.0/(60+b.r_b), 0.0) + COALESCE(1.0/(60+v.r_v), 0.0) DESC;


-- [샘플 예제 5: 벡터 엔진에 걸린 과몰입 스캔 부하 압축 튜닝]
-- HNSW 가 그물망을 이웃 노드로 깊게 안 타고(ef_search = 15) 가볍게 스캔만 치게 만듭니다.
-- 왜냐면 정답이 30위 밖이라도, 키워드(BM25) 서치가 알아서 1등으로 끌어당겨 합산해줄 거니까요!
SET LOCAL hnsw.ef_search = 15;


-- [샘플 예제 6: 알파(Alpha) 가중치를 부여한 검색 밸런싱 조합]
-- RRF가 수학적 순위 결합이라면, 이 방식은 "벡터 점수 * Alpha + 키워드 점수 * (1-Alpha)" 처럼
-- 벡터 자체를 더 신뢰할지(ex: Alpha 0.8), 키워드를 신뢰할지 정수값 조율 방식입니다 (고급 통계용).
-- (벡터 거리는 0으로 갈수록 좋고 BM25 점수는 클수록 좋으므로 정밀한 정규화(Normalization) 과정이 선행되어야 합니다)


-- [샘플 예제 7: RRF 수학 공식의 상수(K=60) 의 의미 파악해보기]
-- "왜 60을 쓰죠?"
-- 만약 K가 1이면, 1등 점수는 1/2(0.5) 이고 2등 점수는 1/3(0.33) 이 되어 차이가 너무 심하게 깎입니다.
-- K가 60이면, 1등은 1/61(0.01639), 2등은 1/62(0.01612) 로 격차가 매우 "부드러운(Smoothing)" 감가상각이 일어납니다.


-- [샘플 예제 8: 백엔드 개발자의 최상위 덕목 "LIMIT 제어"]
-- 상기 3번 예제에서 CTE 안에 LIMIT 이 없다면 100만 건 데이터 조심! FULL JOIN 이 메모리 폭발을 일으킵니다.


-- [샘플 예제 9: 복합 질의(Phase) 가 HNSW 보다 응답/결과가 우월한 쿼리]
-- "아이폰 15 프로" 라고 검색하면 LLM 벡터 임베딩은 그냥 "핸드폰" 따위로 두루뭉술하게 만들어버립니다.
-- 이러면 백날 벡터 쿼리를 짜봐야 정답 매칭이 안되므로 키워드의 정확도가 이 하이브리드 서치의 최종 구원투수가 됩니다.


-- [샘플 예제 10: RAG 용 프롬프트 조립을 위한 LLM 용 문자열 축적 (Agg)]
-- 하이브리드로 뽑힌 최종 우승자 TOP 3 건을 가져와서, `STRING_AGG` 로 하나의 거대한 텍스트로 합칩니다.
-- (Chat API 나 GPT 한테 보낼 System 문맥 토큰 덩어리를 DB 단에서 전부 깔끔하게 본딩해서 발사)

-- =========================================================================
-- [조언] 하이브리드 RRF 는 최고의 성능과 정확도를 보장하지만 양쪽의 IO 자원을 모두 채굴합니다.
-- 따라서 가장 앞에 들어가는 "Where 카테고리 / User Id / 회사 Id / 날짜 범위" 의
-- 스칼라 메타 필터링이 안 들어가서 10만 건 이상의 범위를 풀 샷 때리면 CPU 가 못 버팁니다.
-- =========================================================================
