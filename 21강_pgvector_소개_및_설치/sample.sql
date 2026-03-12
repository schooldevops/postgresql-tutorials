-- =========================================================================
-- [21강] pgvector 소개 및 설치 - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 차세대 AI 데이터베이스로서의 필수 관문인 pgvector 익스텐션을 활성화시키고,
-- 차원(Dimension)을 정의한 VECTOR 컬럼 생성 및 3가지 거리 연산 방식을 테스트합니다.

-- [샘플 예제 1: pgvector 익스텐션 활성화 및 설치 점검]
-- 물리 서버에 모듈이 깔려있다는 가정 하에 DB에 익스텐션을 등록합니다.
CREATE EXTENSION IF NOT EXISTS vector;

-- 제대로 설치되었는지 확장 모듈 리스트 뷰를 찔러 확인합니다.
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';


-- [샘플 예제 2: 3차원 벡터(VECTOR 타입)를 탑재한 장난감 아이템 테이블 생성]
CREATE TEMP TABLE toy_vectors (
    item_id SERIAL PRIMARY KEY,
    item_name VARCHAR(50),
    description TEXT,
    embedding VECTOR(3) -- 3개의 실수 좌표(x, y, z)만 받는 벡터 공간
);


-- [샘플 예제 3: 다수의 숫자 배열을 텍스트 껍데기로 감싸서 데이터 삽입]
-- 백엔드(파이썬 등)에서 배열 모델 결과값을 DB 텍스트 포맷으로 쏴주는 형태 시뮬레이션입니다.
INSERT INTO toy_vectors (item_name, description, embedding) VALUES 
('Apple', '과일 사과입니다.', '[1.0, 2.0, 3.0]'),
('Banana', '노란색 과일 바나나.', '[1.2, 2.1, 3.2]'),
('Computer', '전자기기 컴퓨터.', '[9.0, 8.0, 7.0]'),
('Laptop', '휴대용 노트북.', '[9.1, 8.2, 7.1]');


-- [샘플 예제 4: 유클리디안 거리 (Euclidean Distance: <-> 연산자) 측정]
-- "사과[1.0, 2.0, 3.0] 랑 기하학적 직선 거리가 가장 가까운 게 뭐야?" (KNN 검색)
-- => 바나나가 1등으로 가장 거리가 가깝게(수치가 작을수록 비슷함) 노출됩니다.
SELECT item_name, 
       embedding <-> '[1.0, 2.0, 3.0]' AS euclidean_dist 
FROM toy_vectors
ORDER BY euclidean_dist ASC;


-- [샘플 예제 5: 코사인 거리 (Cosine Distance: <=> 연산자) 측정]
-- 텍스트나 문장(NLP)의 유사도를 판별할 때 AI에서 가장 신뢰받는 "두 점 사이의 각도 차이" 연산입니다.
-- (코사인 유사도는 1일수록 똑같고 0이면 다름이나, DB의 거리는 작을수록=0에 가까울수록 동일함을 뜻합니다.)
SELECT item_name, 
       embedding <=> '[9.0, 8.0, 7.0]' AS cosine_dist 
FROM toy_vectors
ORDER BY cosine_dist ASC; 


-- [샘플 예제 6: 내적 거리 (Inner Product: <#> 연산자) 측정]
-- 두 벡터의 성분을 일일이 곱해서 합산하는 방식. (pgvector 에서는 거리 연산 통일을 위해 마이너스(-)를 곱해서 리턴합니다.)
SELECT item_name, 
       embedding <#> '[9.0, 8.0, 7.0]' AS inner_product_dist 
FROM toy_vectors
ORDER BY inner_product_dist ASC;


-- [샘플 예제 7: 특정 거리 이내(반경)에 있는 데이터만 걸러내기]
-- "사과[1.0, 2.0, 3.0] 와 코사인 거리가 0.1 이내로 엄청 비슷한 놈들만 가져와!"
SELECT item_name, embedding <=> '[1.0, 2.0, 3.0]' AS dist
FROM toy_vectors
WHERE (embedding <=> '[1.0, 2.0, 3.0]') < 0.1;


-- [샘플 대용량 셋팅 준비: 1536 차원의 거대한 AI 테이블 껍데기 구경하기]
-- 실제 OpenAI의 text-embedding 시리즈나 오픈소스 모델이 뱉어내는 규격입니다.
CREATE TEMP TABLE ai_documents (
    doc_id SERIAL PRIMARY KEY,
    file_name VARCHAR(100),
    content TEXT,
    embedding VECTOR(1536) -- 무려 1536개의 실수가 들어갈 거대 배열 선언
);


-- [샘플 예제 8: 차원 수가 안 맞을 때의 에러 관찰]
-- 1536 차원을 받겠다고 한 테이블에 3차원 데이터를 넣으면 "vector dimensions (3) and (1536) do not match" 에러 튕김.
-- INSERT INTO ai_documents (file_name, embedding) VALUES ('에러테스트', '[1.0, 2.0, 3.0]');


-- [샘플 예제 9: AVG() 집계 함수를 이용한 "여러 벡터들의 한가운데 중심점" 구하기]
-- 사과와 바나나 좌표의 평균 좌표점(Centroid)을 구합니다. (클러스터링 알고리즘의 뼈대)
SELECT AVG(embedding) as centroid_vector 
FROM toy_vectors 
WHERE item_name IN ('Apple', 'Banana');


-- [샘플 예제 10: 내가 원하는 K개의 비슷한 놈 찾기 (K-Nearest Neighbors 최종 형태)]
-- 실무 RAG(Retrieval-Augmented Generation) 쿼리의 가장 전형적인 모습입니다. LIMIT 이 곧 'K'가 됩니다.
SELECT item_name, description
FROM toy_vectors
ORDER BY embedding <=> '[9.1, 8.0, 7.5]' -- (사용자의 질문 프롬프트를 임베딩한 벡터값)
LIMIT 2; -- 나와 가장 코사인 각도/거리가 비슷한 상위 2개의 문서(문맥)를 즉시 뽑아냄!

-- =========================================================================
-- [조언] 데이터가 10만 건 미만일 때는 위와 같은 Sequential Scan (풀스캔) 기반의 거리 정렬도
-- 아주 빠르게 동작하지만, 데이터가 100만 건, 1000만 건이 넘어가면 모든 거리를 다 연산하다가 DB가 뻗습니다.
-- 다음 장에서 배울 IVFFlat 이나 HNSW 같은 '근사 최인접(ANN)' 인덱싱이 반드시 필요한 이유입니다.
-- =========================================================================
