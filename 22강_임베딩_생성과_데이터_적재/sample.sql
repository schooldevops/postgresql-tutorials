-- =========================================================================
-- [22강] 임베딩(Embedding) 생성과 데이터 적재 - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 외부 임베딩 모델(OpenAI, HuggingFace)에서 추출해 온 숫자 배열(Vector)들을
-- pgvector 로 확장된 테이블에 적재하고 무결성을 테스트하는 예제들입니다.

CREATE EXTENSION IF NOT EXISTS vector;

-- [샘플 예제 1: 가장 대중적인 RAG 지식베이스 뼈대 테이블 생성]
-- 문서 원본(content)과 AI 모델의 차원(1536)이 정확히 매칭됨을 선언합니다.
CREATE TEMP TABLE knowledge_base (
    doc_id SERIAL PRIMARY KEY,
    title VARCHAR(200),
    content TEXT,
    embedding VECTOR(1536)
);


-- [샘플 예제 2: 차원이 맞지 않는 악성 데이터 삽입 방어 테스트]
-- 1536차원으로 박혀있는 테이블에 실수로 3차원 데이터가 날아오면 철저하게 에러를 뱉고 롤백합니다.
-- INSERT INTO knowledge_base (title, embedding) VALUES ('에러 테스트', '[0.1, 0.2, 0.3]');


-- (원활한 테스트를 위해 3차원짜리 장난감 테이블로 재선언)
CREATE TEMP TABLE kb_toy (
    doc_id SERIAL PRIMARY KEY,
    chunk_text TEXT,
    embedding VECTOR(3)
);


-- [샘플 예제 3: 단일 행(Row) 텍스트 기반 벡터 삽입]
-- 백엔드에서 JSON이나 String 형태로 된 대괄호 배열을 그대로 던집니다.
INSERT INTO kb_toy (chunk_text, embedding) 
VALUES ('대한민국의 수도는 서울입니다.', '[0.11, 0.55, -0.21]');


-- [샘플 예제 4: 다중 행(Multi-Row) Bulk 삽입 패턴]
-- ORM 이나 드라이버를 거칠 때, 1000개 정도의 묶음(Batch)을 하나로 던져 TCP왕복 비용을 절약합니다.
INSERT INTO kb_toy (chunk_text, embedding) VALUES 
('프랑스의 수도는 파리입니다.', '[0.10, 0.50, -0.20]'),
('사과는 맛있고 빨갛다.', '[0.99, -0.88, 0.11]'),
('바나나는 길고 노랗다.', '[0.95, -0.85, 0.15]');


-- [샘플 예제 5: String 파싱(Casting) 변환 쿼리]
-- 엄격한 프레임워크 제어 시 문자열(String)이 벡터타입(VECTOR)임을 명시적으로 변환 기재합니다.
INSERT INTO kb_toy (chunk_text, embedding) 
VALUES ('명시적 타입 캐스팅 텍스트', CAST('[0.1, 0.2, 0.3]' AS VECTOR(3)));


-- [샘플 예제 6: ON CONFLICT 를 이용한 무중단 벡터 업데이트 (UPSERT)]
-- PK 나 고유키 기준, 문서 내용이 고쳐서 들어왔다면 과거 임베딩 값을 최신 모델 값으로 덮어치기 합니다.
ALTER TABLE kb_toy ADD CONSTRAINT unique_chunk_text UNIQUE (chunk_text);

INSERT INTO kb_toy (chunk_text, embedding) 
VALUES ('대한민국의 수도는 서울입니다.', '[0.12, 0.56, -0.22]') -- 임베딩 값이 약간 조정됨
ON CONFLICT (chunk_text) 
DO UPDATE SET embedding = EXCLUDED.embedding;


-- [샘플 예제 7: 테이블 내에서 두 백터끼어 더해서 새로운 위치 계산하기]
-- 의미상 합성이 필요한 경우, 벡터끼리는 일반 숫자처럼 수학 덧셈(+), 뺄셈(-) 연산자가 먹힙니다.
SELECT doc_id, chunk_text, (embedding + '[0.1, 0.1, 0.1]') AS shifted_vector
FROM kb_toy 
WHERE doc_id = 1;


-- [샘플 예제 8: 벡터의 노름(Norm, 스칼라 크기/길이) 구하기]
-- 벡터의 정규화(Normalization) 상태를 확인하거나 그 자체의 힘(규모)을 확인할 때 쓰는 벡터 전용 함수입니다.
SELECT chunk_text, vector_norm(embedding) AS vector_magnitude
FROM kb_toy;


-- [샘플 예제 9: 특정 노드를 중심으로 값의 배열(Vector) 평균값 구하기]
-- 사과와 바나나 데이터가 이루는 군집의 정가운데(중심) 앵커(Anchor) 벡터 좌표를 도출합니다.
SELECT AVG(embedding) as centroid_fruit_vector
FROM kb_toy 
WHERE chunk_text LIKE '%빨갛다%' OR chunk_text LIKE '%바나나%';


-- [샘플 예제 10: 메모리를 절반만 먹는 절반 정밀도(Half-Precision) 하프벡터 사용 맛보기]
-- (PostgreSQL 16 이상 최신 버전에서 동작) 32비트 실수가 갖는 용량적 한계를 부수고 16비트로 밀어넣는 가성비 저장소.
CREATE TEMP TABLE kb_half_toy (
    id SERIAL,
    embedding HALFVEC(3)
);
INSERT INTO kb_half_toy (embedding) VALUES ('[0.3456, 0.1234, 0.9876]');
-- 이 때 HALFVEC 내부에선 지저분하게 긴 소수점 꼬리가 자체적으로 짧게 절삭/반올림 처리되어 들어갑니다.

-- =========================================================================
-- [조언] 대용량 문서 적재 시에는 Python 등에서 `psycopg2`의 `execute_batch` 나
-- `COPY` 객체를 스트림(stream)으로 연결하여 디비에 직결로 때려넣는 방식이 성능의 왕입니다.
-- =========================================================================
