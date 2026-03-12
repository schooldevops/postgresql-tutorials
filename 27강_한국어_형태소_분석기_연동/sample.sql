-- =========================================================================
-- [27강] 한국어 형태소 분석기 연동 및 N-gram (pg_trgm) - 실전 샘플 쿼리 10선
-- =========================================================================

-- 사전 준비: 3글자 단위로 영어든 한국어든 찢어서 인덱스를 태워주는 
-- 가장 대중적인 기본 치트키 확장팩(pg_trgm)을 활성화합니다.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TEMP TABLE board_articles (
    article_id SERIAL PRIMARY KEY,
    title VARCHAR(100),
    content TEXT
);

INSERT INTO board_articles (title, content) VALUES 
('여름휴가 계획', '바다로 가고 싶다. 파도를 타면서 즐겁게 놀자.'),
('겨울방학 안내', '이번 겨울에는 스키장이 대세입니다.'),
('데이터베이스 공부', '포스트그레의 GIN 인덱스와 전문 검색은 혁명이다.'),
('오타가 난 데이타베이스', '데이타베이스의 트리그램 인덱스를 테스트한다.'),
('AI 검색과 튜닝', '벡터에다가 풀텍스트 트리그램을 섞어보자');

-- [제일 중요한 대목!]
-- 만약 아래 인덱스가 없으면 LIKE '%가방%' 같은 검색어는 테이블을 풀스캔하며 서버 자원을 고갈시킵니다.
-- gin_trgm_ops 플래그를 달고 텍스트 컬럼에 역색인을 씌우면 풀스캔을 면해줍니다!
CREATE INDEX idx_board_content_trgm 
ON board_articles USING GIN (content gin_trgm_ops);


-- [샘플 예제 1: ILIKE 스캔을 뚫고 지나는 오타 면제 (Fuzzy) 검색]
-- 보통 '은 혁명이다' 라고 검색하면 B-Tree 로는 못 찾지만, GIN Trigram이 이걸 색출해 냅니다.
SELECT title, content 
FROM board_articles 
WHERE content ILIKE '%은 혁명이다%';


-- [샘플 예제 2: Trigram 내부 분해의 시각적 증명 (show_trgm 함수)]
-- "포스트그레" 라는 5글자를 던지면 DB는 3글자로 씩씩하게 어떤 퍼즐 조각들을 만들어 낼까?
SELECT show_trgm('포스트그레');
-- 결과 조각들: "  포", " 포스", "그레 ", "스트그", "트그레", "포스트" 형태의 마구잡이 조각 배열!


-- [샘플 예제 3: 오타가 엄청 심해서 검색 결과가 매치율(%) 순서대로 뜨게 하기]
-- '다이타배스' 라고 오타를 냈지만, 3글자의 중복 겹침 퍼센트(%)를 기반으로 랭킹 정답('데이터베이스')을 돌려줌
SELECT title, content, 
       similarity(title, '다이타배스') AS similarity_score
FROM board_articles 
WHERE title % '다이타배스' -- % 연산자는 유사도가 일정 기준(임계값 LIMIT) 이상 되면 true 를 던짐
ORDER BY similarity_score DESC;


-- [샘플 예제 4: 더 짠내 나는 커스텀 오타를 잡기 위해 기본 제한 문턱(Threshold) 풀기]
-- % 오퍼레이터는 pg_trgm 의 퍼지 제한점이 기본 0.3 (30%) 일치할 때만 잡게 되어있는데,
-- 이걸 0.1 로 내려서 얼토당토않은 오타도 다 잡아당기게 만들어 봄.
SET pg_trgm.similarity_threshold = 0.1;
SELECT title, similarity(title, '다이타배스') AS score 
FROM board_articles 
WHERE title % '다이타배스';


-- [샘플 예제 5: 형태소 분석기(Mecab)가 깔렸을 때의 한국어 진짜 FTS 맛보기 - 시뮬레이션]
-- (korean 이라는 외부 OS 봇이 텍스트로 들어온 조사 "가", "의"를 잘라내는 역할)
-- SELECT to_tsvector('korean', '포스트그레의 전문 검색은 혁명이다') 
--        @@ to_tsquery('korean', '포스트그레 & 혁명');
-- 한국어 사전이 없다면 위 구문은 'simple' 로 우회하여 작동시켜야 하지만 조사 때문에 '포스트그레' (안 나옴).


-- [샘플 예제 6: 검색 거리(Distance) 계산의 반대 개념 - <-> 연산자]
-- '<->' 연산자는 similarity 함수의 "역수" (1 - similarity) 로, 거리 간격을 뜻합니다. 작을수록 똑같음.
SELECT title, 
       title <-> '여름휴가' AS typo_distance 
FROM board_articles
ORDER BY title <-> '여름휴가' ASC
LIMIT 2;


-- [샘플 예제 7: PostgreSQL 의 맹점 - 2글자 이하의 단어는 방어가 안 됨]
-- '%파%' 같이 1글자나 '%파도%' 2글자 치면 Trigram 의 3글자 뼈대 구조상 인덱스를 무시(Seq Scan)하고 달립니다.
-- 성능 튜닝 시 EXPLAIN 무조건 까봐야 하는 이유!
EXPLAIN 
SELECT * FROM board_articles WHERE content ILIKE '%파도%'; 
-- 만약 Index Scan 이 아니라 Seq Scan 이 뜨면 pg_trgm 이 파도 의 글자수가 너무 작아 인덱스를 패스한 것.


-- [샘플 예제 8: (고급 튜닝) 인덱스가 안 먹히는 2글자를 위해 억지로 강제화]
-- 영문, 혹은 특수 한글의 경우 인덱싱 파라미터를 강제로 B-Tree 의 text_pattern_ops 로 때우는 꼼수 병행 탑재.
-- CREATE INDEX idx_board_title_btree ON board_articles (title varchar_pattern_ops);
-- 이러면 '파도%' 란 단어로 시작하는 검색은 B-Tree 를 타고 빛의 속도로 나감!


-- [샘플 예제 9: 특정 배열/JSON 안의 긴 형태 텍스트들도 조각내어 GIN에 우겨넣기]
CREATE TEMP TABLE complex_docs (id INT, metadata JSONB);
INSERT INTO complex_docs VALUES (1, '{"tags": ["AI", "Search"], "desc": "백터 검색 인덱싱"}');
CREATE INDEX idx_json_trgm ON complex_docs USING GIN ((metadata->>'desc') gin_trgm_ops);
-- JSON 안에 들어간 Text 에 대해서도 오타나 %LIKES% 쿼리에 슈퍼 부스터를 제공합니다.


-- [샘플 예제 10: Trigram 과 Vector <-> 검색을 섞은, DB 내장 기능만으로 구현한 퓨어 하이브리드 서치]
-- (21강 vector 와 27강 FTS 의 랑데뷰 쿼리) 
-- WITH 
-- text_rank AS (SELECT id, ROW_NUMBER() OVER(ORDER BY title <-> '겨울스키장') AS tr FROM board_articles),
-- vec_rank  AS (SELECT id, ROW_NUMBER() OVER(ORDER BY embedding <=> '[0.1, 0.2]') AS vr FROM external_vectors)
-- ... JOIN 결합 (25강 하이브리드 RRF 참조)

-- =========================================================================
-- [조언] pg_trgm 은 LIKE '%단어%' 쿼리를 초가속시키는 전설적인 확장 기능이지만, 
-- 글자를 모조리 3조각으로 갈기갈기 찢기 때문에 인덱스 크기가 미친 듯이 커집니다.
-- 텍스트 컬럼이 긴 (본문 3천 자 이상) 곳에 걸면 디스크 풀(Disk Full) 장애가 올 수 있으니
-- '제목' 이나 '핵심 키워드' 컬럼에만 전략적으로 GIN 을 태워주세요.
-- =========================================================================
