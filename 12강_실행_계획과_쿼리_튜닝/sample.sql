-- =========================================================================
-- [12강] 실행 계획과 쿼리 튜닝 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 성능(EXPLAIN) 테스트를 위한 임의 대량 레코드와 인덱스 셋팅)
CREATE TEMP TABLE user_logs (
    log_id INT PRIMARY KEY,
    user_email VARCHAR(100),
    action VARCHAR(50),
    amount NUMERIC,
    created_at TIMESTAMP
);

-- GENERATE_SERIES 함수로 1만건의 더미 데이터를 빠르게 벌크업 삽입
INSERT INTO user_logs (log_id, user_email, action, amount, created_at)
SELECT 
    i, 
    'user' || (i % 500) || '@test.com', 
    CASE WHEN i % 3 = 0 THEN 'LOGIN' ELSE 'PURCHASE' END,
    (RANDOM() * 1000)::NUMERIC,
    NOW() - (i || ' minutes')::INTERVAL
FROM generate_series(1, 10000) AS s(i);

-- 튜닝의 핵심인 최신 통계(Statistics) 정보 업데이트 (옵티마이저가 상황을 판단하게 뇌 초기화)
ANALYZE user_logs;


-- [샘플 예제 1: 인덱스가 걸리지 않은 컬럼 검색 - 강제 풀 스캔 방식의 이해 (Seq Scan)]
-- action 에는 인덱스가 없으므로 옵티마이저는 1만 건을 다 훑어서 찾는 최악의 시퀀셜 스캔을 계획합니다.
EXPLAIN 
SELECT * FROM user_logs WHERE action = 'LOGIN';


-- [샘플 예제 2: Primary Key 사용 시 극단적 효율 스캔 (Index Scan)]
-- log_id 는 만들어질 때 강제로 B-Tree 인덱스가 생겼으므로, 옵티마이저가 콕 집어서(1개의 행) 초고속으로 접근합니다.
EXPLAIN ANALYZE 
SELECT * FROM user_logs WHERE log_id = 5555;


-- [샘플 예제 3: 테이블(Heap) 본진으로 안가고 인덱스 책갈피 자체에서 쇼부치기 (Index Only Scan)]
-- pk만 조회하면, 인덱스 테이블 안에 이미 들어있는 정보(`log_id`)이므로, 실제 저장 파일(디스크)에 가는 I/O마저 줄입니다.
EXPLAIN ANALYZE 
SELECT log_id FROM user_logs WHERE log_id = 9000;


-- [샘플 예제 4: LIKE 중간 검색 시 인덱스 파괴 확인 (Seq Scan)]
-- `%user` 처럼 중간 글자를 찾으면, 책의 목차(a~z순)를 못 쓰게 되어서 몽땅 뒤지는 참사가 벌어집니다.
EXPLAIN
SELECT * FROM user_logs WHERE user_email LIKE '%user100@%';


-- [샘플 예제 5: LIKE 전방 일치 검색 (Index 가능)]
-- `user100%` 처럼 앞글자가 똑같다면 B-Tree 인덱스를 탈 수 있는 여지가 남습니다. (단, 문자 콜레이션 설정 체크 필요)
-- (실제로 타려면 btree 인덱스 생성 시 varchar_pattern_ops 옵션 추가가 필요할 수 있음)
CREATE INDEX idx_user_logs_email ON user_logs (user_email varchar_pattern_ops);
EXPLAIN SELECT * FROM user_logs WHERE user_email LIKE 'user100%';


-- [샘플 예제 6: 함수 씌우기에 의한 인덱스 붕괴 현상]
-- 원본 데이터 컬럼(`created_at`)을 날짜 빼기(`DATE()`) 함수로 가공해버리면 인덱스는 셧다운됩니다. 
-- 좌측 가공 금지는 SQL 튜닝의 1원칙입니다.
EXPLAIN 
SELECT * FROM user_logs WHERE DATE(created_at) = '2023-11-01';


-- [샘플 예제 7: 우항으로 넘겨서 수식을 만들어 인덱스를 보호한 튜닝]
-- 원본 컬럼 `created_at` 을 냅두고, 기간 범위 (`>=` 와 `<`) 형태로 던져주면 무사히 Index Range Scan을 타게 됩니다.
CREATE INDEX idx_user_logs_created_at ON user_logs (created_at);
EXPLAIN 
SELECT * FROM user_logs 
WHERE created_at >= '2023-11-01 00:00:00' 
  AND created_at <  '2023-11-02 00:00:00';


-- [샘플 예제 8: ORDER BY 정렬로 인한 거대한 비용 (Sort)]
-- 정렬할 때 메모리가 모자라면 디스크(hdd/ssd) 영역에 꺼내서 정렬하는 무거운 오버헤드가 발생("Sort Method" 확인).
EXPLAIN ANALYZE 
SELECT * FROM user_logs ORDER BY amount DESC;


-- [샘플 예제 9: 인덱스를 통한 정렬(Sort) 생략 초고속 튜닝]
-- 정렬하려는 컬럼에 인덱스를 선언해주면 트리에 `이미 정렬이 된 채로` 들어있기 때문에 (LIMIT 스캔으로 끝).
CREATE INDEX idx_user_logs_amount DESC ON user_logs (amount);
EXPLAIN ANALYZE 
SELECT * FROM user_logs ORDER BY amount DESC LIMIT 10;


-- [샘플 예제 10: BUFFERS 옵션으로 메모리 캐시 적중(Hit) 파악]
-- 실행 시간뿐 아니라 이 쿼리를 처리하기 위해 물리 램 버퍼를 얼마나 읽었는지 블록 통계(Buffers: shared hit)를 자세히 띄웁니다.
EXPLAIN (ANALYZE, BUFFERS) 
SELECT log_id, amount FROM user_logs WHERE amount > 500;

-- =========================================================================
-- [조언] 튜닝의 비결은 EXPLAIN 결과 중 가장 코스트(Cost="..")가 크고, 
-- 루프 바퀴수(Loops="..")가 수백/수천 번 도는 악성 노드를 찾아 그 컬럼에 
-- 인덱스를 입혀주거나 JOIN 방식을 바꾸는 것입니다.
-- =========================================================================
