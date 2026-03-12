-- =========================================================================
-- [16강] 뷰와 구체화된 뷰 (Materialized View) - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 테스트를 위한 부서-사원-월급 데이터베이스 임시 구조 배포)
CREATE TEMP TABLE departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(50) NOT NULL
);

CREATE TEMP TABLE employees (
    emp_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50),
    dept_id INT REFERENCES departments(dept_id),
    hire_date DATE,
    salary NUMERIC(10,2)
);

INSERT INTO departments (dept_name) VALUES ('Engineering'), ('HR'), ('Sales');

INSERT INTO employees (emp_name, dept_id, hire_date, salary) VALUES 
('Alice', 1, '2020-01-15', 7000), ('Bob', 1, '2021-03-20', 6000),
('Charlie', 2, '2019-11-01', 5000), ('Dave', 3, '2022-05-11', 4000),
('Eve', 3, '2023-01-05', 4500);


-- [샘플 예제 1: 단순 일반 뷰(View)의 생성]
-- JOIN 이 얽힌 복잡한 형태, 즉, "사원 이름 + 소속 부서 + 연봉" 포맷을 하나의 가상 테이블(v_emp_info) 로 압축합니다.
CREATE VIEW v_emp_info AS
    SELECT e.emp_id, e.emp_name, d.dept_name, e.salary
    FROM employees e
    JOIN departments d ON e.dept_id = d.dept_id;


-- [샘플 예제 2: 만들어진 뷰를 마치 테이블처럼 사용하기]
-- 일반 테이블 쓰듯이 단순 SELECT 만 넘겨주면, 내부적으로는 알아서 방금 정의한 복잡한 JOIN 풀 쿼리로 번역(Expand) 되어 실행됩니다.
SELECT * FROM v_emp_info WHERE salary > 5000;


-- [샘플 예제 3: 민감 데이터를 감추는 보안용 필터 뷰]
-- 외부 시스템에게 데이터를 열어줄 때 급여(salary) 컬럼을 뺀 채로 이름과 부서정보만 노출시키는 안전한 View를 만들어냅니다.
CREATE VIEW v_emp_public AS
    SELECT emp_name, dept_name 
    FROM v_emp_info; -- 이전에 만든 뷰도 뷰에 사용(재활용) 가능


-- [샘플 예제 4: 기존 뷰의 내용을 부수지 않고 안전하게 덮어쓰기 (CREATE OR REPLACE VIEW)]
-- 뷰의 쿼리를 고치고 싶다면 `DROP VIEW` 할 필요 없이, 이 명령어로 조회 구조(입사일자 추가 등)를 덮어씌웁니다.
CREATE OR REPLACE VIEW v_emp_info AS
    SELECT e.emp_id, e.emp_name, d.dept_name, e.hire_date, e.salary
    FROM employees e
    JOIN departments d ON e.dept_id = d.dept_id;


-- [샘플 예제 5: 구체화된 뷰(Materialized View)의 탄생 - 진짜 디스크 공간 물리 스냅샷 구축]
-- 부서별로 급여 통계를 낸 "무거운" 집합 연산을 수행하고 그 결과를 디스크에 `mv_dept_stats`라는 진짜 파일로 캐싱(저장)해 둡니다.
CREATE MATERIALIZED VIEW mv_dept_stats AS
    SELECT d.dept_name, 
           COUNT(e.emp_id) AS total_emp, 
           SUM(e.salary) AS total_salary
    FROM departments d
    LEFT JOIN employees e ON d.dept_id = e.dept_id
    GROUP BY d.dept_name;


-- [샘플 예제 6: 원본의 변화가 MView에 자동 반영되지 않음(스냅샷 증명)]
-- 부서에 새로운 사람이 영입되어 실제 원본 데이터값이 바뀌었으나...
INSERT INTO employees (emp_name, dept_id, hire_date, salary) VALUES ('Zack', 1, '2024-01-01', 9000);

-- 여전히 mv_dept_stats(구체화된 뷰)를 SELECT 해보면 추가 인원이 합산되지 않은 옛날(어제)의 통계가 나옵니다.
SELECT * FROM mv_dept_stats WHERE dept_name = 'Engineering';


-- [샘플 예제 7: 구체화된 뷰 강제 갱신 (리프레시 동기화 - REFRESH)]
-- 이제 명령을 치면, 그 시간표 기준으로 무거운 원본 쿼리를 다시 한 번 실행해서 MView 파일 데이터를 갈아 끼웁니다(통계 업데이트 완료).
REFRESH MATERIALIZED VIEW mv_dept_stats;


-- [샘플 예제 8: 유니크(Unique) 인덱스를 탑재한 괴물 MView 구현]
-- MView 는 일반 View 와 달리 껍데기가 아닌 진짜 테이블이므로 튜닝 마법(인덱스)을 걸어 속도를 100배 가속할 수 있습니다.
-- 무중단 통계를 위해서는 이 유일키(UNIQUE) 선언이 필수적입니다.
CREATE UNIQUE INDEX idx_mv_dept_name ON mv_dept_stats (dept_name);


-- [샘플 예제 9: 무정지 리프레시 동기화 (CONCURRENTLY)]
-- 사용자들이 보고 있는 라이브 통계 화면을 멈추게(Lock) 하지 않고, 오직 바뀐 차이점 데이터 부분만 똑 떼어내어 백그라운드 스왑을 이뤄냅니다.
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dept_stats;


-- [샘플 예제 10: 더미용 빠른 데이터 적재 없이 MView 뼈대만 만들기 (WITH NO DATA)]
-- 쿼리에 너무 천문학적인 시간이 걸려 일단 형태만 만들고 밤에 돌리려 할 때, 데이터를 즉석에서 안 부어넣고 껍데기만 남겨둡니다.
-- 나중에 REFRESH 해야 동작(SELECT)이 가능해집니다.
CREATE MATERIALIZED VIEW mv_yearly_report AS
    SELECT EXTRACT(YEAR FROM hire_date) as yr, SUM(salary) as pay
    FROM employees GROUP BY 1
WITH NO DATA;

-- =========================================================================
-- [조언] 실무에서는 MVIEW가 너무 오래된 데이터를 가르키지 않도록(Stale Data),
-- Event Trigger 설정이나 `pg_cron` 익스텐션을 사용하여 N시간 단위 스케쥴링 갱신 파이프라인(ETL)을 구현합니다.
-- =========================================================================
