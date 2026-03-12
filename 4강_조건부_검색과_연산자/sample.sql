-- =========================================================================
-- [4강] 조건부 검색과 연산자 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: employees, departments 임시 테이블 가정)
CREATE TEMP TABLE departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(50) UNIQUE
);

CREATE TEMP TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50) NOT NULL,
    salary NUMERIC(10,2),
    dept_id INT REFERENCES departments(dept_id),
    email VARCHAR(100),
    hire_date DATE
);

-- 초기 데이터 세팅
INSERT INTO departments (dept_id, dept_name) VALUES (1, 'Sales'), (2, 'Engineering'), (3, 'HR');
INSERT INTO employees (emp_name, salary, dept_id, email, hire_date) VALUES 
('John Doe', 5000.00, 1, 'john@example.com', '2022-01-15'),
('Jane Smith', 6000.00, 2, NULL, '2023-05-20'),
('Tom Hard', 4500.00, 1, 'tom@example.com', '2021-11-10'),
('Alice Brown', 7000.00, 2, 'alice@example.com', '2020-08-01'),
('Bob White', 3500.00, 3, NULL, '2023-09-01');


-- [샘플 예제 1: 단순 비교 검색 (=, >, <)]
-- 급여가 5000 이상인 직원 목록을 조회합니다.
SELECT emp_name, salary 
FROM employees 
WHERE salary >= 5000;


-- [샘플 예제 2: 포함 여부 다중 검색 (IN)]
-- 부서 번호가 1 또는 3인(Sales, HR) 직원들을 찾습니다.
SELECT emp_name, dept_id 
FROM employees 
WHERE dept_id IN (1, 3);


-- [샘플 예제 3: 범위 검색 (BETWEEN)]
-- 2022년도에 입사한 직원들(경계값 포함)을 기간으로 검색합니다.
SELECT emp_name, hire_date 
FROM employees 
WHERE hire_date BETWEEN '2022-01-01' AND '2022-12-31';


-- [샘플 예제 4: 문자열 패턴 검색 (LIKE / ILIKE)]
-- 이름에 'j' 또는 'J'가 들어가는 직원을 대소문자 구분 없이 검색합니다(ILIKE).
SELECT emp_name 
FROM employees 
WHERE emp_name ILIKE '%j%';


-- [샘플 예제 5: 논리 연산자 복합 검색 (AND, OR, 괄호)]
-- 부서 번호가 1이면서 급여가 4000 초과이거나, 부서 번호가 2인 직원을 필터링합니다.
SELECT emp_name, salary, dept_id
FROM employees 
WHERE (dept_id = 1 AND salary > 4000) 
   OR dept_id = 2;


-- [샘플 예제 6: 특정 조건을 제외하는 검색 (NOT, !=, <>)]
-- 이메일 주소가 없거나 영업부서(1번)가 아닌 직원을 조회합니다.
SELECT emp_name, email, dept_id
FROM employees 
WHERE dept_id <> 1 
   OR email IS NULL;


-- [샘플 예제 7: NULL 값 검색 (IS NULL, IS NOT NULL)]
-- 이메일 주소가 정식으로 등록되어 있는 직원만 추출합니다.
SELECT emp_name, email 
FROM employees 
WHERE email IS NOT NULL;


-- [샘플 예제 8: NULL 데이터 치환 출력 (COALESCE)]
-- 이메일이 없는 직원은 '미입력'으로 대체 텍스트를 출력합니다. (검색 조건이 아니라 출력 가공)
SELECT emp_name, 
       COALESCE(email, '이메일 미등록') AS contact_email
FROM employees;


-- [샘플 예제 9: 특정 값 목록을 제외하는 부정 검색 (NOT IN)]
-- 2번과 3번 부서를 제외한 나머지 부서 직원 명단 (여기서는 1번만 나옴)
SELECT emp_name, dept_id 
FROM employees 
WHERE dept_id NOT IN (2, 3);


-- [샘플 예제 10: 조건 연산으로 여러 값 선택하기 (CASE WHEN)]
-- 직원의 급여 수준에 따라 임시로 등급 파생 컬럼을 생성하여 조회합니다.
SELECT emp_name,
       salary,
       CASE 
           WHEN salary >= 6000 THEN 'A등급'
           WHEN salary >= 4500 THEN 'B등급'
           ELSE 'C등급'
       END AS salary_grade
FROM employees;

-- =========================================================================
-- [성능 최적화 방안] 올바른 범위 검색 SQL 작성하기
-- =========================================================================
-- [비효율적인 방식] DATE 컬럼 자체를 함수로 감싸서 변형 (Index Full Scan 발생)
-- SELECT emp_name, hire_date FROM employees WHERE TO_CHAR(hire_date, 'YYYY-MM') = '2023-05';

-- [권장하는 방식] DATE 컬럼을 보존하고, 우측 비교값을 범위(>=, <)로 명시 (Index Range Scan 유도)
-- SELECT emp_name, hire_date FROM employees
-- WHERE hire_date >= '2023-05-01'
--   AND hire_date < '2023-06-01';
