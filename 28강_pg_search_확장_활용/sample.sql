-- =========================================================================
-- [28강] pg_search 확장 활용 (ParadeDB 기반 BM25 전문 검색) - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: Elasticsearch를 대체하는 ParadeDB(pg_search) 익스텐션을 활성화하고,
-- 기존 B-Tree나 GIN으로 감당 불가능한 BM25 기반 초고속 랭킹 검색을 수행합니다.

-- [사전 준비] pg_search (ParadeDB 환경 기준) 익스텐션 로드
CREATE EXTENSION IF NOT EXISTS pg_search;

-- 뉴스/기사 통합 관리 테이블 (텍스트, 카테고리, 날짜 혼합)
CREATE TEMP TABLE news_articles (
    article_id SERIAL PRIMARY KEY,
    title VARCHAR(200),
    body TEXT,
    author VARCHAR(50),
    views INT,
    publish_date DATE
);

INSERT INTO news_articles (title, body, author, views, publish_date) VALUES 
('PostgreSQL 17 Released', 'Huge performance improvements in B-Tree and Vector Search.', 'Alice', 1500, '2023-10-01'),
('Python for Data Science', 'Learn pandas and numpy for machine learning applications.', 'Bob', 5000, '2023-09-15'),
('Database Tuning Guide', 'How to configure work_mem to optimize your PostgreSQL database.', 'Charlie', 200, '2024-01-05'),
('AI and Vector DB', 'Vector databases are taking over the AI landscape. Pinecone vs Postgres.', 'Alice', 8000, '2024-02-14'),
('Learn Python Fast', 'Basic syntax of Python programming language for beginners.', 'Dave', 300, '2023-11-20');


-- [샘플 예제 1: BM25 하이브리드 인덱스 통째로 부어 만들기]
-- 단 하나의 프로시저 Call 로, 루씬 레벨의 초거대 Rust 인덱스를 테이블 옆에 증축시킵니다.
CALL paradedb.create_bm25(
  index_name => 'idx_news_bm25_search',
  table_name => 'news_articles',
  key_field => 'article_id',
  text_fields => '{title, body, author}',  -- 검색 질의가 찌를 수 있는 3개의 텍스트 필드
  numeric_fields => '{views}'              -- 숫자로 필터링(> 1000) 할 수 있게 등록
);


-- [샘플 예제 2: @@@ 기본 매칭 연산과 Elastic Query 언어 검색]
-- 'postgres' 라는 글자가 제목이든 본문이든 저자든 어디든 들어가 있는 뉴스 찾기
SELECT title, author 
FROM news_articles 
WHERE article_id @@@ paradedb.parse('postgres');


-- [샘플 예제 3: BM25 랭킹 스코어 구하기 (ElasticSearch _score 의 심장)]
-- 단어(TF) 빈도수와, 역문서(IDF) 빈도, 문서 길이(Length)를 고려한 전설의 방정식.
-- 점수가 제일 높은 놈(relevance) 역순 정렬.
SELECT title, 
       paradedb.score('idx_news_bm25_search', article_id) AS bm25_relevance_score
FROM news_articles 
WHERE article_id @@@ paradedb.parse('python | data')
ORDER BY bm25_relevance_score DESC;


-- [샘플 예제 4: 다중 필드(Multi-field) 저격 검색]
-- 무조건 'title' (제목) 에만 'database' 란 글자가 있는 글만 찾아! (본문에만 있는 건 기각)
SELECT title, body 
FROM news_articles 
WHERE article_id @@@ paradedb.parse('title:database');


-- [샘플 예제 5: 논리 연산자 (AND, OR, NOT) 복합 질의 쿼리]
-- "Python 에 대한 글인데, Basic 도 엮여있되, 머신러닝(Machine) 글자는 싹 빼라!"
SELECT title, body 
FROM news_articles 
WHERE article_id @@@ paradedb.parse('python AND basic NOT machine');


-- [샘플 예제 6: 숫자 필드(numeric_fields) 범위(Range) 스칼라 필터링]
-- "데이터베이스 관련된(database) 글인데, 조회수(views)가 1000 이 안 되는 비인기 글만 가져와"
SELECT title, views, paradedb.score('idx_news_bm25_search', article_id) AS score
FROM news_articles 
WHERE article_id @@@ paradedb.parse('database AND views:<1000')
ORDER BY score DESC;


-- [샘플 예제 7: 정확한 띄어쓰기 뭉치(Phrase) 구문 강제 고정 쿼리]
-- "machine learning" 이라고 큰따옴표("")로 감싸면, 
-- "machine" 한 줄 뛰고 "learning" 있는 글은 버리고 딱 저 두 단어가 연달아 붙어 있는 글만 정확히 캐냄.
SELECT title, body 
FROM news_articles 
WHERE article_id @@@ paradedb.parse('"machine learning"');


-- [샘플 예제 8: 오타 보정 퍼지(Fuzzy) 검색 (~ 틸드)]
-- 'pythoon' 이라고 유저가 키보드 오타를 냈지만, 편집거리를 산출해 스스로 'python' 으로 치환해 정답 찾음.
SELECT title 
FROM news_articles 
WHERE article_id @@@ paradedb.parse('pythoon~');


-- [샘플 예제 9: 특정 문자로 시작하는 와일드카드(Prefix) 별표 검색 (단어의 접두사)]
-- 'perfor*' 라고 치면 'performance', 'performed' 등 앞 대가리만 같은 단어를 싹 다 긁어옴
SELECT title, body 
FROM news_articles 
WHERE article_id @@@ paradedb.parse('perfor*');


-- [샘플 예제 10: 검색 결과 하이라이팅 (Highlight HTML 스니펫 조립)]
-- 구글 웹 노출용으로, 백엔드가 할 일 없이 DB가 알아서 '<b>vector</b>' 처럼 태그를 입혀서 발사함.
SELECT title, 
       paradedb.highlight('idx_news_bm25_search', article_id, 'body') AS search_snippet
FROM news_articles 
WHERE article_id @@@ paradedb.parse('vector');

-- =========================================================================
-- [조언] 실무에서는 외부 ElasticSearch 로 데이터를 퍼나르지 마세요.
-- AWS EC2나 온프레미스 Docker 에서 ParadeDB 확장 하나만 켜두면,
-- 당신의 시스템 백엔드 아키텍처는 절반으로 줄고 장애 요소는 1/10 로 사라집니다.
-- =========================================================================
