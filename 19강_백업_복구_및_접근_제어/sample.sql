-- =========================================================================
-- [19강] 백업, 복구 및 접근 제어 (ACL & RLS) - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 데이터베이스 안에서 사용자(Role)를 만들고, 권한을 제어(GRANT/REVOKE)하며, 
-- 같은 테이블이라도 접속한 계정에 따라 자신의 데이터만 보이게 하는 행 수준 보안(RLS)을 시뮬레이션합니다.

-- (사전 준비: 테스트용 유저 생성 및 권한을 빼앗을 기초 환경 구축)
CREATE ROLE read_only_crew; -- 로그인할 수 없는 가상의 그룹 계정 생성
CREATE ROLE junior_dev WITH LOGIN PASSWORD 'pass1234'; -- 진짜 사람 역할을 하는 계정

CREATE TEMP TABLE secret_docs (
    doc_id SERIAL PRIMARY KEY,
    owner_name VARCHAR(50),
    title VARCHAR(100),
    content TEXT
);

INSERT INTO secret_docs (owner_name, title, content) VALUES 
('junior_dev', '주니어 업무일지', '오늘은 DB 백업을 배웠다.'),
('senior_dev', '핵심 설계도', '이거 지워지면 우리 다 죽는다.'),
('manager', '인사평가표', '주니어 평가: A, 시니어 평가: B');


-- [샘플 예제 1: 그룹에 묶음 권한 주입 및 사람 가입시키기]
-- junior_dev (사람) 을 read_only_crew (그룹) 이라는 큰 배에 태워서 권한을 상속받게 만듭니다.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO read_only_crew;
GRANT read_only_crew TO junior_dev;


-- [샘플 예제 2: 무서운 전체 허가(DROP 대비) 뺏고, 특정 테이블 핀셋 권한 주기]
-- 주니어 개발자가 실수로 운영 테이블을 드랍(Delete/Drop)하는 걸 맞기 위해, 
-- 오로지 INSERT 와 SELECT 만 주는 보안 수칙의 정석.
GRANT INSERT, SELECT ON secret_docs TO junior_dev;
-- UPDATE나 DELETE 명령을 치면 "ERROR: permission denied for table secret_docs" 로 튕김냅니다.


-- [샘플 예제 3: 권한 회수 (REVOKE)]
-- 다시 권한을 박탈하여, 이제부터는 조회는 되는데 글(docs)을 쓸 순 없게 입을 틀어막습니다.
REVOKE INSERT ON secret_docs FROM junior_dev;


-- [샘플 예제 4: 클라우드 멀티-테넌트 아키텍처의 심장! 행 수준 보안(RLS) 스위치 켜기]
-- "내 테이블은 이제부터 누군가 검열을 거치지 않으면 아무것도 꺼내 보지 못한다!" 라는 절대 봉쇄 방패.
ALTER TABLE secret_docs ENABLE ROW LEVEL SECURITY;
-- (이 순간부터 postgres 슈퍼유저가 아닌 일반 유저는 SELECT * 를 쳐도 0줄이 나옵니다. 철통방어)


-- [샘플 예제 5: "자기가 쓴 글만 조회(SELECT) 가능" 보안 정책(Policy) 뚫어주기]
-- 로그인 한 계정의 ID(current_user)와 데이터의 주인(owner_name)이 똑같을 때만 통과시켜 구멍을 만들어 줍니다.
CREATE POLICY p_select_own_docs ON secret_docs 
FOR SELECT 
USING (owner_name = current_user);


-- [샘플 예제 6: "자기가 남이 쓴 글을 덮어쓰거나(UPDATE) 수정하는 것 차단" 정책]
-- USING은 '기존 행 대상 검열' 이고 
-- WITH CHECK 는 '바꾼 새로운 값이 조건에 맞느냐(남의 이름으로 사칭 입력 금지)' 방어막입니다.
CREATE POLICY p_update_own_docs ON secret_docs 
FOR UPDATE 
USING (owner_name = current_user) 
WITH CHECK (owner_name = current_user);


-- [샘플 예제 7: 관리자용 치트키 권한 패스포트 지급]
-- "어, RLS 다 좋은데 난 관리자(manager)라서 싹 다 모니터링해야 해" 라면,
-- BYPASSRLS 옵션을 Role 에게 던져주면 RLS 검열문을 스나이퍼처럼 가볍게 무시하고 통과합니다.
ALTER ROLE manager WITH BYPASSRLS;


-- [샘플 예제 8: (관리자 전용) 누가 우리 DB에 몇 명이나 접속해있나 세션 감시 쿼리]
-- 갑자기 DB 부하가 너무 심할 때, "어느 놈이, 아이피 몇 번에서, 무슨 쿼리를 돌려서 자원을 빨아먹고 있나?" 실시간 뒷조사.
SELECT pid, usename, client_addr, state, query 
FROM pg_stat_activity 
WHERE datname = '내데이터베이스명' AND state != 'idle';


-- [샘플 예제 9: 무한루프에 빠진 악성 세션(쿼리) 강제 킬(Kill - 학살) 명령어]
-- 위의 8번 예제에서 찾아낸 원흉의 강제 프로세스 ID(pid) 번호를 확보하여, 즉시 접속과 실행 쿼리 멱살을 잡고 터뜨립니다.
-- (pid 99999 자리에 실제 악마의 PID 번호를 입력하세요)
-- SELECT pg_terminate_backend(99999);


-- [샘플 예제 10: 현재 내가 시스템 안에서 물고 있는 내 로그인 계정 역할/이름 까보기]
-- "나 지금 무슨 권한으로 들어와 있지?" 세션 세팅 체크용 내장 함수 호출.
SELECT current_user, session_user;

-- =========================================================================
-- [조언] pg_dump 백업 수행 시, OS 에 환경변수(PGPASSWORD) 파라미터를 먹여두거나 
-- ~/.pgpass 보안 파일 안에 "호스트:포트:DB:유저:비밀번호" 형태로 넣어두면
-- 쉘 스크립트 실행 시 패스워드를 묻는 화면에서 멈추는(Hang) 불상사를 막을 수 있습니다.
-- =========================================================================
