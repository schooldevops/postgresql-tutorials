-- =========================================================================
-- [23강] 벡터 유사도 연산자 (<->, <=>, <#>) - 실전 샘플 쿼리 10선
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- [사전 준비] 시각적 관측이 쉬운 3차원 AI 문서 세트 구축
CREATE TEMP TABLE search_corpus (
    doc_id SERIAL PRIMARY KEY,
    category VARCHAR(20),
    content TEXT,
    embedding VECTOR(3)
);

INSERT INTO search_corpus (category, content, embedding) VALUES 
('ANIMAL', '귀여운 강아지가 뛰놉니다', '[0.9, 0.8, 0.7]'),
('ANIMAL', '고양이가 생선을 먹습니다', '[0.8, 0.9, 0.6]'),
('IT', '최신 노트북 배터리 성능', '[-0.5, -0.6, -0.7]'),
('IT', 'AI 데이터베이스의 벡터 서치', '[-0.6, -0.7, -0.8]'),
('FOOD', '맛있는 사과와 바나나', '[0.1, 0.2, -0.9]');


-- [샘플 예제 1: L2 거리(유클리디안 <->) - 단순 공간 거리 좁히기]
-- IT 주제 벡터인 노트북과 유사한 것을 찾아봅니다.
SELECT content, 
       embedding <-> '[-0.5, -0.5, -0.6]' AS l2_distance
FROM search_corpus
ORDER BY embedding <-> '[-0.5, -0.5, -0.6]' ASC
LIMIT 2;


-- [샘플 예제 2: 코사인 거리(<=>) - 방향과 문맥이 가장 똑같은 것 찾기]
-- 고양이에 관련된 벡터 프롬프트를 던졌다고 가정합니다.
SELECT content, 
       embedding <=> '[0.85, 0.85, 0.65]' AS cosine_distance
FROM search_corpus
ORDER BY embedding <=> '[0.85, 0.85, 0.65]' ASC
LIMIT 2;


-- [샘플 예제 3: 내적 연산자(<#>) - 내적은 곱의 합산인데 왜 음수일까?]
-- pgvector는 무조건 "작은 숫자가 제일 위에(ASC) 오게" 랭킹 엔진을 통합하기 위해
-- 원래 양수로 제일 커야좋은 정답인 내적결과값에 강제로 -1을 곱해서 반환합니다.
SELECT content, 
       (embedding <#> '[0.9, 0.8, 0.7]') AS inner_product_pgvector,
       (embedding <#> '[0.9, 0.8, 0.7]') * -1 AS real_inner_product
FROM search_corpus
ORDER BY embedding <#> '[0.9, 0.8, 0.7]' ASC;


-- [샘플 예제 4: 유사도를 백분율 스코어 퍼센트(%)로 치환하여 환산하기]
-- 코사인 거리는 완전히 똑같으면 0, 반대면 2까지 나옵니다. 1에서 빼주면 유사도 매트릭스가 됨.
SELECT content, 
       ROUND((1 - (embedding <=> '[0.9, 0.8, 0.7]')) * 100, 2) AS match_score_percentage
FROM search_corpus
ORDER BY match_score_percentage DESC -- 점수니까 이때는 높을수록(DESC) 위로 띄움
LIMIT 3;


-- [샘플 예제 5: 쓰레기 문서 걸러내기 (Threshold 컷오프)]
-- 내 질문과 관련이 너무 먼(코사인 유사성이 60% 밑) 생뚱둥맞은 문서는 아예 쳐다보지도 못하게 막습니다.
SELECT content, (1 - (embedding <=> '[0.9, 0.8, 0.7]')) AS sim_score
FROM search_corpus
WHERE (1 - (embedding <=> '[0.9, 0.8, 0.7]')) > 0.60
ORDER BY sim_score DESC;


-- [샘플 예제 6: Metadata 필터링이 결합된 하이브리드 서치]
-- 온 세상 문서를 다 비교하지 않고, `category='IT'` 인 방명록 안에서만 벡터 유사도를 연산! 
-- 풀스캔 오버헤드를 막아주는 실무 RAG 튜닝의 기본기입니다.
SELECT content 
FROM search_corpus
WHERE category = 'IT' 
ORDER BY embedding <=> '[-0.6, -0.6, -0.7]' ASC
LIMIT 1;


-- [샘플 예제 7: 특정 검색어의 묶음에 해당하지 않는 결과 배제하기]
-- IT가 아닌 것들(동물, 밥) 중에서 가장 나와 결맞는 문서를 끄집어냅니다 (부정 스칼라 필터 결합).
SELECT category, content
FROM search_corpus
WHERE category != 'IT'
ORDER BY embedding <=> '[0.1, 0.3, -0.8]' ASC
LIMIT 2;


-- [샘플 예제 8: Subquery에서 찾은 기준점(Anchor)으로 다른 유사 벡터 연쇄 탐색]
-- '고양이' 라는 글자의 벡터 위치를 먼저 찾고, 그 위치와 가장 비슷한 다른 놈을 연쇄적으로 찾기.
WITH target_vec AS (
    SELECT embedding FROM search_corpus WHERE content LIKE '%고양이%' LIMIT 1
)
SELECT content, embedding <=> (SELECT embedding FROM target_vec) AS dist
FROM search_corpus
WHERE content NOT LIKE '%고양이%' -- 고양이 자신은 제외
ORDER BY dist ASC;


-- [샘플 예제 9: 코사인과 내적의 결과가 언제 똑같아지는가? 정규화 증명 쿼리]
-- vector_norm 함수로 길이를 1로 맞춘 정규화 뷰를 선언합니다.
WITH normalized_corpus AS (
    SELECT content, embedding / vector_norm(embedding) as norm_vec FROM search_corpus
)
SELECT content,
       norm_vec <=> '[0.57, 0.57, 0.57]' AS cosine_dist,
       1 - (norm_vec <#> '[0.57, 0.57, 0.57]') * -1 AS inner_prod_sim
FROM normalized_corpus
-- 확인해 보면 코사인 연산 결과와, (사전 정규화된) 내적의 결과 비율이 완전히 동일하게 떨어집니다.
LIMIT 3;


-- [샘플 예제 10: MAX 함수의 역기능 - 가장 멀리 떨어져있는 엉뚱한 대극점(Opposite) 찾기]
-- ASC 오름차순을 DESC로 뒤집으면, 이 문서 공간 안에서 사용자의 질문과 가장 반대편 성향/의미를 가진 아웃라이어를 찾습니다.
SELECT category, content, embedding <=> '[-0.6, -0.7, -0.8]' AS distance
FROM search_corpus
ORDER BY distance DESC  -- DESC: 랭킹 제일 꼴찌, 즉 우주 끝에서 제일 먼 쓰레기 문서를 출력함
LIMIT 1;

-- =========================================================================
-- [조언] 연산자는 DB 내부에서 작동하지만, 엄청난 CPU 사이클을 빨아먹습니다.
-- 무조건 WHERE 절 스칼라 필터(일반 문자열, 지역, 카테고리 등)와 조합해서
-- 옵티마이저가 검사해야 할 벡터 집합의 모수를 사전에 깎아내는 것이 RAG 튜닝의 핵심입니다.
-- =========================================================================
