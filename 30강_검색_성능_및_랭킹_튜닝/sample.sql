-- =========================================================================
-- [30강] 검색 성능 및 랭킹 튜닝 (RAG Q&A 프로젝트) - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 최종 상용 하이브리드 레벨(BM25 + HNSW)에서 검색 응답의 질(점수 가중치)을 세공하고,
-- 0.5초가 넘어가는 지연(Latency) 핑핑이를 디스크 옵션 및 작업 램(Work Mem) 해제로 잡아냅니다.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;

-- 문서 저장소 세팅
CREATE TEMP TABLE qa_docs (
    id SERIAL PRIMARY KEY,
    title VARCHAR(150),
    content TEXT,
    embedding VECTOR(3),
    category VARCHAR(50),
    view_count INT
);

INSERT INTO qa_docs (title, content, embedding, category, view_count) VALUES 
('정기구독 해지 안내', '해지는 마이페이지에서 다음 결제일 이전에 가능합니다.', '[0.9, 0.8, 0.7]', 'billing', 500),
('환불 약관', '디지털 상품은 다운로드 이력이 없을 때만 환불 가능합니다.', '[0.85, 0.75, 0.65]', 'billing', 100),
('비밀번호 찾기', '이메일 인증을 통해 초기화할 수 있습니다.', '[-0.5, -0.4, -0.3]', 'account', 300),
('구독권 양도', '타인에게 계정 귀속 구독권을 양도할 수 없습니다.', '[0.9, 0.9, 0.8]', 'billing', 50),
('정기 점검시간', '매주 목요일 새벽 2시부터 4시까지 입니다.', '[-0.1, 0.0, 0.1]', 'notice', 200);

CALL paradedb.create_bm25(index_name => 'idx_qa_bm25', table_name => 'qa_docs', key_field => 'id', text_fields => '{title, content}');
CREATE INDEX idx_qa_vector ON qa_docs USING hnsw (embedding vector_cosine_ops);


-- [샘플 예제 1: BM25 Boost(가중치)를 활용한 제목(Title) 어드밴티지 부여 서치]
-- "해지" 란 검색어가 "본문"에 나타난 문서보다, "제목"에 나타난 문서의 스코어를 3.0배(^) 폭증시켜 끌어올립니다.
SELECT title, paradedb.score('idx_qa_bm25', id) AS boost_score
FROM qa_docs 
WHERE id @@@ paradedb.parse('title:해지^3.0 OR content:해지')
ORDER BY boost_score DESC;


-- [샘플 예제 2: 과거 FTS 엔진(ts_rank)의 setweight 를 통한 가중치 랭킹]
-- (ParadeDB 설치 불가 시 차선책) 'A' 라벨(보통 헤더, 제목) 단어에 가산 부여
SELECT title,
       ts_rank(setweight(to_tsvector('korean', title), 'A') || setweight(to_tsvector('korean', content), 'D'), 
               to_tsquery('korean', '해지')) AS fts_score
FROM qa_docs
ORDER BY fts_score DESC LIMIT 2;


-- [샘플 예제 3: RRF 공식의 상수(K) 튜닝 실험 (기본값 K=60 이 아닌 K=10 의 극단치)]
-- (순위 1등과 2등의 RRF 점수 격차를 무자비하게 벌려, 확신에 찬 결과만 위로 남기기 위함)
WITH b_search AS (
    SELECT id, ROW_NUMBER() OVER(ORDER BY paradedb.score('idx_qa_bm25', id) DESC) as r_b
    FROM qa_docs WHERE id @@@ paradedb.parse('구독') LIMIT 5
),
v_search AS (
    SELECT id, ROW_NUMBER() OVER(ORDER BY embedding <=> '[0.9, 0.9, 0.7]' ASC) as r_v
    FROM qa_docs LIMIT 5
)
SELECT d.title,
       -- K=10 세팅 (격차 펌핑)
       COALESCE(1.0 / (10 + b.r_b), 0.0) + COALESCE(1.0 / (10 + v.r_v), 0.0) AS extreme_rrf
FROM qa_docs d
LEFT JOIN b_search b ON d.id = b.id
LEFT JOIN v_search v ON d.id = v.id
WHERE b.r_b IS NOT NULL OR v.r_v IS NOT NULL
ORDER BY extreme_rrf DESC;


-- [샘플 예제 4: 정렬(Sorter) 램 폭주를 막기 위한 인프라 파라미터 Session 스위핑]
-- 하이브리드는 ORDER BY (정렬)를 2배로 수반합니다. 디스크가 아닌 오직 RAM 상에서 전부 정렬되도록 세션 워크 메모리를 허물어 줌.
SET LOCAL work_mem = '64MB';
-- 그리고 검색 쿼리 실행...


-- [샘플 예제 5: 벡터 그래프 그물망(HNSW)의 검색 깊이(ef_search) 세밀 제어]
-- (정밀도가 떨어져도 IO Wait 타임아웃을 피하려면 무조건 깊이를 낮춥니다)
SET LOCAL hnsw.ef_search = 10;
-- 그리고 검색 쿼리 실행...


-- [샘플 예제 6: SSD 읽기 비용의 최적화 - NVMe 특성 타기 (통계 비용 강제 다운스케일링)]
-- 디스크의 무작위 찌르기(Random Page)가 B-Tree나 GIN 스캔 시 엄청 싸다는 걸 옵티마이저에게 가스라이팅.
SET LOCAL random_page_cost = 1.1; 
-- 이후 쿼리는 무조건 인덱스를 탐 (Table Full Scan 무시).


-- [샘플 예제 7: 성능 폭망의 주범 - Vector 형 자체를 클라이언트로 반환해버리는 실수 (네트워크 I/O 폭발)]
-- [안좋은 예] SELECT title, embedding FROM qa_docs (X) (1536차원 부동소수점 배열을 왜 끄집어냅니까?)
-- [좋은 예] SELECT title, content, id FROM qa_docs (O)
SELECT title, content 
FROM qa_docs 
ORDER BY embedding <=> '[0.8, 0.8, 0.8]' 
LIMIT 1; 
-- 정답인 제목과 본문만 가볍게 빼내는 게 백엔드의 덕목입니다.


-- [샘플 예제 8: (비즈니스 관점) 조회수 필드로 BM25 문서 점수에 양념 치기]
-- 사람들이 가장 많이 본(views) 문서는 정답일 확률이 높으니, 
-- BM25 가 산출한 언어적 등수(score) 옆에 views 의 로그값(log) 정도를 곱해, 살짝 부스트를 줌.
SELECT title, 
       -- view_count가 1이상이면 로그수치로 가산비례 보정 (LN)
       paradedb.score('idx_qa_bm25', id) * (1.0 + LN(GREATEST(view_count, 1))) AS popular_bm25_score
FROM qa_docs 
WHERE id @@@ paradedb.parse('결제')
ORDER BY popular_bm25_score DESC;


-- [샘플 예제 9: 카테고리(Category)가 무려 3개나 되는 메타 필터 방어망 쿼리 치기]
-- 이런 식별성 높은(Cardinality) 스칼라 문자열 필터 등을 먼저 쳐야, 복잡한 거리 계산의 후보군(모수)이 확 줄어 튜닝이 됩니다.
SELECT title 
FROM qa_docs 
WHERE category IN ('billing', 'account', 'notice') -- 후보군 도메인 1차 제동
ORDER BY embedding <=> '[0.9, 0.8, 0.7]' 
LIMIT 3;


-- [샘플 예제 10: RAG 백엔드 전송용 - 최종 JSON 어그리게이션 추출기]
-- LLM 프롬프트가 한 번에 꿀꺽 집어삼키게 편하도록, 상위 3개 문서를 DB에서 아예 JSON List 로 뭉쳐서 반환합니다.
WITH top_docs AS (
    SELECT title, content 
    FROM qa_docs 
    ORDER BY embedding <=> '[0.9, 0.9, 0.7]' 
    LIMIT 3
)
SELECT json_agg(
           json_build_object('doc_title', title, 'doc_content', content)
       ) AS llm_context_json
FROM top_docs;

-- =========================================================================
-- [조언] pgvector 와 pg_search 의 조합, 그리고 하이브리드 RRF 와 메모리 튜닝까지
-- 마치셨다면 당신은 이제 어떠한 LLM (OpenAI, Claude, 오픈소스 Llama) 의
-- 두뇌에 당신의 사내 문서를 완벽하고 즉각적으로 이식할 수 있는 최정상급
-- 'AI Vector DB 아키텍트' 의 반열에 올랐습니다. 튜토리얼을 수료하심을 축하합니다!
-- =========================================================================
