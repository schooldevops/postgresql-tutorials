-- =========================================================================
-- [5강] 데이터 정렬과 페이징 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 페이징 실습용 직원 데모 테이블 생성 및 다량의 데이터 삽입)
CREATE TEMP TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50) NOT NULL,
    salary NUMERIC(10,2),
    dept_id INT,
    hire_date DATE
);

-- 초기 샘플 삽입
INSERT INTO employees (emp_name, salary, dept_id, hire_date) VALUES 
('John Doe', 5000.00, 1, '2020-01-15'),
('Jane Smith', 6000.00, 2, '2021-05-20'),
('Tom Hard', 4500.00, 1, '2019-11-10'),
('Alice Brown', 7000.00, 2, '2022-08-01'),
('Bob White', 3500.00, 3, '2018-09-01'),
('Chris Green', NULL, 1, '2023-01-01'),
('David Black', 5500.00, 2, '2019-12-11'),
('Eva White', 6000.00, 1, '2021-03-15'),
('Frank Red', 4000.00, 3, '2020-07-20'),
('Grace Lee', NULL, 2, '2023-04-10'),
('Henry Kim', 4800.00, 1, '2021-08-30');


-- [샘플 예제 1: 기본 오름차순/내림차순 연산]
-- 입사일이 가장 최근인 직원(늦은 날짜)부터 내림차순 정렬하여 보여줍니다.
SELECT emp_name, hire_date 
FROM employees 
ORDER BY hire_date DESC;


-- [샘플 예제 2: 다중 조건 정렬]
-- 부서 번호(오름차순 1->3) 정렬 후, 같을 경우 급여(내림차순, 고연봉자)를 2차 기준으로 정렬합니다.
SELECT emp_name, dept_id, salary 
FROM employees 
ORDER BY dept_id ASC, salary DESC;


-- [샘플 예제 3: NULL 데이터가 맨 마지막 위치하도록 강제]
-- 급여가 정해지지 않은(NULL) 인턴 사원들이 상위에 나오는 걸 방지하고자 맨 맨 뒤로 넘깁니다.
SELECT emp_name, salary 
FROM employees 
ORDER BY salary DESC NULLS LAST;


-- [샘플 예제 4: 제일 낮은 NULL 데이터 먼저 출력하기 (NULLS FIRST)]
-- 가장 낮은 연봉자부터 보여주되, 아직 미측정된(NULL) 대상자를 제일 앞단에 배치하여 확인합니다.
SELECT emp_name, salary 
FROM employees 
ORDER BY salary ASC NULLS FIRST;


-- [샘플 예제 5: 반환되는 전체 레코드 개수 제한 (LIMIT N)]
-- 연봉 상위 TOP 3의 사령부 직원 명단을 뽑아옵니다.
SELECT emp_name, salary 
FROM employees 
ORDER BY salary DESC NULLS LAST 
LIMIT 3;


-- [샘플 예제 6: 시작점부터 건너뛰어 가져오는 구조화 (OFFSET n)]
-- 상위 1, 2, 3위 사원은 건너뛰고, 그 다음인 4위, 5위 2명의 사원 명단을 뽑습니다.
SELECT emp_name, salary 
FROM employees 
ORDER BY salary DESC NULLS LAST 
LIMIT 2 OFFSET 3;


-- [샘플 예제 7: 페이지네이션(Pagination) 조회 공식의 적용]
-- 화면에 4명씩 출력한다고 가정할 때, 제 2페이지(5~8번째 자료) 데이터를 구합니다.
-- OFFSET = (보려는페이지번호 - 1) * 보여줄크기 -> (2-1)*4 = 4를 건너뜀
SELECT emp_id, emp_name, hire_date 
FROM employees 
ORDER BY hire_date DESC 
LIMIT 4 OFFSET 4;


-- [샘플 예제 8: 랜덤하게 N건 레코드 무작위 추출하기]
-- RANDOM() 함수를 기준으로 정렬시키고 2건을 가져오면, 새로고침 시마다 사원이 달라집니다. (이벤트 추첨 등에 사용)
SELECT emp_name, dept_id 
FROM employees 
ORDER BY RANDOM() 
LIMIT 2;


-- [샘플 예제 9: ANSI 표준 SQL 윈도우 방식으로 페이징]
-- 대부분의 기업용 RDBMS (Oracle 등) 과 호환이 가능하도록 LIMIT/OFFSET 대신 FETCH 기반 표준 문법 활용합니다.
SELECT emp_name, salary 
FROM employees 
ORDER BY salary DESC NULLS LAST
OFFSET 2 ROWS FETCH FIRST 3 ROWS ONLY;


-- [샘플 예제 10: (성능 최적화 연계) 커서 기반 페이지네이션 기법]
-- 수백만 건의 데이터를 페이징할 때, 앱에서 마지막으로 받은 ID(예: 8)를 이용해 그 이전 입사자 3명을 가져옵니다.
-- OFFSET이 없어 디스크 부하 없이 즉각적인 INDEX 탐색이 이루어집니다.
SELECT emp_id, emp_name, hire_date 
FROM employees 
WHERE emp_id < 8 
ORDER BY emp_id DESC 
LIMIT 3;

-- =========================================================================
-- [주의사항] 
-- LIMIT 문을 쓸 때 ORDER BY 절이 생략되면, PostgreSQL 내부 스토리지 엔진이 블록 빈칸을
-- 우선 반환하므로 결과 순서가 섞여 중복 표출될 위험이 큽니다. 항상 ORDER BY 와 페어링 하세요.
-- =========================================================================
