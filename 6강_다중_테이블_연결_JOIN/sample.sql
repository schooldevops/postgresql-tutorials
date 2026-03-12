-- =========================================================================
-- [6강] 다중 테이블 연결 (JOIN) - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: JOIN 실습용 부서, 직원, 직급 임시 데모 테이블 생성)
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

CREATE TEMP TABLE job_positions (
    pos_id SERIAL PRIMARY KEY,
    position_name VARCHAR(50)
);

-- 초기 샘플 삽입
INSERT INTO departments (dept_id, dept_name) VALUES 
(1, 'Sales'), (2, 'Engineering'), (3, 'HR'), (4, 'Marketing'); -- Marketing 부서에는 직원이 없음

INSERT INTO job_positions (position_name) VALUES
('Staff'), ('Manager'), ('Director');

INSERT INTO employees (emp_name, salary, dept_id, manager_id) VALUES 
('Boss John', 10000.00, 2, NULL),         -- 보스 (관리자 없음)
('Manager Smith', 8000.00, 1, 1),         -- Sales 매니저 (상사 1)
('Engineer Alice', 6000.00, 2, 1),        -- Engineering 사원 (상사 1)
('Clerk Bob', 4000.00, 1, 2),             -- Sales 평사원 (상사 2)
('Intern Charlie', 3000.00, NULL, 3);     -- 부서 아직 미배치된 인턴사원 (상사 3)


-- [샘플 예제 1: 기준키 연결 (INNER JOIN 기본)]
-- 소속 부서가 명확하게 등록된 직원(인턴 제외)들과 소속된 부서명 리스트를 가져옵니다.
SELECT e.emp_id, e.emp_name, d.dept_name
FROM employees AS e
INNER JOIN departments AS d ON e.dept_id = d.dept_id;


-- [샘플 예제 2: 기준이 없는 사원까지 전부 가져오기 (LEFT OUTER JOIN)]
-- 부서 배치를 못 받은 고아 데이터(인턴 찰리)도 누락시키지 않도록, 기준인 사원 테이블(LEFT)의 모든 걸 보존합니다.
SELECT e.emp_name, COALESCE(d.dept_name, '부서 미배정') AS dept_info
FROM employees AS e
LEFT JOIN departments AS d ON e.dept_id = d.dept_id;


-- [샘플 예제 3: 짝이 없는 유령 데이터 찾기 (LEFT JOIN + WHERE IS NULL)]
-- 반대로, 부서는 존재하는데 직원이 1명도 등록되지 않은, 사용되지 않는 부서(마케팅 부서)만 추려냅니다.
SELECT d.dept_name 
FROM departments AS d
LEFT JOIN employees AS e ON d.dept_id = e.dept_id
WHERE e.emp_id IS NULL;


-- [샘플 예제 4: 두 테이블의 교차 시나리오 도출 (CROSS JOIN)]
-- 4개의 부서 * 3개의 직급 = 총 12가지의 '부서-직급' T.O 테이블을 모두 출력합니다. (경우의 수 조합)
SELECT d.dept_name, p.position_name 
FROM departments AS d
CROSS JOIN job_positions AS p;


-- [샘플 예제 5: 자신을 재귀적으로 바라보기 (SELF JOIN)]
-- 직원의 상사(manager_id) 정보가 곧 같은 사원 테이블(emp_id)에 있을 때 나란히 조회합니다.
SELECT emp.emp_name AS 직원명, 
       COALESCE(mgr.emp_name, '최고 경영자') AS 담당상사명
FROM employees AS emp
LEFT JOIN employees AS mgr ON emp.manager_id = mgr.emp_id;


-- [샘플 예제 6: 다중 JOIN 복합 쿼리 체이닝]
-- 3개의 테이블을 조합하여, 직원 + 부서명 + 그 직원의 상사 이름을 하나로 결합합니다.
SELECT e.emp_name, 
       d.dept_name, 
       m.emp_name AS manager_name
FROM employees AS e
LEFT JOIN departments AS d ON e.dept_id = d.dept_id
LEFT JOIN employees AS m ON e.manager_id = m.emp_id;


-- [샘플 예제 7: 조건부 INNER JOIN (ON 절에 다중 조건)]
-- INNER 조인 시, 특정 급여가 넘는 사원 데이터만 애초에 연결할 수 있도록 ON 안에 조건을 넣습니다.
SELECT e.emp_name, d.dept_name, e.salary 
FROM employees e 
INNER JOIN departments d 
ON e.dept_id = d.dept_id AND e.salary >= 5000;


-- [샘플 예제 8: USING 키워드를 이용한 간략한 JOIN 작성]
-- 매칭되는 양쪽 테이블의 연결 키(dept_id) 이름이 똑같을 경우, ON 대신 USING(키)를 써서 간단히 줄일 수 있습니다. (조인 결과에서 키가 중복 출력 안됨)
SELECT emp_name, dept_name 
FROM employees 
INNER JOIN departments USING (dept_id);


-- [샘플 예제 9: FULL OUTER JOIN 사용처 알아보기]
-- 소속 없는 직원(인턴)과, 사람 없는 부서(마케팅) 양쪽의 붕 뜬 데이터를 하나도 누락 없이 합칩니다.
SELECT e.emp_name, d.dept_name
FROM employees e
FULL OUTER JOIN departments d ON e.dept_id = d.dept_id;


-- [샘플 예제 10: (실무 팁) 조건 시점에 따른 차이 증명]
-- 조인 조건(ON)과 필터 조건(WHERE)의 차이 확인.
-- 아래 쿼리는 LEFT 조인임에도 불구하고 WHERE에서 d.dept_name를 비교하며 필터가 들어가 결국 INNER 결과(매칭된 것만 나오게 됨)와 동일한 오류를 범합니다.
-- 개발자 실수 방지 튜닝용 점검 쿼리입니다.
SELECT e.emp_name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_name = 'Sales'; -- LEFT 의도를 잃고 결합 후 Sales 만 필터링

-- =========================================================================
-- [조언] 실무에서는 FULL OUTER 는 거의 쓸모가 없고, 
-- 주로 주 테이블을 LEFT로 세우거나, 강한 교집합을 INNER JOIN 하는 것을 가장 많이 사용합니다.
-- =========================================================================
