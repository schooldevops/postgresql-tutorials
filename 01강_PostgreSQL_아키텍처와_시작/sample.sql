-- =========================================================================
-- [1강] PostgreSQL 아키텍처와 시작 - 실전 샘플 쿼리 10선
-- =========================================================================

-- [샘플 예제 1: PostgreSQL 버전 확인]
-- 현재 설치된 PostgreSQL의 버전과 컴파일된 OS 환경 등의 정보를 확인합니다.
SELECT version();


-- [샘플 예제 2: 현재 세션의 접속 정보 확인]
-- 자신이 접속한 데이터베이스 이름과 사용자 계정을 확인합니다.
SELECT current_database(), current_user;


-- [샘플 예제 3: 주요 설정 파일 위치 확인]
-- PostgreSQL 운영 중 설정 파일(postgresql.conf)이 어느 경로에 위치하는지 찾습니다.
SHOW config_file;


-- [샘플 예제 4: 공유 메모리 버퍼(Shared Buffers) 크기 확인]
-- DB 성능에 가장 큰 영향을 미치는 핵심 메모리의 현재 할당량을 확인합니다.
SHOW shared_buffers;


-- [샘플 예제 5: 현재 실행 중인 프로세스 및 쿼리 확인]
-- 데이터베이스에 접속된 세션 목록과 활성화되어 실행 중인 쿼리를 실시간으로 모니터링합니다.
SELECT pid, usename, datname, state, query 
FROM pg_stat_activity 
WHERE state = 'active';


-- [샘플 예제 6: 현재 세션의 프로세스 ID 확인]
-- 트러블슈팅 또는 락(Lock) 확인 시 기준이 되는 본인의 Backend 프로세스 ID(PID)를 호출합니다.
SELECT pg_backend_pid();


-- [샘플 예제 7: 특정 동적 시스템 설정 조회]
-- pg_settings 뷰를 활용하여 메모리 할당 설정(work_mem) 값을 확인하고 단위를 함께 출력합니다.
SELECT name, setting, unit, short_desc 
FROM pg_settings 
WHERE name = 'work_mem';


-- [샘플 예제 8: 환경 설정 재시작 없이 적용하기]
-- postgresql.conf 파일을 수정 후 DB를 완전히 내리지 않고 설정을 리로드합니다.
-- (주의: 이 함수는 관리자 권한이 필요할 수 있습니다.)
SELECT pg_reload_conf();


-- [샘플 예제 9: 시스템 로그 및 데이터 디렉토리 위치 파악]
-- 실제 데이터 파일이 저장되는 물리적 경로 확인에 사용됩니다.
SHOW data_directory;


-- [샘플 예제 10: 데이터베이스별 상태 통계 확인]
-- 각 데이터베이스마다 커밋된 트랜잭션 수와 롤백 횟수, 접속자 수 등 통계를 확인합니다.
SELECT datname, numbackends, xact_commit, xact_rollback 
FROM pg_stat_database 
WHERE datname = current_database();


-- =========================================================================
-- [성능 최적화 방안] 메모리 최적화 설정 예제
-- =========================================================================
-- 메모리가 부족한 작업을 실행하기 전, 세션 단위로 임시 메모리를 증가시킵니다.
-- 주의: 너무 큰 값을 전역으로 설정하면 OOM(Out Of Memory) 이슈가 발생할 수 있습니다.

-- 세션 단위로 복잡한 정렬(Sort)이나 해시(Hash) 연산을 위해 로컬 메모리를 증가
SET work_mem = '64MB';

-- 인덱스 생성, VACUUM 등의 작업을 더 빠르게 수행하기 위해 유지보수 메모리 할당 증가
SET maintenance_work_mem = '256MB';
