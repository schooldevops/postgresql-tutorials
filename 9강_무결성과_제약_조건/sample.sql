-- =========================================================================
-- [9강] 무결성과 제약 조건 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 제약 조건 테스트를 위한 상하위 임시 테이블 선언)
CREATE TEMP TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    age INT
);

-- [샘플 예제 1: NOT NULL 제약 조건 부여]
-- 이메일(email) 열은 절대로 비워둘 수 없는 필수 값이라고 선언하여, 누락 사고를 방지합니다.
ALTER TABLE users ADD COLUMN email VARCHAR(100) NOT NULL DEFAULT 'unknown@example.com';


-- [샘플 예제 2: CHECK 제약 조건: 특정 수치 범위 논리 검사]
-- 나이(age)는 반드시 음수가 올 수 없다고 제한합니다. (개발자 실수 등 방어 목적)
ALTER TABLE users ADD CONSTRAINT chk_user_age CHECK (age >= 0);


-- [샘플 예제 3: CHECK 제약 조건: 허용 문자열만 입력토록 도메인 관리]
-- 사용자 권한 열(role)에 정해진 글자인 'ADMIN', 'USER' 외의 다른 오타 값이 삽입되는 것을 막아버립니다. 
ALTER TABLE users ADD COLUMN role VARCHAR(10) DEFAULT 'USER' 
                 CHECK (role IN ('ADMIN', 'USER', 'GUEST'));


-- [샘플 예제 4: 두 개의 컬럼을 혼합한 복합 고유키(UNIQUE) 생성]
-- 회원은 한 번호(phone)와, 같은 주소(address) 두 개가 동시에 동일한 걸 또 생성할 수 없게 만듭니다. (다중 로그인 어뷰징 차단)
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN address VARCHAR(100);
ALTER TABLE users ADD CONSTRAINT uk_phone_addr UNIQUE (phone, address);


-- [샘플 예제 5: 외래키(FOREIGN KEY)를 통한 참조 무결성 연결 및 ON DELETE CASCADE 옵션]
-- user 테이블에 존재하지 않는 허위 user_id가 이 리뷰 테이블에 들어오는 것을 처음부터 봉쇄합니다. 
-- 추가로 상위 부모인 users의 레코드가 지워지면 달려있던 자식 리뷰들도 깔끔하게 연쇄 파괴(CASCADE)됩니다.
CREATE TEMP TABLE user_logs (
    log_id SERIAL PRIMARY KEY,
    user_id INT,  
    action_type VARCHAR(50),
    CONSTRAINT fk_log_user 
      FOREIGN KEY (user_id) 
      REFERENCES users(user_id) ON DELETE CASCADE
);


-- [샘플 예제 6: ON DELETE SET NULL - 삭제 시 빈 값 처리 보존]
-- 게시판을 만들 때 부모 데이터(회원 탈퇴 등)가 지워져도, 이 사용자가 썼던 게시물의 흔적은 보존합니다. (탈퇴한 회원입니다 처리)
CREATE TEMP TABLE board_posts (
    post_id SERIAL PRIMARY KEY,
    author_id INT,
    title VARCHAR(200),
    CONSTRAINT fk_post_author 
      FOREIGN KEY (author_id) 
      REFERENCES users(user_id) ON DELETE SET NULL
);


-- [샘플 예제 7: 위반 사례 테스트 (ERROR 발생 구간)]
-- 아래 주석 처리된 구문들은 각 제약 조건을 위반하므로 곧바로 Postgres 엔진 레벨에서 강제로 거부(에러)됩니다.
-- INSERT INTO users (username, age) VALUES ('admin', -5); -- chk_user_age 위반!
-- INSERT INTO user_logs (user_id) VALUES (9999); -- fk_log_user 외래키 위반!
-- INSERT INTO users (username) VALUES ('test_user'), ('test_user'); -- username UNIQUE 위반!


-- [샘플 예제 8: 걸려있는 기존 제약조건 이름 변경시키기 (RENAME)]
-- 임의로 들어간 제약 조건의 이름을 팀 컨벤션에 맞추어 `uk_phone_addr` 에서 `uk_users_contact`로 바꿉니다.
ALTER TABLE users 
RENAME CONSTRAINT uk_phone_addr TO uk_users_contact;


-- [샘플 예제 9: 특정 제약조건 삭제(DROP)하기]
-- 기존에 0살 이상만 가입을 막았던 체크 부분을, 정책 변경으로 지워버립니다. (제약조건 이름을 미리 지어뒀기에 관리가 편합니다.)
ALTER TABLE users 
DROP CONSTRAINT chk_user_age;


-- [샘플 예제 10: NOT VALID 로 무중단 서비스 락 없이 제약조건 추가하기]
-- 매우 용량이 큰 테이블에 수억 건 데이터가 있을 경우, 과거 이력 검사는 보류하고 신규 데이터들만 체킹하는 'NOT VALID' 구문을 사용하여, 장애(Table Lock)를 우회합니다.
ALTER TABLE user_logs 
ADD CONSTRAINT chk_action_length CHECK (LENGTH(action_type) > 2) NOT VALID;

-- 기존 레거시 데이터는 나중에 시간 날 때 천천히 별도로 점검합니다.
ALTER TABLE user_logs 
VALIDATE CONSTRAINT chk_action_length;

-- =========================================================================
-- [조언] 과도한 제약조건(특히 FOREIGN KEY)은 애플리케이션의 유연성을 떨어뜨리고, 
-- DML(INSERT, UPDATE) 속도를 갉아먹는 주 원인이 되므로 서비스 요구사항을 보고 트레이드오프를 따릅니다.
-- =========================================================================
