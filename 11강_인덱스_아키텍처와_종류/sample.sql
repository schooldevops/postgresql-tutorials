-- =========================================================================
-- [11강] 인덱스 아키텍처와 종류 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 다양한 데이터 타입이 혼합된 실습용 로깅 시스템 테이블)
CREATE TEMP TABLE user_logs (
    log_id SERIAL PRIMARY KEY,
    user_email VARCHAR(100),
    action VARCHAR(50),      -- 로그인, 로그아웃 등
    payload JSONB,           -- 부가 정보
    location POINT,          -- 접속 위치 (x,y 좌표계)
    created_at TIMESTAMP DEFAULT NOW()
);

-- 대량의 트래픽을 가정하여 더미 데이터 단건 삽입
INSERT INTO user_logs (user_email, action, payload, location) VALUES 
('admin@test.com', 'LOGIN', '{"ip": "192.168.1.1", "device": "mac"}', point(37.5, 127.0)),
('user1@test.com', 'CLICK', '{"button": "buy", "time": 120}', point(35.1, 129.0));


-- [샘플 예제 1: 다중 컬럼(결합) 인덱스 B-Tree]
-- 특정 유저 이메일과 그 유저가 행한 '어떤 행동(action)' 을 쌍으로 자주 묶어서 조회할 일이 많다면, 이 두 개를 한 개의 결합 인덱스로 만듭니다.
-- 주의: 인덱스 컬럼의 순서가 매우 중요하며, 조건절(WHERE)에서 항상 맨 앞에(user_email) 있는 값을 먼저 찔러야 인덱스를 탑니다.
CREATE INDEX idx_user_logs_email_action 
ON user_logs (user_email, action);


-- [샘플 예제 2: Hash 인덱스를 통한 동등(=) 성능의 극대화]
-- 오로지 "action = 'LOGIN'" 같은 1:1 단순 매칭만 일어나는 속성 컬럼엔, B-Tree보다 가벼운 Hash 테이블 방식의 인덱스가 적합합니다. (범위검색 <, > 불가)
CREATE INDEX idx_user_logs_action_hash 
ON user_logs USING HASH (action);


-- [샘플 예제 3: 부분(Partial) 인덱스의 극강의 메모리 아끼기]
-- 전체 데이터 수십억 건 중, '오류(ERROR)' 로 남은 로그들만 집중 모니터링한다면, 굳이 INFO 로그를 다 색인화하지 맙시다.
CREATE INDEX idx_user_logs_errors 
ON user_logs (action) 
WHERE action = 'ERROR';


-- [샘플 예제 4: 함수 변형 무시 - 함수형(Functional) 인덱스]
-- 데이터에는 대문자로 들어갔을지 소문자로 들어갔을지 모를 때, 조회 시 `LOWER(user_email) = '...'` 처럼 변환을 하면 기존 인덱스가 박살납니다. 아예 변형본으로 구워둡니다.
CREATE INDEX idx_user_logs_lower_email 
ON user_logs (LOWER(user_email));


-- [샘플 예제 5: GIN(Generalized Inverted Index) - JSONB 풀스캔 피하기]
-- JSONB 컬럼 안속성(`payload->'device'`) 등 비정형 데이터 내부의 세부 키-값을 검색하려면 GIN (역 인덱스) 사용이 유일무이한 최적화 길입니다.
CREATE INDEX idx_user_logs_payload_gin 
ON user_logs USING GIN (payload);


-- [샘플 예제 6: GiST (Generalized Search Tree) - 공간 데이터 특화]
-- 위치 좌표 검색 (PostGIS 기능)이나 단순 `POINT` 데이터에서 '특정 반경 X 미터 이내 유저 찾기' 등을 할 땐 공간 트리가 필요합니다.
CREATE INDEX idx_user_logs_location_gist 
ON user_logs USING GIST (location);


-- [샘플 예제 7: BRIN (Block Range Index) - 거대 시계열 데이터 한판승]
-- 생성일(`created_at`) 처럼 시간이 흐르며 한 방향으로 계속 늘어나기만 하는 IoT 시계열 데이터(1테라바이트 급)는 수만 개의 덩어리(블록) 최소/최대값만 저장해두면 디스크 용량을 99% 아낄 수 있습니다.
CREATE INDEX idx_user_logs_created_brin 
ON user_logs USING BRIN (created_at);


-- [샘플 예제 8: 온라인 라이브 중단 없는(Lock-Free) 인덱스 추가]
-- 실 사용자가 미친듯이 들어오는 도중에 `CREATE INDEX` 를 때리면 전체 테이블 테이블 락이 걸립니다. `CONCURRENTLY` 옵션을 주면 천천히 뒤에서 백그라운드로 맵핑을 안전하게 완성합니다.
CREATE INDEX CONCURRENTLY idx_user_logs_action_live 
ON user_logs (action);


-- [샘플 예제 9: Index-Only Scan 을 위한 INCLUDE(커버링 인덱스) 지정]
-- `created_at` 으로 날짜를 뒤져서 `user_email` 을 가져와야 할 때, 원본 디스크에 점프 뛰는 비용을 없애기 위해 이메일 값을 인덱스 메모리 자체에 끼워(INCLUDE) 팔아냅니다.
CREATE INDEX idx_user_logs_date_include 
ON user_logs (created_at) INCLUDE (user_email);


-- [샘플 예제 10: 현재 테이블에 걸린 모든 인덱스 상태 뷰어]
-- PostgreSQL 내부 시스템 테이블을 찔러서 현재 내 테이블에 어떤 이름/어떤 방식으로 인덱스가 걸려있는지 목록을 확인합니다.
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'user_logs';

-- =========================================================================
-- [조언] 인덱스 튜닝의 핵심 지표는 "디스크 공간(Memory)" 과 "쓰기 속도(Write)" 를
-- "읽기 성능 향상(Select)" 과 타협(Trade-Off) 하는 고도의 예술 작업입니다.
-- =========================================================================
