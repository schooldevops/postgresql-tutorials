-- =========================================================================
-- [20강] 고가용성과 커넥션 풀링 (HA & PgBouncer) - 실전 모니터링 쿼리 10선
-- =========================================================================

-- 개요: 인프라/DBA 관점에서 마스터(Primary) 데이터베이스가 자식(Replica)들에게 데이터를
-- 잘 복제 스트리밍하고 있는지 샅샅이 감시하고, 논리적 출판(Publication)을 시뮬레이션합니다.
-- 또한 좀비 커넥션들을 추적하여 연결 수 초과를 방어하는 모니터링 뷰(View) 쿼리를 확인합니다.


-- (사전 준비: 논리적 단일 복제를 테스트하기 위한 임의 테이블 생성)
CREATE TEMP TABLE inventory (
    item_id INT PRIMARY KEY,
    item_name VARCHAR(100),
    quantity INT
);

INSERT INTO inventory (item_id, item_name, quantity) VALUES 
(1, 'Database Server', 10), (2, 'Network Switch', 20);


-- [샘플 예제 1: 내가 복제 대장(마스터 DB) 인지 노예(읽기 전용 DB) 인지 신분(Role) 조회]
-- True 가 나오면 Read-Only 모드인 스탠바이(Replica) 서버이고, False 가 나오면 무소불위의 Master 서버를 의미.
SELECT pg_is_in_recovery() AS is_replica_db;


-- [샘플 예제 2: [Master 전용] 나한테 빨대 꽂은 Replica 들의 IP와 대기열(지연: Lag) 염탐하기]
-- 스트리밍 복제가 고립/단절되지 않았는지 헬스체크(Health Check).
-- sync_state 가 'sync' 혹은 'async' 인지, 그리고 지연량인 reply_lsn이 잘 따라오는지 점검합니다.
SELECT pid, usename, application_name, client_addr, state, sync_state, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes 
FROM pg_stat_replication;


-- [샘플 예제 3: [Replica 전용] 나는 마스터로부터 얼마나 뒤처져(지연) 있는가 자가진단표]
-- 마스터가 보낸 WAL 트랜잭션 수신 시간과, 내 디스크에 적용되는 갭(Gap)이 벌어지면 앱에서 옛날 조회가 됩니다.
SELECT pg_last_wal_receive_lsn() AS received_log, 
       pg_last_wal_replay_lsn() AS applied_log,
       NOW() - pg_last_xact_replay_timestamp() AS time_lag;


-- [샘플 예제 4: 논리적 복제 도입 (PUBLICATION) - 테이블 일부만 "구독 방송 채널" 만듬]
-- 나는 inventory 테이블만, UPDATE 될 때 옛날 값까지 포함해서 샅샅이 외부로 쏴주겠다(REPLICA IDENTITY FULL).
ALTER TABLE inventory REPLICA IDENTITY FULL;
CREATE PUBLICATION pub_inventory_updates FOR TABLE inventory;


-- [샘플 예제 5: 내가 운영하는 출판물(Publication) 조회]
-- 카프카(Kafka)나 Debezium, 타 기종 DB로 빨아들이기 위해 틀어놓은 방송 채널 이름과 목록 파악.
SELECT pubname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'pub_inventory_updates';


-- (이후 다른 DB인 타겟(Target) 서버에서는 아래와 같은 스크립트로 구독(SUBSCRIBE)합니다.)
-- [샘플 예제 6: 논리적 복제 전용 (비활성화 상태 기재)]
/*
CREATE SUBSCRIPTION sub_local_inventory_mirror 
CONNECTION 'host=192.168.1.10 port=5432 dbname=mydb user=repl password=sekret' 
PUBLICATION pub_inventory_updates;
*/


-- [샘플 예제 7: 내 데이터베이스 서버를 잡아먹고 있는 좀비 커넥션 총량 세기]
-- max_connections 제한(예: 100개)에 다다르면 DB가 터집니다. 
-- State 컬럼값(active/idle/idle in transaction) 중에서 미친 듯이 늘어나는 걸 찾아 경고를 울립니다.
SELECT datname, state, COUNT(*) as connection_count
FROM pg_stat_activity 
GROUP BY datname, state
ORDER BY connection_count DESC;


-- [샘플 예제 8: (치명적) "Idle in transaction" 즉결 처형 리스트 작성]
-- 스프링(앱)에서 DB.Begin() 락만 걸어놓고 Java로 루프 돌며 하루 종일 쿼리를 안 날리는 미친 좀비(연결선 누수)들.
-- 이놈들이 있으면 PgBouncer 커넥션 풀이 꽉 차고 다른 모든 접속이 무한 대기 걸림. 해당 PID를 뽑습니다.
SELECT pid, usename, client_addr, query_start, NOW() - query_start AS duration_wait 
FROM pg_stat_activity 
WHERE state = 'idle in transaction' 
AND NOW() - query_start > INTERVAL '1 minute'; 
-- 1분이 넘게 잠수타는 놈들은 모조리 강제 종료 1순위.


-- [샘플 예제 9: 좀비 프로세스 무자비 강제 킬(Kill) (DBA의 필살기)]
-- 위 예제 8에서 뽑아낸 PID(예: 7777, 8888)를 잘라버리고 커넥션을 풀(Pool)로 반납시켜 DB 가용성을 회복시킵니다.
-- SELECT pg_terminate_backend(7777); 
-- SELECT pg_terminate_backend(8888); 


-- [샘플 예제 10: PgBouncer 처럼 외부 풀러 없이, DB 자체 내장 세션 타임아웃 방패치기 설정]
-- 사실 DB 파라미터단에서 옵션을 넣어두면 앱이 예절 없게 연결을 안 끊어도 알아서 단두대로 쳐버립니다.
-- idle in transaction 상태로 60,000ms(60초) 이상 버티면 연결선 자체를 끊어버려라 선언(postgresql.conf 설정급)
-- ALTER SYSTEM SET idle_in_transaction_session_timeout = '60000';
-- SELECT pg_reload_conf();

-- =========================================================================
-- [조언] 실무에서는 수백 개의 API/Lambda 가 DB 하나만 바라보도록 직접 물리지 마세요.
-- DB 커넥션 풀은 고갈되기 아주 쉽습니다. 웬만하면 PgBouncer(Transaction Mode)를 사이에 하나 넣어 
-- 커넥션을 돌려쓰고 라우팅(Read/Write 쪼개기) 하는 것이 백엔드 장애를 막는 교과서입니다.
-- =========================================================================
