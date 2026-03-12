-- =========================================================================
-- [26강] 내장 Full-Text Search (전문 검색) - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 문자열의 꼬리를 떼어 원형 단어로 만드는(Tokenizing) tsvector 추출과,
-- 단어 검색식을 만드는 tsquery 의 문법, 그리고 이들을 매칭(@@)하는 연산 세트입니다.

-- [사전 셋업] 영어 텍스트 검색을 증명하기 위한 리뷰 게시판 테이블
CREATE TEMP TABLE english_reviews (
    id SERIAL PRIMARY KEY,
    author VARCHAR(50),
    review_title VARCHAR(100),
    review_content TEXT,
    fts_tokens TSVECTOR -- 여기에 잘게 쪼갠 렉심(Lexeme) 단어 더미 배열이 들어갑니다
);

-- 데이터 붓기 + 입력과 동시에 원본(content)을 영어사전 기준으로 쪼개어 fts_tokens 컬럼에 자동 삽입(Update)
INSERT INTO english_reviews (author, review_title, review_content) VALUES 
('Alice', 'Great phone!', 'I love this smartphone. The battery is amazing and screen is very bright.'),
('Bob', 'Bad battery life', 'The batteries died so quickly when I was jumping and walking.'),
('Charlie', 'Okay', 'Screens are bright but phone gets hot.'),
('Dave', 'Dog lover', 'This has nothing to do with phones, I just love my dogs.'),
('Eve', 'Return policy', 'I jumps backwards. The screen is broken.');

UPDATE english_reviews 
SET fts_tokens = to_tsvector('english', review_title || ' ' || review_content);

-- 만약 GIN 인덱스를 깔아버리면 검색 속도가 O(1) 수준으로 초가속됩니다
CREATE INDEX idx_reviews_fts ON english_reviews USING GIN (fts_tokens);


-- [샘플 예제 1: 단순 텍스트 쪼개기(어근 단어 추출)의 무용담 검증]
-- 과거형 '-ed' 나 복수형 '-s' 들을 떼고 기본 형태소(Token)로 통일하는 원리 확인
SELECT to_tsvector('english', 'dogs are chasing cats while jumped backwards');
-- 확인 시결과: 'backward', 'cat', 'chase', 'dog', 'jump' 만 남음. (불용어 are, while 은 버려짐)


-- [샘플 예제 2: 쿼리(Query) 포매팅 - 검색어 단일 연산]
-- 배터리 라는 단어가 들어간 게시물 매치 연산 (@@)
SELECT id, author, review_title, review_content 
FROM english_reviews 
WHERE fts_tokens @@ to_tsquery('english', 'battery');


-- [샘플 예제 3: 검색어 다중 OR (|) 논리 연산 모음망]
-- 'battery' 거나, 아니면 'screen' 에 대해 불평/칭찬하는 두 단어 모두 사냥
SELECT id, review_content 
FROM english_reviews 
WHERE fts_tokens @@ to_tsquery('english', 'battery | screen');


-- [샘플 예제 4: 검색어 다중 AND (&) 논리 연산 교집합 검색]
-- 'phone' 과 'hot' 둘 다 본문에 무조건 존재해야만 통과
SELECT author, review_content 
FROM english_reviews 
WHERE fts_tokens @@ to_tsquery('english', 'phone & hot');


-- [샘플 예제 5: NOT (!) 제외 검색 - 부정 필터링]
-- 'phone' 관련된 글을 모두 찾되, 'hot' 열나는 거북한 리뷰는 보기 싫다고 제외하기
SELECT author, review_content 
FROM english_reviews 
WHERE fts_tokens @@ to_tsquery('english', 'phone & !hot');


-- [샘플 예제 6: 형태소 분석기가 "jumped" 와 "jumping" 도 같은 뿌리로 알까? - 시제 무시 검색]
-- 리뷰 원본에는 "jumping"과 "jumps" 라고 쓰여있지만, "jump" 라는 원형 쿼리로 다 잡아들인다.
SELECT author, review_content 
FROM english_reviews 
WHERE fts_tokens @@ to_tsquery('english', 'jump');


-- [샘플 예제 7: 구문을 통째로 묶는 연속 단어 검색 거리 연산자 (<->)]
-- 'battery' 라는 글자가 나오고, 바로 1칸 옆(1어절 차이)에 'life' 가 딱 붙은 상태일 때만 true
SELECT review_content 
FROM english_reviews 
WHERE fts_tokens @@ to_tsquery('english', 'battery <-> life');


-- [샘플 예제 8: ts_rank() 를 활용한 구글 랭킹 서치 가중 조합 쿼리결과 정렬]
-- 본문 길이가 짧은데 내가 검색한 단어('screen')가 많으면 밀도가 꽉 차서 랭크 점수가 높게 나옴
SELECT id, author, 
       ts_rank(fts_tokens, to_tsquery('english', 'screen')) AS relevance_score,
       review_content
FROM english_reviews
WHERE fts_tokens @@ to_tsquery('english', 'screen')
ORDER BY relevance_score DESC;


-- [샘플 예제 9: "The", "And" 같은 쓰레기 불용어(Stopwords)는 무시되는가 맹점 파악]
-- 'is' 란 검색어를 때려봐야 영어 파서 사전에 '불용어'로 등록되어 있어 검색 대상(Token)에 아예 끼워주지 않습니다.
-- (Notice 메세지: text-search query contains only stop words or doesn't contain lexemes)
SELECT to_tsvector('english', 'This is a test') @@ to_tsquery('english', 'is'); -- false 가 떨어집니다.


-- [샘플 예제 10: 언어를 'simple' 로 지정했을 때의 바보같은 한계점 파악]
-- 한국어처럼 형태소 분석 파서('english' 등) 플러그인이 깔려있지 않은 상태를 가정.
-- 언어를 'simple'로 넣으면 "jump"를 "jumps"로 인식하지 못하고 있는 그대로(exact match) 굳어져 버립니다.
SELECT to_tsvector('simple', 'The batteries died quickly') @@ to_tsquery('simple', 'battery'); 
-- english 로 파싱했을 땐 true 지만, 여기선 false 가 떨어집니다. 한국어 분석기가 필요한 이유!

-- =========================================================================
-- [조언] 한국어 문장을 Full-Text Search 하려면, 이 simple 모드의 먹통을 돌파할
-- "은전한닢(morp") 이나 "Pgroonga" 같은 외부 플러그인(파서)을 터미널에서 설치하고
-- to_tsvector('korean', 본문) 형태로 깎아내야 '가방에' -> '가방' 으로 파싱됩니다. 
-- 다음 27강에서 그 세팅을 집중 학습합니다.
-- =========================================================================
