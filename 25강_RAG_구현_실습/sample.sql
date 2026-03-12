-- =========================================================================
-- [25강] RAG 구현 실습 (하이브리드 서치 시스템) - 실전 샘플 쿼리 10선
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- [사전 준비] RAG용 1536 차원급 (가상 3차원) 핵심 다큐먼트 테이블
CREATE TEMP TABLE rag_docs (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200),
    content TEXT,
    is_active BOOLEAN,
    embedding VECTOR(3)
);

-- 검색 데이터 인서트 (IT, 사규 섞여있음)
INSERT INTO rag_docs (title, content, is_active, embedding) VALUES 
('환불규정', '환불은 정책상 30일 내에만 가능합니다.', true, '[0.9, 0.8, 0.7]'),
('구 환불규정', '환불은 7일 내에만 가능', false, '[0.8, 0.9, 0.6]'),
('연차수당', '연차수당은 12월 25일에 지급됩니다.', true, '[-0.9, -0.8, -0.7]'),
('노트북지급', '입사 시 맥북을 지급합니다.', true, '[-0.5, -0.4, -0.3]'),
('모니터지급', '모니터는 1대만 기본 제공됩니다', true, '[-0.4, -0.5, -0.2]');

-- HNSW 인덱스 장착 (검색 최적화)
CREATE INDEX idx_rag_docs_hnsw ON rag_docs USING hnsw (embedding vector_cosine_ops);


-- [샘플 예제 1: 단순 LLM용 서치 쿼리 체인 (Base RAG Retrieval)]
-- 사용자가 "노트북 언제 나와요?" 라고 물었을 때의 Retrieval 과정
SELECT content 
FROM rag_docs 
ORDER BY embedding <=> '[-0.5, -0.5, -0.3]' ASC
LIMIT 1;


-- [샘플 예제 2: 과거 데이터 삭제 방어 - is_active 같은 메타데이터 필터링 융합]
-- 과거 폐기된 환불규정이 튀어나와 챗봇이 환각(Hallucination)에 빠지는 것을 막기 위함
SELECT title, content 
FROM rag_docs 
WHERE is_active = true  -- 구 환불규정 차단망
ORDER BY embedding <=> '[0.95, 0.85, 0.75]' ASC
LIMIT 1;


-- [샘플 예제 3: 검색 거리 임계점 (Distance Threshold) 설정]
-- "비트코인 가격" 이라는 엉뚱한 질문을 던졌을 때, 억지로 아무거나 3개를 안 찾게 막음
SELECT content, (embedding <=> '[0.0, 0.0, 0.0]') AS distance
FROM rag_docs 
WHERE is_active = true 
  AND (embedding <=> '[0.0, 0.0, 0.0]') < 0.20 -- 아주 확신에 찬 결과만 추출
ORDER BY distance ASC;


-- [샘플 예제 4: 답변을 만들기 위한 프롬프트 포매팅(Format) 내장 함수화 맛보기]
-- DB가 아예 프롬프트까지 조립해서 백엔드로 던져주는 극강의 서포팅 쿼리
SELECT '참고 문서 제목: ' || title || E'\n' || '내용: ' || content AS llm_context
FROM rag_docs 
ORDER BY embedding <=> '[-0.9, -0.8, -0.7]' 
LIMIT 1;


-- [하이브리드 서치 개념 시뮬레이션을 위한 세팅 (FTS 연계)]
-- PostgreSQL 에 내장된 텍스트 빈도수 기반 Full-Text Search(FTS) 인덱싱 컬럼 추가
ALTER TABLE rag_docs ADD COLUMN fts_token tsvector;
UPDATE rag_docs SET fts_token = to_tsvector('simple', content);
CREATE INDEX idx_rag_fts ON rag_docs USING GIN (fts_token);


-- [샘플 예제 5: 풀텍스트 서치(FTS) 쿼리 단독 실행]
-- 벡터의 '의미'가 아닌 '환불' 이라는 글자가 정확히 찍힌 빈도수를 위주로 찾기
SELECT id, title, content, ts_rank(fts_token, to_tsquery('simple', '환불')) AS text_rank
FROM rag_docs 
WHERE fts_token @@ to_tsquery('simple', '환불')
ORDER BY text_rank DESC;


-- [샘플 예제 6: 벡터 연산 단독 실행 (Vector Search)]
SELECT id, title, content, (1 - (embedding <=> '[0.9, 0.8, 0.7]')) AS vector_rank
FROM rag_docs 
ORDER BY vector_rank DESC;


-- [샘플 예제 7: RRF (Reciprocal Rank Fusion) 하이브리드 서치]
-- [고급] FTS 순위와 Vector 순위를 서브쿼리로 합쳐서 궁극의 문서 1개를 찾아냄
WITH fts_search AS (
    SELECT id, ROW_NUMBER() OVER(ORDER BY ts_rank(fts_token, to_tsquery('simple', '환불')) DESC) as rank
    FROM rag_docs WHERE fts_token @@ to_tsquery('simple', '환불')
),
vec_search AS (
    SELECT id, ROW_NUMBER() OVER(ORDER BY embedding <=> '[0.9, 0.8, 0.7]' ASC) as rank
    FROM rag_docs
)
SELECT r.title, r.content,
       -- RRF 스코어 공식: 1 / (상수 60 + 각 구문의 순위) 들의 합산
       COALESCE(1.0 / (60 + f.rank), 0.0) + COALESCE(1.0 / (60 + v.rank), 0.0) AS rrf_score
FROM rag_docs r
LEFT JOIN fts_search f ON r.id = f.id
LEFT JOIN vec_search v ON r.id = v.id
WHERE f.rank IS NOT NULL OR v.rank IS NOT NULL
ORDER BY rrf_score DESC LIMIT 2;


-- [샘플 예제 8: RAG 모델의 LLM 토큰 수 관찰 (Length 계산)]
-- LLM은 보통 입력 문자열 너비(Token 제한)가 걸려있습니다. 너무 긴 것은 버려야 함.
SELECT title, LENGTH(content) AS text_len
FROM rag_docs
ORDER BY embedding <=> '[-0.9, -0.8, -0.7]' ASC
LIMIT 3;


-- [샘플 예제 9: 특정 카테고리를 서브쿼리 IN 절로 필터링하는 RAG]
-- 사용자 프로필에 따라 볼 수 있는 문서 권한(ID List)만 인계받아 먼저 자름.
SELECT content 
FROM rag_docs
WHERE id IN (1, 3, 5) -- 이 사람이 열람 가능한 ID 리스트
ORDER BY embedding <=> '[-0.5, -0.4, -0.3]' ASC
LIMIT 1;


-- [샘플 예제 10: RAG 용 16비트 메모리 포맷 (HALFVEC) 생성]
-- 하이브리드 서치를 돌리면 조인과 계산 로직이 극도로 메모리와 CPU를 먹습니다. 
-- 때문에 실무에선 이 임베딩 컬럼 자체를 가장 가벼운 16비트로 밀어넣는 것이 암묵적 룰이 되고 있습니다.
CREATE TEMP TABLE rag_light (
    id INT, 
    content TEXT, 
    embedding HALFVEC(3)
);
-- 이렇게 테이블을 구축해두고 동일한 RRF(7번 예제) 쿼리를 돌리는 시스템이 
-- 백엔드 프로그래머가 구현해야 할 pgvector의 종착지입니다.

-- =========================================================================
-- [조언] pgvector 하나만으로 Pinecone이나 Milvus 같은 거대 VectorDB를 
-- 거의 공짜로 대체할 수 있습니다. 위 예제의 RRF(하이브리드 결합 방식) 쿼리문을
-- 마이바티스(MyBatis)나 JPA QueryDSL 로 짠 뒤 LLM과 물리면 그것이 곧 10억짜리 RAG 시스템입니다.
-- =========================================================================
