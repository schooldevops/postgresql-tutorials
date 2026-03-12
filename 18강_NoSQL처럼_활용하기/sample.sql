-- =========================================================================
-- [18강] NoSQL처럼 활용하기 (JSON/JSONB) - 실전 샘플 쿼리 10선
-- =========================================================================

-- 개요: 복잡도와 속성 변경이 잦은 이커머스에서 스키마 프리(Schema-Free) NoSQL과
-- PostgreSQL RDBMS 기능을 하이브리드로 접목시킨 특화된 JSON 연산자 및 인덱싱 활용입니다.

-- (사전 준비: 이기종 상품의 변동 제원을 유동적으로 담아줄 특수 테이블 `products_json`)
CREATE TEMP TABLE products_json (
    id SERIAL PRIMARY KEY,
    category VARCHAR(50),
    properties JSONB
);

-- 제각기 다른 뎁스와 노드를 가진 JSON 데이터 구조 주입
INSERT INTO products_json (category, properties) VALUES 
('Laptop', '{"brand": "Apple", "specs": {"cpu": "M2", "ram": "16GB"}, "colors": ["Silver", "Space Gray"]}'),
('Smartphone', '{"brand": "Samsung", "is_5g": true, "colors": ["Black", "White", "Green"]}'),
('Book', '{"author": "John Doe", "pages": 300, "isbn": "978-3-16-148410-0"}');


-- [샘플 예제 1: 단순 1차원 키 탐색 (-> 와 ->>의 차별화 텍스트 반환)]
-- ->> 연산자는 마지막으로 꺼낸 결과에 대해 JSON 껍데기를 버리고 '일반 문자열(TEXT)' 타입으로 캐스팅하여 비교 준비를 마칩니다.
SELECT id, 
       properties->'specs' AS as_json_object, 
       properties->>'brand' AS as_text_value 
FROM products_json;


-- [샘플 예제 2: 2차원(중첩 객체) 밑바닥 찌르기 (Path traversal)]
-- 스펙(specs) 객체 최하단에 위치한 'cpu' 내용물만 뽑지만 값이 없는 스마트폰이나 책은 조용히 무시(NULL)됩니다.
SELECT id, properties->'specs'->>'cpu' AS cpu_spec 
FROM products_json 
WHERE properties->'specs' IS NOT NULL;


-- [샘플 예제 3: 배열(Array) 인덱싱 활용]
-- 0번째 방에 있는 값을 색출하기. 존재하지 않는 배열이면 예외 없이 조용히 NULL이 떨어집니다.
SELECT id, properties->>'brand', properties->'colors'->>0 AS first_color 
FROM products_json;


-- [샘플 예제 4: Contains 연산자(@>)로 완벽히 포함된 문서 콕 집기 (NoSQL의 find)]
-- "brand가 Apple이고, cpu가 M2인 녀석들을 싹 다 가져와라" 라는 깊은 교집합 조건 쿼리 (MongoDB 동일 문법).
SELECT * FROM products_json 
WHERE properties @> '{"brand": "Apple", "specs": {"cpu": "M2"}}';


-- [샘플 예제 5: 키(Key) 존재 여부 물어보기 (? 연산자)]
-- 그냥 "저자는 누구인지 상관 없고, 나한테 책 종류라서 'author' 탭이 채워져 있는 물건만 골라내!" 라고 던집니다.
SELECT * FROM products_json 
WHERE properties ? 'author';


-- [샘플 예제 6: 다중 키(Key) OR 탐색 (?| 연산자)]
-- "is_5g 혹은 pages 두 개 중 하나라도 데이터가 박혀있는 물건들을 걸러낼게!"
SELECT * FROM products_json 
WHERE properties ?| array['is_5g', 'pages'];


-- [샘플 예제 7: JSON 데이터 뼈대 갱신 - 추가 병합 연산자(||)]
-- 스마트폰 항목에 대하여 배터리라는 Key 밸류 세트를 원래 데이터 꼬리에 자연스럽게 흡수·융합(Merge) 시킵니다.
UPDATE products_json 
SET properties = properties || '{"battery_ma": 4000}'::jsonb 
WHERE category = 'Smartphone';


-- [샘플 예제 8: JSON 삭제 연산자 (-)로 골칫거리 속성 잘라내기]
-- 노트북의 컬림 중에서 쓸데없는 'colors' 배열 리스트 가지 전체를 싹둑 잘라 삭제하여 스토리지 다이어트를 시킵니다.
UPDATE products_json 
SET properties = properties - 'colors' 
WHERE category = 'Laptop';


-- [샘플 예제 9: 특정 노드 단 1개만 정교하게 값 고치기 (jsonb_set)]
-- 전체를 갈아 끼우는 게 부담스러울 때, 배열로 Path('{specs, ram}')를 정의해서 목표 지점의 값만 스위치(32GB)시킵니다.
UPDATE products_json 
SET properties = jsonb_set(properties, '{specs, ram}', '"32GB"') 
WHERE category = 'Laptop';


-- [샘플 예제 10: RDBMS 연산자를 흉내내게 만들어주는 JSON 집계 추출 (jsonb_array_elements)]
-- 컬럼 한 칸 안에 욱여넣어진 거대한 '컬러 리스트 배열'을, 
-- JOIN 테이블 처럼 한 행당 1개씩 쪼개(Unnest) 아래위 줄로 와르르 풀어 버립니다(집계와 정렬의 마법).
SELECT p.id, color_item 
FROM products_json p, 
     jsonb_array_elements(p.properties->'colors') AS color_item
WHERE category = 'Smartphone';

-- =========================================================================
-- [조언] JSONB 사용 시 `@>` 연산자 등 포함 여부를 엄청난 속도로 탐색하려면
-- 반드시 테이블 설계 시 'GIN(Generalized Inverted Index)' 역색인을 걸어 주시기 바랍니다.
-- =========================================================================
