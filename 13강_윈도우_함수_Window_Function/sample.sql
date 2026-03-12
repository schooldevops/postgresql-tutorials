-- =========================================================================
-- [13강] 윈도우 함수 (Window Function) - 실전 샘플 쿼리 10선
-- =========================================================================

-- (사전 준비: 윈도우 함수 실습용 부서별 사원 및 매출 더미 데이터 생성)
CREATE TEMP TABLE sales_data (
    sale_id SERIAL PRIMARY KEY,
    emp_name VARCHAR(50),
    dept_name VARCHAR(50),
    sale_date DATE,
    amount NUMERIC(10,2)
);

INSERT INTO sales_data (emp_name, dept_name, sale_date, amount) VALUES 
('Alice', 'Sales', '2023-11-01', 1000.00),
('Alice', 'Sales', '2023-11-02', 1500.00),
('Bob', 'Sales', '2023-11-01', 2000.00),
('Bob', 'Sales', '2023-11-03', 1000.00),
('Charlie', 'Marketing', '2023-11-01', 1200.00),
('Charlie', 'Marketing', '2023-11-02', 1200.00),
('Dave', 'Marketing', '2023-11-03', 800.00);


-- [샘플 예제 1: 그룹을 무너뜨리지 않는 OVER() 절 기본]
-- 개별 거래 건수를 출력하면서, "전체 회사 매출의 총합계"도 나란히 덧붙입니다.
SELECT emp_name, dept_name, amount,
       SUM(amount) OVER() AS company_total_sales
FROM sales_data;


-- [샘플 예제 2: 그룹 내 통계 보여주기 (PARTITION BY + 집계함수)]
-- 회사 전체 합계가 아닌, 그 직원이 속한 부서(dept_name)만을 묶어서 부서 총 매출을 옆에 덧붙입니다.
SELECT emp_name, dept_name, amount,
       SUM(amount) OVER(PARTITION BY dept_name) AS my_dept_total
FROM sales_data;


-- [샘플 예제 3: 무조건 1부터 발급하는 단순 줄 세우기 (ROW_NUMBER)]
-- 각 부서별(PARTITION BY)로 파티션을 치고, 그 안에서 매출이 제일 높은 순서(ORDER BY)대로 무조건 1, 2, 3.. 고유 순위표를 발급합니다.
SELECT emp_name, dept_name, amount,
       ROW_NUMBER() OVER(PARTITION BY dept_name ORDER BY amount DESC) as sales_rn
FROM sales_data;


-- [샘플 예제 4: RANK() vs DENSE_RANK() 동점자 순위 처리의 차이]
-- 마케팅 부서의 찰리가 이틀 연속 1200원을 팔았습니다(공동 1위).
-- RANK는 1, 1, 3위를 주고 / DENSE_RANK는 1, 1, 2위를 줍니다.
SELECT emp_name, dept_name, amount,
       RANK() OVER(PARTITION BY dept_name ORDER BY amount DESC) as rk,
       DENSE_RANK() OVER(PARTITION BY dept_name ORDER BY amount DESC) as drk
FROM sales_data;


-- [샘플 예제 5: 누적 판매액 산정 (PARTITION + ORDER)]
-- 엘리스와 밥이 시간(sale_date)이 흐를수록 돈을 얼마씩 '누적(Running Total)'해서 벌었는지 확인합니다.
-- OVER 안에 ORDER BY가 들어가면 맨 위부터 '현재 행까지 누적'하라는 숨은 명령이 켜집니다.
SELECT emp_name, sale_date, amount,
       SUM(amount) OVER(PARTITION BY emp_name ORDER BY sale_date) AS running_amount
FROM sales_data;


-- [샘플 예제 6: 이전 날짜(시간)의 데이터 훔쳐오기 (LAG)]
-- 현재 내 행(Row)에 앨리스의 "바로 전날(1칸 위)" 매출을 함께 띄워놓고 등락률을 구합니다.
SELECT emp_name, sale_date, amount,
       LAG(amount, 1) OVER(PARTITION BY emp_name ORDER BY sale_date) AS prev_day_amount
FROM sales_data;


-- [샘플 예제 7: 다음 데이터 훔쳐오거나 빈 값 채우기 (LEAD와 DEFAULT)]
-- 다음 날 매출(1칸 밑)을 봅니다. 마지막 날짜라서 다음 날 비교군이 없을(NULL) 경우 기본값(0)을 주도록 설정합니다.
SELECT emp_name, sale_date, amount,
       LEAD(amount, 1, 0) OVER(PARTITION BY emp_name ORDER BY sale_date) AS next_day_amount
FROM sales_data;


-- [샘플 예제 8: 주식, 코인 차트의 이동 평균 구하기 (ROWS BETWEEN)]
-- 영업일 기준 최근 2일(현재, 어제) 치의 평균 매출(이동 평균) 선을 그립니다.
SELECT emp_name, sale_date, amount,
       AVG(amount) OVER(
           PARTITION BY emp_name 
           ORDER BY sale_date 
           ROWS BETWEEN 1 PRECEDING AND CURRENT ROW -- 나 한칸 위부터 ~ 나까지의 범위
       ) AS moving_avg_2days
FROM sales_data;


-- [샘플 예제 9: 특정 등급 풀(상위/중위/하위 그룹) 배정하기 (NTILE)]
-- 전체 직원에 대해 매출 총합을 구한 다음, 서브쿼리로 감싼 후 이들을 균등하게 3개(상/중/하)의 버킷(통)으로 나눕니다.
WITH total_sales AS (
    SELECT emp_name, SUM(amount) AS sum_amount 
    FROM sales_data GROUP BY emp_name
)
SELECT emp_name, sum_amount,
       NTILE(3) OVER(ORDER BY sum_amount DESC) AS bucket_grade
FROM total_sales;


-- [샘플 예제 10: 제일 처음과 제일 첫 마지막 값 고정하기 (FIRST_VALUE / LAST_VALUE)]
-- 이 부서 전체 기간 중에서 '가장 처음 발생했던 영업 매출 구액'을 모든 직원의 쿼리에 각인시켜 보여줍니다.
SELECT dept_name, emp_name, sale_date, amount,
       FIRST_VALUE(amount) OVER(PARTITION BY dept_name ORDER BY sale_date) AS dept_first_sale
FROM sales_data;

-- =========================================================================
-- [조언] 윈도우 함수는 "결과를 다 뽑고 나서 조립 전에 표식을 붙이는" 기능입니다.
-- 만약 조건으로 써서 필터링하고 싶으면 반드시 밖으로 FROM( ... ) 이나 WITH()로 빼주세요.
-- =========================================================================
