-- =========================================================================
-- [8강] 서브쿼리와 공통 테이블 식 - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 서브쿼리용 임시 부서, 직원 스키마 세팅 및 데이터 삽입)
CREATE TEMP TABLE departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(50) NOT NULL
);

CREATE TEMP TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50) NOT NULL,
    salary NUMERIC(10,2),
    dept_id INT REFERENCES departments(dept_id),
    manager_id INT REFERENCES employees(emp_id)
);

INSERT INTO departments (dept_id, dept_name) VALUES 
(1, 'Executive'), (2, 'Sales'), (3, 'Engineering'), (4, 'Marketing');

INSERT INTO employees (emp_name, salary, dept_id, manager_id) VALUES 
('Boss CEO', 15000.00, 1, NULL),
('VP Sales', 10000.00, 2, 1),
('VP Tech', 12000.00, 3, 1),
('Sales Rep A', 5000.00, 2, 2),
('Sales Rep B', 4500.00, 2, 2),
('Senior Dev', 8000.00, 3, 3),
('Junior Dev', 4000.00, 3, 6);


-- [샘플 예제 1: 단순 스칼라 서브쿼리 (단일 값 도출)]
-- 전체 직원의 평균 급여를 구한(단일 스칼라값) 숫자보다 급여를 많이 받는 임원/사원의 목록만 추출합니다.
SELECT emp_name, salary 
FROM employees 
WHERE salary > (SELECT AVG(salary) FROM employees);


-- [샘플 예제 2: 연관 스칼라 서브쿼리를 통한 출력값 생성]
-- 직원의 목록을 뽑되, 그 직원이 속한 부서명은 서브쿼리로 부서 테이블을 찔러서 가져옵니다. (JOIN 대체)
SELECT e.emp_name, e.salary,
       (SELECT d.dept_name 
        FROM departments d 
        WHERE d.dept_id = e.dept_id) AS dept_name_subq
FROM employees e;


-- [샘플 예제 3: IN 절을 활용한 다중값 서브쿼리 (필터링)]
-- 평균 급여보다 돈을 많이 받는 사람들이 소속된 잘나가는 부서 정보 전체를 찾습니다.
SELECT dept_id, dept_name 
FROM departments
WHERE dept_id IN (
    SELECT DISTINCT dept_id 
    FROM employees 
    WHERE salary > (SELECT AVG(salary) FROM employees)
);


-- [샘플 예제 4: EXISTS 를 이용한 조인 대체 여부 조사]
-- 해당 부서에 아직 사람이 1명이라도 존재하지 않는 부서를 찾습니다. (IN 사용시보다 속도 향상)
SELECT dept_name 
FROM departments d
WHERE NOT EXISTS (
    SELECT 1 FROM employees e 
    WHERE e.dept_id = d.dept_id
);


-- [샘플 예제 5: 인라인 뷰(Inline View)를 활용한 그룹 데이터 조인]
-- 부서별 최고 급여액이라는 새로운 가상 테이블 세트(max_sal_info)를 만들어 내고 본문과 교차(INNER JOIN)시킵니다.
SELECT e.emp_name, e.salary, e.dept_id
FROM employees e
INNER JOIN (
    SELECT dept_id, MAX(salary) AS top_salary
    FROM employees
    GROUP BY dept_id
) max_sal_info ON e.dept_id = max_sal_info.dept_id AND e.salary = max_sal_info.top_salary;


-- [샘플 예제 6: CTE(Common Table Expression)를 적용한 깔끔한 코드 분리]
-- 예제 5와 똑같은 동작을 하나, 위쪽 가상 테이블 선언 블록인 `WITH`를 사용하여 훨씬 더 직관적이고 깔끔하게 설계합니다.
WITH department_max_salary AS (
    SELECT dept_id, MAX(salary) AS max_sal
    FROM employees
    GROUP BY dept_id
)
SELECT m.emp_name, m.salary, cte.max_sal, m.dept_id 
FROM employees m
JOIN department_max_salary cte ON m.dept_id = cte.dept_id AND m.salary = cte.max_sal;


-- [샘플 예제 7: 2개 이상의 연속된 CTE 테이블 선언과 참조]
-- 첫 번째 임시 테이블(avg_calc)을, 두 번째 임시 테이블(high_paid)에서 다시 재사용하여 복잡한 로직을 끊어갑니다.
WITH avg_calc AS (
    SELECT AVG(salary) AS total_avg FROM employees
),
high_paid AS (
    SELECT emp_name, salary 
    FROM employees 
    WHERE salary > (SELECT total_avg FROM avg_calc)
)
SELECT * FROM high_paid; -- 최종 메인 쿼리


-- [샘플 예제 8: ANY(SOME) / ALL 연산자 활용]
-- Engineering(dept_id=3) 부서의 "가장 낮은 연봉"보다도 더 많이 받는 다른 부서의 직원을 찾습니다. (> ANY 기능)
SELECT emp_name, salary, dept_id
FROM employees 
WHERE salary > ANY (
    SELECT salary FROM employees WHERE dept_id = 3
) AND dept_id != 3;


-- [샘플 예제 9: 계층형 구조 (조직도, 카테고리 트리)를 풀어내는 재귀형 CTE]
-- WITH RECURSIVE를 통해 Boss CEO(Level 1) 부터 누가 누구 부하인지 직급 체인을 내려가며 탐색하는 트리 탐색 쿼리입니다.
WITH RECURSIVE org_tree AS (
    -- 1계층(루트): 상사가 없는 CEO
    SELECT emp_id, emp_name, manager_id, 1 AS depth_level, emp_name::text AS path
    FROM employees 
    WHERE manager_id IS NULL
    
    UNION ALL
    
    -- 2계층~반복: 자신의 매니저가 직전 사이클의 emp_id인 자식 노드를 찾아서 계속 붙임
    SELECT e.emp_id, e.emp_name, e.manager_id, t.depth_level + 1,
           t.path || ' -> ' || e.emp_name
    FROM employees e
    INNER JOIN org_tree t ON e.manager_id = t.emp_id
)
-- 계산이 끝난 전체 조직도 계층 트리를 단계별로 정렬 출력
SELECT emp_name, depth_level, path 
FROM org_tree 
ORDER BY path;


-- [샘플 예제 10: 재귀를 곁들인 DUMMY 날짜 시퀀스 생성]
-- 달력, 통계 날짜 구멍 메우기를 위한 날짜(Date) 무한루프 임시 더미 테이블(Generator)을 만듭니다. (PostgreSQL의 generate_series 와 동일 동작 증명구문)
WITH RECURSIVE date_generator(dt) AS (
    SELECT '2023-10-01'::DATE
    UNION ALL
    SELECT dt + INTERVAL '1 day'
    FROM date_generator
    WHERE dt < '2023-10-07'
)
SELECT * FROM date_generator;


-- =========================================================================
-- [조언] 재귀형 쿼리(RECURSIVE)는 특정 조건을 달지 않으면(WHERE절) 
-- 사이클이 무한반복 되어 DB 메모리가 터질 수 있으므로 무한루프 종료 조건 작성이 강력히 요구됩니다.
-- =========================================================================
