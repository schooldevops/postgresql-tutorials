-- =========================================================================
-- [15강] 동시성 제어와 격리 수준 - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 다수의 사용자가 동시에 데이터를 읽고 쓸 때 발생할 수 있는 데이터 정합성 문제와, 
-- 격리 수준(Isolation Level), 명시적 행 잠금(Row-level Lock)으로 이를 어떻게 제어하는지 보여주는 실습입니다.

-- (사전 준비: 테스트용 은행 계좌(accounts)와 이벤트 쿠폰(coupons) 테이블 생성)
CREATE TEMP TABLE accounts (
    acc_id SERIAL PRIMARY KEY,
    owner VARCHAR(50) NOT NULL,
    balance NUMERIC(10,2) CHECK (balance >= 0)
);

CREATE TEMP TABLE coupons (
    coupon_id SERIAL PRIMARY KEY,
    status VARCHAR(20) DEFAULT 'AVAILABLE',
    claimed_by VARCHAR(50)
);

INSERT INTO accounts (owner, balance) VALUES ('Alice', 10000.00), ('Bob', 5000.00);

INSERT INTO coupons (status) VALUES ('AVAILABLE'), ('AVAILABLE'), ('AVAILABLE');


-- [샘플 예제 1: 단순 SELECT는 읽기 자물쇠(Shared Lock)를 무시함 (MVCC 특성)]
-- (만약 세션 1이 Alice의 돈을 건드리고(UPDATE) 아직 COMMIT하기 전, 세션 2가 읽으려고 하면?)
-- => 대기(Wait) 현상 없이 즉시 과거의 변경 전 원본 버전을(10000.00) 읽어냅니다 (동시성 극대화).
SELECT balance FROM accounts WHERE owner = 'Alice';


-- [샘플 예제 2: 쓰기 충돌 회피 (Pessimistic Locking - 배타적 락 FOR UPDATE)]
-- 누군가 Alice의 돈을 뽑아 갈 거라면, 내 작업이 완전히 끝날 때까지 남들이 아예 손도 대지 못하게 자물쇠를 겁니다.
BEGIN;
SELECT balance FROM accounts WHERE owner = 'Alice' FOR UPDATE;
-- (이제 이 트랜잭션이 끝나기 전까진, 남들이 이 줄에 "FOR UPDATE"나 "UPDATE"를 날리면 멈춰서 기다리게 됨)
UPDATE accounts SET balance = balance - 1000 WHERE owner = 'Alice';
COMMIT;


-- [샘플 예제 3: 락 대기 시간 없애고 에러로 튕겨내기 (NOWAIT)]
-- 이미 남이 선점해서 잠긴 데이터를 터치했을 때, 영원히 멈추는 걸 피하고 곧바로 애플리케이션에 예외(Error)를 보냅니다.
BEGIN;
-- 다른 트랜잭션이 락을 쥐고 있다면 바로 "ERROR: could not obtain lock" 발생 후 즉시 롤백됨
SELECT * FROM accounts WHERE owner = 'Bob' FOR UPDATE NOWAIT;
COMMIT;


-- [샘플 예제 4: 선점된 건 쿨하게 건너뛰고 빈 것만 날름 가져오기 (SKIP LOCKED)]
-- 수십 명이 동시에 덤벼드는 콘서트 티켓팅, 쿠폰 선착순 발급 등에 쓰이는 락의 궁극기입니다.
BEGIN;
UPDATE coupons 
SET status = 'CLAIMED', claimed_by = 'User1'
WHERE coupon_id = (
    SELECT coupon_id FROM coupons 
    WHERE status = 'AVAILABLE' 
    LIMIT 1 FOR UPDATE SKIP LOCKED
)
RETURNING coupon_id; -- 내가 발급받은 쿠폰 번호를 반환
COMMIT;


-- [샘플 예제 5: 조회는 허락하지만 변경은 막는 공유 락 (FOR SHARE)]
-- "난 이 데이터를 읽고서 뭔가 대조만 할 거니까 다른 사람도 와서 자유롭게 '읽어도' 되지만, 
-- 내가 끝날 때까지 누구도 '수정'은 하지 마!" 라는 조건입니다. (외래키 무결성 검증 시 내부적으로 사용됨)
BEGIN;
SELECT * FROM accounts WHERE owner = 'Alice' FOR SHARE;
-- (다른 조회는 안 막히지만, 누군가 UPDATE 하려 들면 대기 탐)
COMMIT;


-- [샘플 예제 6: Non-Repeatable Read 오류 (기본: READ COMMITTED 모드)]
-- 여러 개의 값을 대조하는데, 시간이 걸려서 남이 중간에 끼어들어 데이터를 바꾼 걸 커밋하면 내 뷰가 돌변하는 현상.
BEGIN; -- BEGIN 수행 직후 (기본 격리 모드)
SELECT balance FROM accounts WHERE owner = 'Bob'; -- 5000 
-- (수 초 뒤, 이 사이 남이 Bob의 잔고를 1000으로 바꾸고 커밋해버림)
SELECT balance FROM accounts WHERE owner = 'Bob'; -- 1000 으로 내 트랜잭션 도중 값이 휙휙 바뀜
COMMIT;


-- [샘플 예제 7: Repeatable Read 격리 수준 (내가 처음 본 세상 유지)]
-- 트랜잭션 도중 "남이 데이터를 바꿔도 나에게는 보이지 않게" 일관된 스냅샷(과거 사진)만 봅니다.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM accounts WHERE owner = 'Bob'; -- 5000 
-- (수 초 뒤, 이 사이 남이 Bob의 잔고를 1000으로 바꾸고 커밋해버림)
SELECT balance FROM accounts WHERE owner = 'Bob'; -- 여전히 나에겐 5000 으로 보장됨! (정합성)
COMMIT;


-- [샘플 예제 8: 트랜잭션 무결성의 정점 (SERIALIZABLE 격리 수준)]
-- 병렬 처리가 난무해도 마치 "한 줄로 차례차례" 실행한 것과 동일무결한 결과만 허용하는 가장 빡빡한 단계입니다.
-- (조금이라도 양쪽이 동시에 값을 바꿔 계산에 충돌이 나면 한쪽 트랜잭션을 에러 내면서 바로 폭파시켜버림)
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- (계산 및 변경 로직수행)
COMMIT;


-- [샘플 예제 9: MVCC 에서 쌓인 빈 껍데기 시체들 확인하기 (pg_stat_user_tables)]
-- 잦은 UPDATE 나 DELETE 이후에는 사실 데이터가 지워지지 않고 빈 파일 파편(Dead Tuple)이 쌓여 조회 성능이 떨어집니다.
SELECT n_live_tup AS 살아있는_개수, 
       n_dead_tup AS 유령_데이터_개수
FROM pg_stat_user_tables 
WHERE relname = 'accounts'; 


-- [샘플 예제 10: 강제 데드 튜플 청소 (Manual VACUUM)]
-- 모니터링 툴(Datadog 등)에서 위 쿼리의 유령(Dead Tuple)이 너무 많다고 알림이 오면 물리적 공간을 즉시 초기화/수거해냅니다.
-- 매일 밤 배치 스케줄러로 돌려주는 것이 가장 바람직한 운영 포인트.
VACUUM ANALYZE accounts; 

-- =========================================================================
-- [조언] FOR UPDATE 자물쇠를 걸 때 LIMIT 를 꼭 주고, 서브 쿼리 등 복잡한 연결 구문에 걸지 마세요! 
-- 자칫하면 테이블 수백만 건 전체에 락이 걸리며 서비스 DB 전체가 뻗습니다.
-- =========================================================================
