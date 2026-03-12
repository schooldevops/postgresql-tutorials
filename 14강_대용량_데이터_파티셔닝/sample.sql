-- =========================================================================
-- [14강] 대용량 데이터 파티셔닝 - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 월별(Range), 지역별(List), 그리고 Hash를 혼용한 고급 파티션 시뮬레이션을 구현하고 
-- 실무에서 대량 데이터를 넣었을 때 옵티마이저가 어떻게 쿼리를 격리하는지 증명합니다.


-- [샘플 예제 1: Range 파티션을 위한 메인 테이블 껍데기 생성]
-- 날짜(`log_date`)를 분할 기준 스펙으로 잡는 접속 로그 테이블입니다. 물리 공간은 0바이트입니다.
CREATE TEMP TABLE access_logs (
    log_id BIGSERIAL,
    user_id INT,
    action VARCHAR(50),
    log_date DATE NOT NULL
) PARTITION BY RANGE (log_date);


-- [샘플 예제 2: 범위가 명시된 자식(하위) 테이블 생성 붙이기]
-- 주의: TO('2024-02-01') 은 해당 날짜는 미포함하고 그 전날까지만 포함합니다 (수학에서 < 연산).
CREATE TEMP TABLE access_logs_2024_01 PARTITION OF access_logs 
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TEMP TABLE access_logs_2024_02 PARTITION OF access_logs 
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');


-- [샘플 예제 3: Default 파티션(쓰레기통) 생성 및 데이터 밀어넣기]
-- 선언된 1~2월 구간을 벗어난 날짜가 입력되면 죽지 않고 임시로 쌓일 DEFAULT 파티션을 안전벨트로 만듭니다.
CREATE TEMP TABLE access_logs_future PARTITION OF access_logs DEFAULT;

INSERT INTO access_logs (user_id, action, log_date) VALUES 
(1, 'LOGIN', '2024-01-15'), -- 1월 파티션으로 향함
(2, 'CLICK', '2024-02-28'), -- 2월 파티션으로 향함
(3, 'LOGOUT', '2025-12-31'); -- 아무데도 갈 곳이 없어 DEFAULT 파티션으로 향함


-- [샘플 예제 4: 내가 넣은 데이터가 제대로 찢어져 들어갔는지 물리 폴더 검색 (Pruning Test)]
-- 메인 테이블이 아닌 자식 테이블에 직접 SELECT 를 날려봐도 1건만 예쁘게 격리된 걸 증명합니다.
SELECT COUNT(*) FROM access_logs_2024_01; -- 1건 출력결과


-- [샘플 예제 5: List 방식의 파티셔닝 기초 세팅]
-- 지역 코드처럼 범주형 문자열을 기준으로 대형 테이블을 여러 개로 쪼개는 방식입니다.
CREATE TEMP TABLE global_users (
    user_id SERIAL,
    username VARCHAR(50),
    country_code VARCHAR(3) NOT NULL
) PARTITION BY LIST (country_code);

CREATE TEMP TABLE users_kr PARTITION OF global_users FOR VALUES IN ('KR');
CREATE TEMP TABLE users_us PARTITION OF global_users FOR VALUES IN ('US');
CREATE TEMP TABLE users_others PARTITION OF global_users DEFAULT;


-- [샘플 예제 6: 다중 리스트 범위 묶기 및 데이터 주입]
-- 유럽 통합 서버처럼 여러 조건을 묶어 하나로 배정할 수 있습니다 (Partition List Group).
CREATE TEMP TABLE users_eu PARTITION OF global_users FOR VALUES IN ('UK', 'FR', 'DE');

INSERT INTO global_users (username, country_code) VALUES 
('Kim', 'KR'), ('John', 'US'), ('Hans', 'DE'), ('Ali', 'AE'); -- (AE는 others 로 흡수)


-- [샘플 예제 7: Hash 방식의 파티셔닝 생성]
-- 도무지 날짜나 지역 같은 논리적인 구분 기준이 없고, 그저 트랜잭션을 4등분(N) 랜덤 분산하고 싶을 때 사용합니다.
CREATE TEMP TABLE system_logs (
    log_id UUID NOT NULL,
    message TEXT
) PARTITION BY HASH (log_id);

CREATE TEMP TABLE logs_hash_1 PARTITION OF system_logs FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TEMP TABLE logs_hash_2 PARTITION OF system_logs FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TEMP TABLE logs_hash_3 PARTITION OF system_logs FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TEMP TABLE logs_hash_4 PARTITION OF system_logs FOR VALUES WITH (MODULUS 4, REMAINDER 3);


-- [샘플 예제 8: (튜닝 필수!) 옵티마이저가 똑똑하게 하나의 파티션만 찌르는지 플랜 보기]
-- "2월 데이터만 내놔봐!" 했을 때 바보같이 1월/Default 테이블까지 뒤지지 않고 2월만 치고 빠지는 'Partition Pruning' 점검입니다.
-- 결과(Plan)에서 "Seq Scan on access_logs_2024_02" 만 잡히면 파티셔닝 성공입니다.
EXPLAIN 
SELECT * FROM access_logs WHERE log_date = '2024-02-15';


-- [샘플 예제 9: 특정 파티션을 분리(DETACH)하여 아카이빙 하기]
-- 메인 테이블(`access_logs`) 조회 시 이제 1월은 철 지난 데이터라 빼고 싶다면 빠르게 가지치기합니다. (메트릭/뷰에서 분리)
ALTER TABLE access_logs DETACH PARTITION access_logs_2024_01;
-- 이 순간부터 SELECT * FROM access_logs 에서는 2024_01 데이터가 보이지 않습니다! (독립 테이블화 성공)


-- [샘플 예제 10: 초고속 1초 컷으로 과거 데이터 수백만 건 흔적도 없이 지우기 (DROP)]
-- 메인에서 DETACH된 데이터를 HDD 구석진 디스크로 옮기거나, 그냥 버리겠다면 DROP TABLE 로 일말의 망설임 없이 삭제합니다.
-- 이 부분은 DELETE FROM ~ 구문보다 I/O 코스트가 수백만 배 적게 드는 기적을 보여줍니다.
DROP TABLE access_logs_2024_01;

-- =========================================================================
-- [조언] 실무에서는 1일, 1주일, 1달 단위 파티셔닝 전략을 잘 짜두어야 합니다.
-- 또한 `PARTITION BY`에 지정된 컬럼(예: log_date)이 
-- WHERE 조건절에 포함되어 있지 않은 쿼리는 모든 파티션을 풀스캔 때리는 재앙을 낳으니 조심하세요.
-- =========================================================================
