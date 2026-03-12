# 3강: 데이터 조작어 (DML)

## 개요 
본 강의에서는 정의된 테이블에 실제 데이터를 밀어넣고(INSERT), 변경하고(UPDATE), 삭제하는(DELETE) 데이터 조작어(DML, Data Manipulation Language)의 핵심을 다룹니다. 추가적으로 PostgreSQL만의 강력한 기능인 `RETURNING` 절과, 데이터 충돌 시 업데이트로 전환하는 `UPSERT` 구문에 대해서도 학습합니다.

```mermaid
graph TD
    DML[데이터 조작어 DML]
    
    DML --> InsertCmd[데이터 삽입\nINSERT INTO]
    DML --> UpdateCmd[데이터 수정\nUPDATE]
    DML --> DeleteCmd[데이터 삭제\nDELETE FROM]
    
    InsertCmd --> SingleRow[단일행 삽입]
    InsertCmd --> MultiRow[다중행 삽입\nMulti-row Insert]
    InsertCmd --> Upsert[충돌 제어 방식\nON CONFLICT (UPSERT)]
    
    UpdateCmd --> WhereCond[조건부 수정\nWHERE 절]
    DeleteCmd --> WhereCond2[조건부 삭제\nWHERE 절]
    
    InsertCmd -.-> Returning[실행 결과 반환\nRETURNING]
    UpdateCmd -.-> Returning
    DeleteCmd -.-> Returning
```

## 사용형식 / 메뉴얼 

**데이터 삽입 (INSERT)**
```sql
-- 특정 컬럼 지정 삽입
INSERT INTO 테이블명 (컬럼1, 컬럼2) 
VALUES (값1, 값2);

-- 다중 데이터 동시 삽입 (Multi-row Insert)
INSERT INTO 테이블명 (컬럼1, 컬럼2) 
VALUES (값1_1, 값2_1), 
       (값1_2, 값2_2);
```

**데이터 수정 (UPDATE)**
```sql
UPDATE 테이블명 
SET 컬럼1 = 새값1, 컬럼2 = 새값2 
WHERE 조건;
```

**데이터 삭제 (DELETE)**
```sql
DELETE FROM 테이블명 
WHERE 조건;
```

**RETURNING 절과 UPSERT (PostgreSQL 특화)**
```sql
-- INSERT/UPDATE/DELETE 후 처리된 결과를 별도 조회 없이 즉시 반환
UPDATE 테이블명 SET 컬럼명 = 값 WHERE 조건
RETURNING *; -- 또는 반환할 특정 컬럼명 목록

-- ON CONFLICT: 데이터 삽입 시 고유키(PK/Unique) 충돌 시 무시하거나 덮어쓰기 (UPSERT)
INSERT INTO 테이블명 (ID, 변경값) VALUES (1, '새로운값')
ON CONFLICT (ID) 
DO UPDATE SET 변경값 = EXCLUDED.변경값;
```

## 샘플예제 5선 

[샘플 예제 1: 기본 데이터 삽입 (INSERT)]
- `departments` 테이블에 새로운 부서 데이터를 한 건 등록합니다.
```sql
INSERT INTO departments (dept_name, location) 
VALUES ('Engineering', 'Seoul');
```

[샘플 예제 2: 여러 행의 데이터 동시 삽입 (Multi-row INSERT)]
- `employees` 테이블에 여러 직원의 정보를 단일 쿼리로 한 번에 등록합니다.
```sql
INSERT INTO employees (emp_name, salary, dept_id) 
VALUES ('John Doe', 5000.00, 1),
       ('Jane Smith', 6000.00, 1),
       ('Tom Hard', 4500.00, 1);
```

[샘플 예제 3: 데이터 수정 후 즉시 결과 받기 (UPDATE & RETURNING)]
- 특정 직원의 급여를 인상하고, 수정된 레코드의 내용을 별도의 `SELECT` 쿼리 없이 바로 돌려받습니다.
```sql
UPDATE employees 
SET salary = salary * 1.1 
WHERE emp_id = 1
RETURNING emp_id, emp_name, salary;
```

[샘플 예제 4: 조건에 맞는 데이터 삭제 (DELETE)]
- 퇴사 처리 등을 위해 급여가 특정 금액 미만인 레코드를 데이터베이스에서 삭제합니다.
```sql
DELETE FROM employees 
WHERE salary < 4000.00;
```

[샘플 예제 5: 데이터 충돌 시 업데이트 처리 (UPSERT)]
- 같은 직원이 이미 등록되어 기본키(`emp_id`)나 `UNIQUE` 조건에서 충돌이 나면, 에러를 내뿜는 대신 다른 정보(급여 등)를 `UPDATE` 하도록 처리합니다.
```sql
INSERT INTO employees (emp_id, emp_name, salary, is_active) 
VALUES (1, 'John Doe', 5500.00, true)
ON CONFLICT (emp_id) 
DO UPDATE SET salary = EXCLUDED.salary, is_active = true;
```

*(상세한 쿼리와 추가 실전 예제는 `sample.sql` 파일을 확인해주세요.)*

## 주의사항 
- `UPDATE`와 `DELETE` 구문에서 **`WHERE` 조건절을 누락하면 테이블의 전체 데이터가 한꺼번에 수정/삭제**되는 대형 장애가 발생할 수 있습니다. 운영 환경에서는 반드시 사전에 `SELECT ... WHERE ...` 쿼리로 대상을 분명히 확인한 이후에 DML을 수행하는 습관을 들여야 합니다.
- 다량의 데이터를 `INSERT` 할 때는 루프(for/while) 안에서 한 건씩 밀어넣는 것보다, 본문의 [샘플 예제 2] 와 같이 뱃치(Batch) 형태의 다중 `INSERT`를 사용하는 것이 네트워크 비용과 트랜잭션 오버헤드를 아껴 엄청나게 빠릅니다.
- PostgreSQL에서 DML은 자동으로 MVCC(다중 버전 동시성 제어) 기반으로 처리되므로, 데이터가 `UPDATE` 혹은 `DELETE` 된다 하더라도 찌꺼기(Dead Tuple)가 파일 시스템에 남게 됩니다. 후속 강의인 VACUUM 메커니즘을 숙지하여 디스크 조각남 현상을 관리해야 합니다.

## 성능 최적화 방안
[RETURNING을 활용한 애플리케이션 I/O 최적화]
```sql
-- 안 좋은 방식 (네트워크 통신이 2번 발생)
INSERT INTO orders (user_id, amount) VALUES (1, 50000);
-- 애플리케이션에서 별도로 최근 등록한 내역의 PK를 재조회해야 함
SELECT MAX(order_id) FROM orders;

-- 최적화 방식 (데이터 통신 1번에 끝남)
INSERT INTO orders (user_id, amount) VALUES (1, 50000)
RETURNING order_id, order_date;
```
- **성능 개선이 되는 이유**: 웹 서버나 애플리케이션에서 DB에 레코드를 삽입(`INSERT`)한 직후, 시스템이 자동으로 생성한 식별번호(PK)나 등록 임시일 등을 알기위해 또 다시 `SELECT` 문을 전송하는 경우가 흔히 발생합니다. `RETURNING` 절을 활용하면, 삽입/변경 연산을 수행한 직후 해당 데이터를 응답 값에 포함시켜 서버로 되돌려줍니다. 불필요한 네트워크 통신(Round Trip)을 절반으로 줄여 어플리케이션의 처리량(Throughput)을 눈에 띄게 끌어올릴 수 있습니다.
