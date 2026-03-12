-- =========================================================================
-- [24강] pgvector 인덱스 최적화 (IVFFlat & HNSW) - 실전 샘플 쿼리 10선
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- [사전 준비] 인덱스 생성을 증명하기 위한 다량의 목업 구조 테이블 (1000 차원)
CREATE TEMP TABLE vector_logs (
    log_id SERIAL PRIMARY KEY,
    memo TEXT,
    embedding VECTOR(100)
);


-- [샘플 예제 1: HNSW 인덱스 생성 기본형 (L2 유클리디안 거리 전용)]
-- HNSW는 테이블이 비어져 있을 때 인덱스를 먼저 걸어놓아도 데이터가 들어올 때마다 알아서 그물을 이쁘게 짭니다.
-- vector_l2_ops 는 <-> 연산자를 만났을 때 반응하라는 규칙입니다.
CREATE INDEX idx_vector_logs_hnsw_l2 
ON vector_logs USING hnsw (embedding vector_l2_ops);


-- [샘플 예제 2: HNSW 인덱스의 고급 세부 튜닝 파라미터 개입]
-- m: 하나의 데이터 점(노드)에서 연결선을 몇 가닥(edge)이나 뻗을 것인가 (기본값 16)
-- ef_construction: 처음 건물을 지을 때 얼마나 주변을 샅샅이 뒤져 연결망을 구축할 것인가 (기본값 64)
-- 두 수치를 올리면 램과 인덱스가 뚱뚱해지지만 검색의 신뢰도(Recall)가 최고조에 달합니다.
CREATE INDEX idx_vector_logs_hnsw_advanced 
ON vector_logs USING hnsw (embedding vector_cosine_ops)
WITH (m = 24, ef_construction = 100);


-- [샘플 예제 3: IVFFlat 인덱스 생성 기본형 (Inner Product 전용)]
-- 테이블 안의 데이터를 N가구씩 묶는 방식. (주의: 테이블이 텅 비어있을 땐 절대로 파면 안됩니다)
CREATE INDEX idx_vector_logs_ivfflat_ip 
ON vector_logs USING ivfflat (embedding vector_ip_ops)
WITH (lists = 100); -- 전체 데이터를 100 덩어리로 잘라 관리하겠단 의미


-- [샘플 예제 4: HNSW 검색 런타임 성능 향상을 우한 탐색 스위프 조절]
-- 쿼리(SELECT)를 때릴 때, 그물망을 이웃 노드로 몇 번이나 타고 들어갈지 범위를 지시합니다.
-- 무겁게 검색해서 무조건 정답을 찾아야 하면 200, 대충 빨리 보여만 주려면 10 으로 검색 전 세팅.
SET hnsw.ef_search = 100;

SELECT memo FROM vector_logs 
ORDER BY embedding <=> (SELECT embedding FROM ai_model_mock_call LIMIT 1)
LIMIT 5;


-- [샘플 예제 5: IVFFlat 의 Probes 조정으로 구석에 걸친 정답 캐내기]
-- 군집 100개 중 1개만 찔러보던 것을, 인접한 주변 군집까지 5개를 다 찔러보도록 시야를 넓혀 재현률을 올립니다.
SET ivfflat.probes = 5;

SELECT memo FROM vector_logs 
ORDER BY embedding <#> (SELECT embedding FROM ai_model_mock_call LIMIT 1)
LIMIT 5;


-- [샘플 예제 6: 미스매치(Miss Match)에 의한 인덱스 스캔 실패 현상 방어하기]
-- 인덱스는 Cosine 전용(vector_cosine_ops) 으로 파놓고 정작 검색 명령은 L2 거리(<->)로 때리는 최악의 실수
EXPLAIN 
SELECT memo FROM vector_logs 
ORDER BY embedding <-> '[0.1, 0.2]' 
LIMIT 5;
-- 플랜을 까보면 인덱스를 깔끔히 무시하고 Seq Scan(풀스캔) 밑바닥 노가다를 뛰고 있음을 증명합니다.


-- [샘플 예제 7: 올바르게 아귀가 맞은 퍼펙트 인덱스 스캔 플랜 증명]
-- 코사인 인덱스가 살아있는 테이블에서 <=> 오퍼레이터를 정확히 타깃팅하여 호출하면 벌어지는 마법.
EXPLAIN 
SELECT memo FROM vector_logs 
ORDER BY embedding <=> '[0.1, 0.2]' 
LIMIT 5;
-- 플랜 노드 맨 윗줄에 "Index Scan using idx_vector_logs_hnsw_advanced" 문구가 위풍당당하게 뜹니다 (소요시간 1ms 이하).


-- [샘플 예제 8: 인덱싱 생성을 초가속하는 서버 파라미터 단기 부스트 부여]
-- HNSW 생성 명령을 치기 직전에, 이 터미널(Session)에 한하여 램(RAM) 자원을 4GB로 폭발적으로 늘려줍니다.
SET maintenance_work_mem = '4GB';
-- CREATE INDEX ... 
-- 완료 후 램 설정은 터미널 종료 혹은 RESET 으로 자연 반납됩니다.


-- [샘플 예제 9: 인덱스의 덩치(Disk Size)와 부풀어오름(Bloat) 확인하기]
-- HNSW 그래프 구조는 일반 B-Tree 인덱스보다 디스크 용량을 꽤 육중하게 차지합니다. 실제 먹고 있는 사이즈 까보기.
SELECT pg_size_pretty(pg_relation_size('idx_vector_logs_hnsw_advanced')) AS index_physical_size;


-- [샘플 예제 10: 반정밀도 16비트(HALFVEC) 인덱싱 결합하기]
-- 앞선 22강에서 본 HALFVEC 컬럼 위에도 당연히 HNSW 최적화 그래프를 결합할 수 있습니다. 
-- 이 때 디스크 점유 용량과 인덱스 스캔 속도(RAM 히트율)는 상상을 초월하게 가벼워집니다.
CREATE TEMP TABLE light_docs (id INT, embedding HALFVEC(100));
CREATE INDEX idx_light_docs_hnsw ON light_docs USING hnsw (embedding halfvec_cosine_ops);

-- =========================================================================
-- [조언] 현재 AI RDBMS 서치 아키텍처의 알파이자 오메가는 "HNSW + Cosine Ops + LIMIT" 체제입니다.
-- IVFFlat 에 비해 인덱스 형성 속도와 삽입 페널티는 크지만, 읽기(Search)의 압도적 재현도와 스루풋이 모든 걸 씹어먹습니다.
-- =========================================================================
