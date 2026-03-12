-- =========================================================================
-- [10강] 트랜잭션의 이해 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 트랜잭션 및 금융 계좌 이체를 시뮬레이션할 임시 테이블 생성)
CREATE TEMP TABLE accounts (
    account_id SERIAL PRIMARY KEY,
    owner_name VARCHAR(50) NOT NULL,
    balance NUMERIC(10,2) CHECK (balance >= 0) -- 잔고 마이너스 방지 제약
);

INSERT INTO accounts (owner_name, balance) VALUES 
('Alice', 10000.00),
('Bob', 5000.00),
('Charlie', 2000.00);


-- [샘플 예제 1: 기본 전체 성공 트랜잭션 (COMMIT)]
-- Alice가 Bob에게 3000원을 송금합니다. 두 계좌의 UPDATE가 모두 정상 처리되어야 완수됩니다.
BEGIN;

UPDATE accounts SET balance = balance - 3000 WHERE owner_name = 'Alice';
UPDATE accounts SET balance = balance + 3000 WHERE owner_name = 'Bob';

COMMIT; -- 양쪽 계좌 잔액 확정 반영 (Alice: 7000, Bob: 8000)


-- [샘플 예제 2: 논리적 오류를 감지한 강제 취소 (ROLLBACK)]
-- Bob이 Charlie에게 9000원을 송금하려다 잔액 부족 오류(CHECK 위반)나, 또는 앱 서버의 예외 통보를 받고 이전 상태로 전부 되돌립니다.
BEGIN;

UPDATE accounts SET balance = balance - 9000 WHERE owner_name = 'Bob'; -- 에러 발생 지점!
UPDATE accounts SET balance = balance + 9000 WHERE owner_name = 'Charlie';

ROLLBACK; -- 모든 UPDATE를 백지화 (Bob: 8000, Charlie: 2000 그대로 유지)


-- [샘플 예제 3: 테이블 자체를 지우는 DDL마저 롤백이 가능함 증명]
-- PostgreSQL만의 강력한 기능으로, 운영 테이블을 드랍(삭제)하는 대형 사고를 내도 COMMIT 전에만 살려내면 부활합니다.
BEGIN;
DROP TABLE accounts;
-- (아차! 잘못 지웠다 판단)
ROLLBACK; 
-- SELECT * FROM accounts; 명령이 정상 작동함


-- [샘플 예제 4: SAVEPOINT 를 활용한 긴 호흡의 중간 끊어치기]
-- 여러 작업을 하던 도중 1번과 2번의 DML은 살려두고, 3번째로 가한 삽입만 지워달라고 명시합니다.
BEGIN;

INSERT INTO accounts (owner_name, balance) VALUES ('Dave', 1000.00);
SAVEPOINT insert_dave;

UPDATE accounts SET balance = 0 WHERE owner_name = 'Alice';
-- (Alice의 돈을 0으로 만드는 UPDATE가 잘못되었다면 그 지점(Savepoint)까지만 잘라냅니다.)
ROLLBACK TO insert_dave; 

COMMIT; -- Dave의 INSERT 1건은 살아남음


-- [샘플 예제 5: 트랜잭션 블록 안에서 현재 내 세션만의 데이터 확인하기]
-- 다른 세션(사용자)에게는 아직 COMMIT 안된(보이지 않는) 격리된(Isolation) 나의 수정 사항을 미리 확인합니다.
BEGIN;

UPDATE accounts SET balance = balance + 5000 WHERE owner_name = 'Charlie';
SELECT * FROM accounts WHERE owner_name = 'Charlie'; -- 내 창에서는 7000원(2000+5000) 노출
    
-- (이 타이밍에 다른 창에서 Charlie를 조회하면 여전히 2000원)
COMMIT; -- 이로써 모두에게 7000원으로 영구 노출


-- [샘플 예제 6: 다중행 삽입 시 무거운 I/O 튜닝 비법 (다중 BATCH화)]
-- 트랜잭션을 일일이 열고 닫는 오토커밋(Auto-Commit) 대신, 엄청난 양의 로그를 백그라운드 BEGIN으로 묶어서 단숨에 쏟아냅니다.
BEGIN;
INSERT INTO accounts (owner_name, balance) VALUES ('User1', 100);
INSERT INTO accounts (owner_name, balance) VALUES ('User2', 200);
INSERT INTO accounts (owner_name, balance) VALUES ('User3', 300);
-- (10만번 통신 반복이라 가정)
COMMIT; -- 이 때 디스크에 1번만 가서 저장하므로 엄청나게 빠름


-- [샘플 예제 7: 동시성 처리를 위한 수동 Lock 이 포함된 트랜잭션 (SELECT FOR UPDATE)]
-- Alice의 계좌에 누군가 동시에 접근하여 잔액을 빼가지 못하도록, 내 트랜잭션이 끝날 때까지 레코드에 '강제 자물쇠'를 채웁니다. (비관적 락)
BEGIN;

SELECT balance FROM accounts 
WHERE owner_name = 'Alice' FOR UPDATE; -- 타 세션들은 해당 줄 UPDATE 대기(Wait)

UPDATE accounts SET balance = balance - 100 WHERE owner_name = 'Alice';
COMMIT; -- 잔액 깎은 후 락 해제


-- [샘플 예제 8: 트랜잭션 격리 수준 명시 (Isolation Level 조정)]
-- 기본값인 READ COMMITTED 보다 더 엄격하게, 중간에 다른 사람이 데이터를 변경하더라도 처음 내가 본 스냅샷 상태를 유지(REPEATABLE READ) 하라는 명세입니다.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT SUM(balance) FROM accounts;
COMMIT;


-- [샘플 예제 9: 읽기 전용으로 안전하게 방어하는 트랜잭션 (READ ONLY)]
-- 통계 테이블을 조회할 때 실수로라도 데이터를 조작(UPDATE/DELETE)하지 못하게 방어막(Read Only)을 설정합니다.
BEGIN READ ONLY;
SELECT * FROM accounts;
-- DB 보안을 위해 애플리케이션 접속 계정에 이 옵션을 걸기도 합니다.
COMMIT;


-- [샘플 예제 10: 에러 발생 후 '트랜잭션 중단' 모드가 된 블록 처리법]
-- 한번 쿼리를 삐끗(문법오류 발생 등)하여 블록이 Aborted 상태로 변하면 남은 쿼리들을 더 쓸 수 없다는 점과 무조건 ROLLBACK을 강제해야 함을 시연합니다.
BEGIN;

-- 의도적인 오타나 렉시컬(Lexical) 에러
-- SELECT * FROM dummy_table_not_exist;

-- 위 에러 직후엔 아래와 같은 정상 쿼리를 쳐도 <current transaction is aborted> 라고 하면서 모조리 무시됩니다.
-- SELECT 1;

-- 수동으로 끝을 맺어주어야만 깨진 블록이 풀립니다.
ROLLBACK; 

-- =========================================================================
-- [조언] 애플리케이션의 @Transactional (Spring) 어노테이션 등도 결국 DB로 날아갈 때는
-- 이 BEGIN, COMMIT 의 연결/해제 과정입니다. 블록 안에 긴 API 외부 호출을 섞으면 DB 커넥션 풀이 마르게 됩니다.
-- =========================================================================
