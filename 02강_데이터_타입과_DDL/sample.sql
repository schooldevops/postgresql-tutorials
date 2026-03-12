-- =========================================================================
-- [2강] 데이터 타입과 DDL - 실전 샘플 쿼리 10선
-- =========================================================================

-- [샘플 예제 1: 스키마(Schema) 생성 및 설정]
-- 업무 도메인별로 테이블을 분리 관리하기 위해 새로운 스키마를 생성합니다.
CREATE SCHEMA hr;

-- 현재 작업 중인 세션에서 hr 스키마를 public보다 먼저 검색하도록 경로를 변경합니다.
SET search_path TO hr, public;


-- [샘플 예제 2: 부서 정보를 담는 테이블 생성]
-- 정수, 자동 증가값(SERIAL), 문자열 타입을 사용해 테이블을 구성합니다.
CREATE TABLE departments (
    dept_id SERIAL PRIMARY KEY,    -- SERIAL: 1씩 자동 증가하는 4바이트 정수
    dept_name VARCHAR(100) NOT NULL, -- 길이가 최대 100인 가변 길이 문자. 빈 값을 허용하지 않음
    location TEXT                  -- 길이 제한이 없는 텍스트
);


-- [샘플 예제 3: 직원 정보를 담는 테이블 생성 (다양한 데이터 타입 활용)]
-- 날짜형(DATE), 숫자/화폐형(NUMERIC), 부울형(BOOLEAN) 등을 복합적으로 사용합니다.
CREATE TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50) NOT NULL,
    hire_date DATE DEFAULT CURRENT_DATE, -- DATE: yyyy-mm-dd 형식, 기본값으로 오늘 날짜 지정
    salary NUMERIC(15, 2),               -- NUMERIC: 총 15자리 중 소수점 이하 2자리를 저장하는 고정 소수점 타입 (금액 계산용)
    is_active BOOLEAN DEFAULT true,      -- BOOLEAN: true/false 등 논리형 데이터, 기본값 true
    dept_id INTEGER REFERENCES departments(dept_id) -- INTEGER(4바이트 상수) 타입 사용 및 외래키 지정
);


-- [샘플 예제 4: 기존 테이블에 새로운 컬럼 추가 (ALTER COLUMN)]
-- 직원 테이블에 연락망과 생년월일 컬럼을 새롭게 추가합니다.
ALTER TABLE employees 
ADD COLUMN phone_number TEXT,
ADD COLUMN birth_date DATE;


-- [샘플 예제 5: 기존 데이터 타입 변경하기 (ALTER COLUMN TYPE)]
-- 기존 phone_number 컬럼의 데이터 타입을 TEXT에서 정해진 길이의 VARCHAR(20)으로 변환합니다.
ALTER TABLE employees 
ALTER COLUMN phone_number TYPE VARCHAR(20);


-- [샘플 예제 6: 형변환(USING)을 동반한 데이터 타입 변경]
-- 문자열로 저장되어 있는 '1000' 형태의 보너스 컬럼이 있다고 가정할 때, 이를 숫자로 바꾸는 방식입니다.
-- (임시로 보너스 텍스트 컬럼 생성)
ALTER TABLE employees ADD COLUMN bonus_text TEXT;
-- (문자형 데이터를 숫자형 NUMERIC으로 명시적 형변환(USING) 하여 타입 변경)
ALTER TABLE employees ALTER COLUMN bonus_text TYPE NUMERIC(10,2) USING bonus_text::numeric;


-- [샘플 예제 7: 불필요한 컬럼 삭제]
-- 더 이상 쓰지 않는 bonus_text 컬럼을 삭제합니다.
ALTER TABLE employees 
DROP COLUMN bonus_text;


-- [샘플 예제 8: 테이블 컬럼 이름 변경]
-- is_active 컬럼의 이름을 의미가 더 명확한 status_active 로 변경합니다.
ALTER TABLE employees 
RENAME COLUMN is_active TO status_active;


-- [샘플 예제 9: 테이블 내 전체 데이터 고속 삭제 (TRUNCATE)]
-- 테이블의 뼈대(구조)는 남겨두되 저장된 모든 데이터를 매우 빠른 속도로 날려버립니다.
-- 데이터가 너무 많은 경우 DELETE FROM 대신 사용합니다.
-- ※ 실제 실행 전에 테스트용 더미 테이블을 만들고 실행해보세요.
CREATE TABLE dummy_table (id serial, val text);
TRUNCATE TABLE dummy_table;


-- [샘플 예제 10: 테이블 및 스키마 완전 삭제 (DROP FULL)]
-- 의존성이 있는 하위/연관 객체들까지 강제로 일괄 삭제합니다. 실무에선 각별한 주의가 필요합니다.
-- dummy_table 테이블을 완전히 삭제
DROP TABLE dummy_table;

-- 데이터와 뷰 등과 함께 hr 스키마를 소멸 (CASCADE 사용 시 관련된 모든 것을 연쇄 삭제)
-- 현재 hr 스키마를 쓰고 있다면 에러가 나거나 테이블이 날아가므로 주석 처리 상태입니다.
-- DROP SCHEMA hr CASCADE;

-- public 스키마로 검색 경로 원복
SET search_path TO public;
