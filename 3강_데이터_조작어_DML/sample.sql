-- =========================================================================
-- [3강] 데이터 조작어 (DML) - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: departments, employees 임시 테이블 가정)
CREATE TEMP TABLE departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(50) UNIQUE,
    location VARCHAR(50)
);

CREATE TEMP TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50) NOT NULL,
    salary NUMERIC(10,2),
    dept_id INT REFERENCES departments(dept_id),
    is_active BOOLEAN DEFAULT true
);

-- [샘플 예제 1: 기본 데이터 삽입 (단일 건)]
-- departments 테이블에 데이터를 1건 입력합니다. 
INSERT INTO departments (dept_name, location) 
VALUES ('Engineering', 'Seoul');

-- [샘플 예제 2: 여러 행의 동시 삽입 (Multi-row Insert)]
-- employees 테이블에 단일 쿼리로 다수 건의 직원을 등록합니다.
INSERT INTO employees (emp_name, salary, dept_id) 
VALUES 
    ('John Doe', 5000.00, 1),
    ('Jane Smith', 6000.00, 1),
    ('Tom Hard', 4500.00, 1);

-- [샘플 예제 3: 다른 테이블의 데이터를 조회하여 일괄 삽입 (INSERT ... SELECT)]
-- 기존 employees 테이블의 복사본(백업용)을 만들고, 거기에 조건에 맞는 현재 전체 데이터를 삽입합니다.
-- (먼저 구조가 같은 백업 테이블 생성)
CREATE TEMP TABLE employees_backup AS SELECT * FROM employees WITH NO DATA;

INSERT INTO employees_backup
SELECT * FROM employees WHERE is_active = true;

-- [샘플 예제 4: 조건에 맞는 데이터 특정 컬럼 수정 (UPDATE)]
-- 이름이 'John Doe'인 직원의 급여를 변경합니다.
UPDATE employees 
SET salary = 5200.00 
WHERE emp_name = 'John Doe';

-- [샘플 예제 5: 다중 컬럼 수정]
-- 'Tom Hard' 직원의 근무 상태를 비활성화하고, 급여를 0으로 조정합니다.
UPDATE employees 
SET salary = 0, is_active = false 
WHERE emp_name = 'Tom Hard';

-- [샘플 예제 6: 연산식을 포함한 일괄 수정과 RETURNING (급여 인상)]
-- Engineering(dept_id=1) 부서 직원 전체의 급여를 5% 일괄 인상하고,
-- UPDATE된 직원의 ID, 이름, 새로 적용된 급여(salary)를 애플리케이션에 반환(RETURNING)합니다.
UPDATE employees 
SET salary = salary * 1.05 
WHERE dept_id = 1 AND is_active = true
RETURNING emp_id, emp_name, salary as new_salary;

-- [샘플 예제 7: 조건에 맞는 데이터 삭제 (DELETE)]
-- 잘못된 데이터나 퇴사자로 표기된(is_active=false) 직원 데이터를 테이블에서 지웁니다.
DELETE FROM employees 
WHERE is_active = false;

-- [샘플 예제 8: 삭제되는 데이터 정보 반환 (DELETE ... RETURNING)]
-- 삭제 직전 지워진 데이터의 상세 내용을 애플리케이션으로 넘겨받아 로깅(Logging)용도로 활용합니다.
DELETE FROM employees 
WHERE salary < 5000 
RETURNING emp_id, emp_name, salary;

-- [샘플 예제 9: 데이터 충돌 시 덮어쓰기 (UPSERT, ON CONFLICT DO UPDATE)]
-- 특정 부서가 이미 존재(dept_name이 UNIQUE라고 가정)하면 에러 대신 location을 덮어씁니다.
INSERT INTO departments (dept_name, location)
VALUES ('Engineering', 'Busan')
ON CONFLICT (dept_name) 
DO UPDATE SET location = EXCLUDED.location
RETURNING *;

-- [샘플 예제 10: 데이터 충돌 시 조용히 무시하기 (ON CONFLICT DO NOTHING)]
-- 중복된 부서명 입력이 들어오면 에러를 내뿜지 않고 그냥 그 레코드의 삽입을 무시(Skip)합니다.
INSERT INTO departments (dept_name, location)
VALUES ('Engineering', 'Jeju')
ON CONFLICT (dept_name) 
DO NOTHING;

-- =========================================================================
-- [성능 최적화 방안] RETURNING 애플리케이션 I/O 실전 최적화 예제
-- =========================================================================
-- 테이블 생성과 동시에 등록된 ID/일자를 다시 조회하는 Network Roundtrip 비용을 아끼기 위해
-- RETURNING 구문을 적극 사용하여 불필요한 SELECT 후속 조회를 제거합니다.

-- CREATE TEMP TABLE orders (order_id SERIAL, user_id INT, amount INT);

-- 삽입 후 발급된 order_id를 1건의 트랜잭션/통신 내로 받아가는 실무 예제:
-- INSERT INTO orders (user_id, amount) VALUES (99, 50000)
-- RETURNING order_id;
