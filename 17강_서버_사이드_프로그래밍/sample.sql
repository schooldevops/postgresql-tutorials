-- =========================================================================
-- [17강] 서버 사이드 프로그래밍 (PL/pgSQL) - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 함수와 트리거를 걸어볼 임시 회원 및 감사 로깅용 로그 테이블들)
CREATE TEMP TABLE user_accounts (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    balance NUMERIC(10,2) DEFAULT 0.00
);

CREATE TEMP TABLE audit_logs (
    log_id SERIAL PRIMARY KEY,
    changed_table VARCHAR(50),
    action VARCHAR(20),
    record_id INT,
    old_data TEXT,
    new_data TEXT,
    logged_at TIMESTAMP DEFAULT NOW()
);


-- [샘플 예제 1: 단순 상수 변환 헬퍼(Helper) 함수 기초]
-- 애플리케이션 등에서 회원 포인트를 계산할 때 1.05배 곱하기 로직을 DB 공용 모듈로 맞춥니다.
CREATE OR REPLACE FUNCTION calc_bonus_points(base_amount NUMERIC)
RETURNS NUMERIC AS $$ 
BEGIN
    RETURN ROUND(base_amount * 1.05, 2);
END;
$$ LANGUAGE plpgsql;
-- 사용: SELECT calc_bonus_points(100); -- 105.00 반환


-- [샘플 예제 2: 변수(DECLARE)와 분기문(IF-ELSIF-ELSE)이 가득한 비즈니스 로직 함수]
-- 잔고에 따라 VIP 등급 문자열(Silver/Gold/Platinum)을 계산하여 반환해 내는 자바 메서드 같은 친구입니다.
CREATE OR REPLACE FUNCTION get_user_tier(balance NUMERIC)
RETURNS VARCHAR AS $$
DECLARE
    tier VARCHAR(20);
BEGIN
    IF balance >= 10000 THEN tier := 'Platinum';
    ELSIF balance >= 5000 THEN tier := 'Gold';
    ELSE tier := 'Silver';
    END IF;
    RETURN tier;
END;
$$ LANGUAGE plpgsql;
-- 사용: SELECT username, get_user_tier(balance) FROM user_accounts;


-- [샘플 예제 3: 쿼리 결과를 변수에 집어넣는 SELECT INTO]
-- 함수의 내부에서 다른 테이블을 `SELECT` 하여, 나온 단일값 결과를 내장 변수(v_total)에 밀어 넣습니다.
CREATE OR REPLACE FUNCTION get_total_bank_balance()
RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC;
BEGIN
    SELECT SUM(balance) INTO v_total FROM user_accounts;
    -- 값이 없는 경우를 대비해 COALESCE 같은 NULL 방어 코딩을 하는 것이 현명함
    RETURN COALESCE(v_total, 0.00);
END;
$$ LANGUAGE plpgsql;


-- [샘플 예제 4: 여러 줄을 반환하는(테이블 흉내) 셋(SET) 리턴 함수 - RETURNS TABLE]
-- 단일값이 아니라 검색된 결과 묶음(Result Set)을 테이블 컬럼 구조체로 와르르 쏟아내는 강력한 뷰 대용 함수입니다.
CREATE OR REPLACE FUNCTION func_search_rich_users(min_balance NUMERIC)
RETURNS TABLE (u_id INT, u_name VARCHAR, u_tier VARCHAR) AS $$
BEGIN
    RETURN QUERY 
        SELECT user_id, username, get_user_tier(balance) 
        FROM user_accounts 
        WHERE balance >= min_balance;
END;
$$ LANGUAGE plpgsql;
-- 사용: SELECT * FROM func_search_rich_users(5000); (※ 괄호 안 인자가 동적으로 들어가는 뷰 역할)


-- [샘플 예제 5: 이름 없고 재사용 못하는 일회용 특공대 스크립트 (DO 블록)]
-- 굳이 저장 함수를 만들지 않고 쉘 스크립트 1번 쓱 밀어넣듯 DB 콘솔에서 즉석으로 1번만 도는 루프/조건 스크립트입니다.
DO $$
DECLARE
    total_cnt INT;
BEGIN
    SELECT COUNT(*) INTO total_cnt FROM user_accounts;
    RAISE NOTICE '현재 전 회원의 수는 % 명입니다. 배치 작업을 시작합니다.', total_cnt;
    -- (여기에 UPDATE 등의 마이그레이션 배치 스크립트 작성)
END;
$$;


-- [샘플 예제 6: 에러를 나게 하여 입력을 거부하는 함수 기초 (RAISE EXCEPTION)]
-- 잘못된 데이터가 들어오면 프로그램 자체를 터뜨리고 롤백시킵니다. (이 함수를 트리거로 연결할 겁니다.)
CREATE OR REPLACE FUNCTION trg_check_negative_balance() 
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.balance < 0 THEN
        RAISE EXCEPTION '잔고는 마이너스(율)가 될 수 없습니다! 현재 전달된 값: %', NEW.balance;
    END IF;
    -- 통과 시에는 수정/삽입된 행(NEW) 그대로를 돌려주면 정상 반입됩니다.
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- [샘플 예제 7: 위 함수를 삽입/업데이트 동작 "직전(BEFORE)" 에 터지게 연결하는 트리거(Trigger)]
CREATE TRIGGER before_user_balance_change
BEFORE INSERT OR UPDATE ON user_accounts
FOR EACH ROW EXECUTE FUNCTION trg_check_negative_balance();
-- (이제 INSERT INTO ... VALUES ('Hack', -50) 같은 것을 치면 삽입 직전에 DB 단에서 에러 띄우고 차단됩니다)


-- [샘플 예제 8: 데이터가 "바뀐 직후(AFTER)" 백그라운드 몰래 감사(Audit) 로그 찍어주기 설계]
CREATE OR REPLACE FUNCTION trg_audit_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_logs (changed_table, action, record_id, new_data) 
        VALUES ('user_accounts', 'INSERT', NEW.user_id, NEW.username);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        -- 옛날 정보(OLD)와 바뀐 새로운 정보(NEW)를 비교하여 저장
        INSERT INTO audit_logs (changed_table, action, record_id, old_data, new_data) 
        VALUES ('user_accounts', 'UPDATE', OLD.user_id, OLD.balance::TEXT, NEW.balance::TEXT);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_logs (changed_table, action, record_id, old_data) 
        VALUES ('user_accounts', 'DELETE', OLD.user_id, OLD.username);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [샘플 예제 9: 위 감사 함수를 "모든 입력(INSERT, UPDATE, DELETE) 직후" 에 보초 서게 트리거 달기]
CREATE TRIGGER after_user_audit_trg
AFTER INSERT OR UPDATE OR DELETE ON user_accounts
FOR EACH ROW EXECUTE FUNCTION trg_audit_user_changes();


-- [샘플 예제 10: 내부 트랜잭션 수동 제어가 가능한 진짜배기 프로시저 (PROCEDURE) - v11 이후]
-- 함수(FUNCTION) 안에서는 자기가 맘대로 BEGIN/COMMIT을 하거나 에러를 롤백할 수 없습니다(호출한 부모 트랜잭션에 종속되므로).
-- 하지만 "프로시저" 는 자신만의 방에서 COMMIT을 수천 번 제어하는 배치 작업 튜닝의 슈퍼 파워를 갖습니다.
CREATE OR REPLACE PROCEDURE prc_monthly_interest_batch()
LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM user_accounts WHERE balance > 0 LOOP
        UPDATE user_accounts SET balance = balance * 1.01 WHERE user_id = r.user_id;
        COMMIT; -- 1만 줄을 업데이트 할 때마다 계속 조금씩 확정 지으며 나아가서 I/O 메모리 초과를 방지합니다.
    END LOOP;
END;
$$;
-- 호출할 땐 SELECT 가 아니라 CALL 명령어를 사용합니다: CALL prc_monthly_interest_batch();

-- =========================================================================
-- [조언] 프로시저 안에 수만 건 루프를 돌며 타 테이블을 찌르는 동적 다형 로직은 강력하지만,
-- SQL의 꽃인 집합 연산(Set Theory)의 힘을 포기하고 자바처럼 Loop 돌며 느려지는 폐단이 생기므로 남용을 금물입니다.
-- =========================================================================
