-- =========================================================================
-- [7강] 집계 함수와 데이터 그룹화 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 통계 실습을 위한 부서 및 직원 임시 테이블 세팅)
CREATE TEMP TABLE departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(50) NOT NULL
);

CREATE TEMP TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50) NOT NULL,
    salary NUMERIC(10,2), -- 부분 NULL 값을 통한 집계 테스트
    dept_id INT REFERENCES departments(dept_id),
    hire_date DATE
);

INSERT INTO departments (dept_id, dept_name) VALUES 
(1, 'Sales'), (2, 'Engineering'), (3, 'HR');

INSERT INTO employees (emp_name, salary, dept_id, hire_date) VALUES 
('John Doe', 5000.00, 1, '2020-01-15'),
('Jane Smith', 6000.00, 2, '2021-05-20'),
('Alice Brown', 7000.00, 2, '2022-08-01'),
('Tom Hard', 4500.00, 1, '2019-11-10'),
('Bob White', 3500.00, 3, '2018-09-01'),
('Chris Green', NULL, 1, '2023-01-01'), -- 급여가 배정되지 않은 신입(NULL)
('David Black', 5500.00, 2, '2019-12-11'),
('Eva White', 6000.00, 1, '2021-03-15');


-- [샘플 예제 1: 전체 집합 (COUNT, SUM, AVG, MAX, MIN)]
-- 테이블 내 모든 데이터를 대상으로 기초 통계치를 1개의 튜플로 반환합니다.
SELECT COUNT(*) AS total_employees,
       COUNT(salary) AS has_salary_count, -- NULL은 갯수에서 제외되는 특징 증명 (7건)
       SUM(salary) AS sum_salary,
       AVG(salary) AS avg_salary,
       MAX(salary) AS max_salary,
       MIN(salary) AS min_salary
FROM employees;


-- [샘플 예제 2: 그룹별 통계 (GROUP BY)]
-- 각 부서 ID별로 평균 급여액(소수점 1자리 반올림)을 산출하여 정렬합니다.
SELECT dept_id,
       ROUND(AVG(salary), 1) AS cur_avg_salary 
FROM employees 
GROUP BY dept_id 
ORDER BY dept_id;


-- [샘플 예제 3: 여러 기준으로 세분화하여 그룹핑 (다중 GROUP BY)]
-- 부서 번호 내에서도 추가로 `년도` 별로 각각 세분화하여, 그룹을 잘게 쪼개어 건수를 집계합니다.
SELECT dept_id, 
       EXTRACT(YEAR FROM hire_date) AS hire_year, 
       COUNT(*) AS cur_emp_cnt
FROM employees
GROUP BY dept_id, EXTRACT(YEAR FROM hire_date)
ORDER BY dept_id ASC, hire_year DESC;


-- [샘플 예제 4: 그룹 결과에 필터링 적용 (HAVING)]
-- 부서별로 인원이 3명 이상 배치된 '대형 부서'의 평균 급여만 필터링해서 봅니다.
SELECT dept_id, 
       COUNT(*) AS cur_emp_cnt,
       AVG(salary) AS cur_avg_salary 
FROM employees 
GROUP BY dept_id 
HAVING COUNT(*) >= 3;


-- [샘플 예제 5: WHERE + GROUP BY + HAVING 전체 복합 쿼리 체이닝]
-- [WHERE] 2021년 이전 입사자만 대상으로, [GROUP BY] 부서별 묶어내어, [HAVING] 통계가 5000이 넘는 부서의 내역을 도출.
SELECT dept_id, 
       SUM(salary) AS old_emp_salary
FROM employees 
WHERE hire_date < '2021-01-01'
GROUP BY dept_id
HAVING SUM(salary) > 5000;


-- [샘플 예제 6: 다중 테이블 결합 후 통계 (JOIN + GROUP BY)]
-- 부서 번호 숫자(dept_id) 대신 부서 명칭(dept_name) 으로 예쁘게 조인하여 통계 시각화 및 정렬을 맞춥니다.
SELECT d.dept_name, 
       SUM(e.salary) AS total_group_salary
FROM employees AS e
INNER JOIN departments AS d ON e.dept_id = d.dept_id
GROUP BY d.dept_name
ORDER BY total_group_salary DESC NULLS LAST;


-- [샘플 예제 7: 유령 데이터가 포함된 통계 (LEFT JOIN + GROUP BY + COALESCE)]
-- 급여(NULL)를 받는 신입('Chris Green') 때문에 SUM() 시 일부분 비어 보이는 문제를 0으로 치환합니다.
SELECT d.dept_name, 
       COALESCE(SUM(e.salary), 0) AS safe_sum_salary
FROM departments AS d
LEFT JOIN employees AS e ON d.dept_id = e.dept_id
GROUP BY d.dept_name;


-- [샘플 예제 8: 유의미한 특정 조건만 합산 (FILTER 기능 - PostgreSQL 전용)]
-- 여러 개의 복잡한 합계를 한 번에 뽑을 때 유용한 고급 기법입니다. (WHERE 처럼 동작)
-- 전체 급여 총량과, 6000 이상의 프리미엄 급여 총량을 나란히 단일 로우로 뽑습니다.
SELECT SUM(salary) AS total_salary,
       SUM(salary) FILTER (WHERE salary >= 6000) AS high_salary_sum
FROM employees;


-- [샘플 예제 9: 여러 개의 독립적인 통계 (GROUPING SETS 역할)]
-- GROUPING SETS 를 통해 부서별 통계와, 전체 통합 통계 2가지 결과를 하나의 결과셋(ResultSet) 안에 이어 붙입니다.
SELECT dept_id, SUM(salary) AS group_sum
FROM employees
GROUP BY GROUPING SETS ( (dept_id), () )
ORDER BY dept_id;


-- [샘플 예제 10: 집계 함수와 문자열 결합 (STRING_AGG)]
-- 부서별로 누가 소속되어 있는지를 리스트 형태의 하나의 문자열 열로 이어 붙입니다. (MySQL의 GROUP_CONCAT 대응)
SELECT d.dept_name, 
       STRING_AGG(e.emp_name, ', ' ORDER BY e.hire_date) AS member_list
FROM departments d
INNER JOIN employees e ON d.dept_id = e.dept_id
GROUP BY d.dept_name;

-- =========================================================================
-- [조언] 통계를 위해 무거운 GROUP BY 를 계속 수행하는 건 비효율적입니다. 
-- 대용량 배치 집계는 야간에 스케줄러로 돌려서 구체화된 뷰(Materialized View) 테이블에 넣어두고,
-- 앱에서는 단순 SELECT만 하도록 구조(Data Warehouse)를 고도화하는 것이 바람직합니다.
-- =========================================================================
