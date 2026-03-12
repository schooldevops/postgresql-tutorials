# 26강: 내장 Full-Text Search (전문 검색)

## 개요 
문자열 데이터에서 특정 키워드를 검색할 때, `LIKE '%단어%'` 는 매번 100만 건 테이블을 풀스캔해야 하므로 데이터량이 많아질수록 성능이 급격히 저하됩니다. 이를 막고자 PostgreSQL 내부에 탑재된 구글 검색 엔진 포맷인 **전문 검색(Full-Text Search, FTS)** 의 핵심 기술 2가지, 말뭉치를 잘라내는 `tsvector` 와 검색 질의를 포매팅하는 `tsquery` 의 아키텍처를 학습합니다.

```mermaid
graph LR
    FTS[PostgreSQL Full-Text Search 엔진]
    
    Doc["원본 텍스트: 나는 데이터베이스에서 아름다운 고양이를 찾았다"] --> FTS
    
    FTS -->|1. 형태소 분석 및 불용어 제거| TSVector["tsvector 본문 문맥 조각화: 나 1, 데이터베이스 2, 고양이 3, 찾 4"]
    
    UserQuery["질문: 고양이 데이터베이스"] --> TSQuery["tsquery 질의 변환: 고양이 AND 데이터베이스"]
    
    TSVector -->|"@@" 매칭 연산자 판별| Match{일치 여부 확인 및 랭킹 산출}
    TSQuery --> Match
    
    Match --> Result["결과 반환 및 GIN 역색인 인덱스 스캔"]
```

## 사용형식 / 메뉴얼 

**1. 텍스트를 검색 가능한 말뭉치 배열로 전환 (to_tsvector)**
영문이나 기본 형태로 입력된 문장을 의미 있는 단어(Token/Lexeme) 들로 쪼개고, 복수형(-s)이나 과거형(-ed)의 꼬리를 떼어 원형 단어의 묶음으로 매핑합니다. 
```sql
SELECT to_tsvector('english', 'The quick brown foxes jumped over the lazy dogs');
-- 결과: 'brown':3 'dog':9 'fox':4 'jump':5 'lazi':8 'quick':2
```

**2. 검색 단어를 질의형 규칙으로 전환 (to_tsquery)**
사용자가 입력한 "fox dog" 이라는 텍스트를 검색 엔진이 알아들을 수 있는 교집합(&) 검색 묶음으로 전환합니다. 
```sql
SELECT to_tsquery('english', 'foxes & dogs');
-- 결과: 'fox' & 'dog' 
-- (자기가 알아서 단어 원형을 짜맞춥니다)
```

**3. 검색 결과 매칭 연산자 (@@)**
위의 `vector` 문맥망과 `query` 질문이 서로 뜻이 통하여 부합하는지 여부(True/False)를 일순간에 검증하는 연산자입니다.
```sql
SELECT to_tsvector('english', 'foxes jumped') @@ to_tsquery('english', 'fox');
-- 결과: true 
```

## 샘플예제 5선 

[샘플 예제 1: 단순 LIKE 검색과 FTS 전문 검색의 뉘앙스 차이]
- `LIKE` 에서는 완전히 글자가 스펠링 토씨 하나 안 틀리고 매치되어야 하지만, `to_tsvector` 는 뛰었다(jumped), 뛰는(jumping) 등의 단어 뿌리(Lexeme)를 추적하여 'jump' 로 통일시킵니다.
```sql
-- 영어 기본 형태소 사전 활용 1
SELECT to_tsvector('english', 'I am walking backwards') @@ to_tsquery('english', 'walk'); 
-- 결과: true (walking 을 walk 로 분해하여 일치 성공)
```

[샘플 예제 2: OR (|) 검색과 구조적 질의]
- "고양이가 있거나, 쥐가 있는 글들을 싹 다 돌려줘!" 라고 할 때.
```sql
SELECT title FROM blog_posts 
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'cat | mouse');
```

[샘플 예제 3: NOT (!) 검색으로 배제 필터링]
- "사과에 대한 글인데, 썩은(rotten) 거에 대한 내용은 빼고 가져와!" 라고 논리 연산을 먹일 수 있습니다.
```sql
SELECT title FROM blog_posts 
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'apple & !rotten');
```

[샘플 예제 4: 두 단어가 거리를 두고 얼마나 가까이 나오는가 추적 (<-> 연산)]
- "black" 이란 글자와 "dog" 이란 단어가 정확히 바로 옆에 딱 붙거나 1칸 띄워 연속해서 나오는 구절 추적 기능.
```sql
SELECT to_tsvector('english', 'big black fat dog') @@ to_tsquery('english', 'black <-> dog'); -- false
SELECT to_tsvector('english', 'big black dog') @@ to_tsquery('english', 'black <-> dog'); -- true
```

[샘플 예제 5: 순위를 점수(Rank)로 환산하여 Google-like 정렬하기 (ts_rank)]
- 이 문서의 길이 대비 내가 검색한 단어가 얼마나 핵심적으로 자주 등장하느냐에 따라 0.0 ~ 1.0 의 AI스러운 순위 점수를 뱉어냅니다.
```sql
SELECT title, ts_rank(to_tsvector('english', content), to_tsquery('english', 'apple')) AS score 
FROM blog_posts 
ORDER BY score DESC LIMIT 3;
```

*(영문, 다국어 텍스트 분절 및 랭킹 정렬 테스트 쿼리는 `sample.sql` 을 참조하세요)*

## 주의사항 
- `to_tsvector` 함수는 텍스트를 파싱(Parsing)할 때 CPU 사이클을 은근히 많이 돌아갑니다. 조회(`SELECT`) 할 때마다 매번 수백만 개의 문장(content)을 `to_tsvector` 함수로 감싸서 비교하면 결국 풀스캔 지연 이슈가 터집니다. 반드시 사전에 쪼개진 배열 자체를 저장하는 `tsvector` 전용 물성 컬럼을 테이블에 따로 뚫어놓는 과정(아래 최적화 방안 참조)이 필수입니다.
- **한국어**는 교착어(조사가 붙는 언어)이기 때문에, 기본적으로 내장된 'simple' 이나 'english' 파서를 쓰면 "아버지가" 라는 글자를 "아버지" 와 "가" 로 쪼개지 못하고 헛발질을 합니다. 때문에 27강에서 배우는 외부 한국어 전용 파서 플러그인 장착이 필요합니다.

## 성능 최적화 방안
[GIN (Generalized Inverted Index) 역색인 인덱스 엔진 탑재]
```sql
-- 1. [테이블 재설계] 검색 쿼리를 날릴 때마다 본문(TEXT)을 파싱하지 않도록 
-- 아예 단어 모음집(Lexeme) 전용 열방향 컬럼을 추가합니다.
ALTER TABLE articles ADD COLUMN document_tokens tsvector;

-- 2. [주입] 글이 들어올 때 미리 영구적으로 쪼개어서 저장시켜둡니다. (트리거 활용 가능)
UPDATE articles SET document_tokens = to_tsvector('english', content);

-- 3. [초고속 방탄 엔진 장착] 배열이나 jsonb, tsvector 처럼 다중 값을 갖는 객체는 B-Tree 로 검색이 안됩니다.
-- 책 뒤의 '찾아보기(색인)' 구역처럼, 단어가 앞단에 나열되는 거꾸로 역색인인 GIN 인덱스를 덮어 씌웁니다.
CREATE INDEX idx_articles_fts ON articles USING GIN (document_tokens);

-- 4. [검색 패러다임 변화] 속도가 1/1,000 이하로 단축된 것을 확인합니다.
SELECT title FROM articles WHERE document_tokens @@ to_tsquery('english', 'apple');
```
- **성능 개선이 되는 이유**: 거대한 책 100만 권 속에 '데이터베이스'라는 글자가 어디에 박혀있는지 첫장부터 끝장까지 읽는 것(Sequence Scan)은 미련한 행위입니다. `GIN` (역발상 색인) 인덱스를 치면, 데이터베이스는 내부적으로 `사과 [문서1, 문서99]`, `데이터베이스 [문서3, 문서 501]` 형태로 단어 기준의 목차 카탈로그를 별도 메모리에 생성해 둡니다. 사용자가 '데이터베이스'를 찾는 순간 찰나의 시간에 아이디(문서번호 3번, 501번)만 찾아 테이블 블록 주소로 터널링해 버리므로 CPU 폭주 없이 O(1)에 가까운 정답 추출이 이루어집니다.
