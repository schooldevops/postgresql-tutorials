# 32강: 회원 및 카테고리/상품 테이블 물리적 구축

## 개요 
이번 32강에서는 논리적으로 설계한 ERD를 바탕으로 사용자(회원)를 관리하는 테이블과 카테고리 계층, 그리고 상품 및 동적 옵션(JSONB)을 저장하기 위한 물리적 테이블을 DDL로 구성합니다. Ltree와 UUID, 그리고 JSONB 인덱싱 기법이 주요 학습 테마입니다.

## 사용형식 / 메뉴얼 
- UUID v4 확장을 통해 고유 식별자를 생성합니다.
- `ltree` 확장을 사용해 카테고리의 뎁스를 무한으로 늘릴 수 있게 경로(path)를 저장합니다.
- JSONB는 다양한 상품 속성을 스키마리스 형태로 저장하게 도와주며 GIN 인덱스를 필히 사용해야 합니다.

## 샘플예제 5선 

[샘플 예제 첫번째] uuid-ossp 확장과 회원 테이블 생성
```sql
-- 1. UUID 확장을 설치하고 테이블을 생성합니다.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'CUSTOMER',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```
- 샘플 예제 설명: UUID 확장을 사용하여 유저 아이디를 생성하고, 타임존이 포함된 날짜형식을 사용했습니다.

[샘플 예제 두번째] 다중 배송지 처리
```sql
-- 2. 회원의 배송지를 관리하는 테이블입니다.
CREATE TABLE addresses (
    address_id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    address_line TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false
);

CREATE UNIQUE INDEX unq_user_default_addr 
ON addresses(user_id) 
WHERE is_default = true;
```
- 샘플 예제 설명: 회원은 여러 배송지를 갖지만 기본 배송지(`is_default = true`)는 하나만 존재해야 함을 부분 인덱스(Partial Index)를 통해 강제합니다.

[샘플 예제 세번째] Ltree 카테고리 테이블
```sql
-- 3. 계층형 카테고리를 저장하는 모델
CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    path ltree NOT NULL
);

CREATE INDEX idx_categories_path ON categories USING GIST (path);
```
- 샘플 예제 설명: GIST 인덱스를 사용하여 `path` 값을 통한 하위 카테고리 검색 속도를 비약적으로 높입니다.

[샘플 예제 네번째] 상품 테이블 및 JSONB 제약
```sql
-- 4. 상품과 JSONB 동적 속성 관리 테이블 구축
CREATE TABLE products (
    product_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id INT REFERENCES categories(category_id),
    title VARCHAR(200) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    attributes JSONB DEFAULT '{}'::jsonb
);
```
- 샘플 예제 설명: `price`는 부동소수점 오차를 막기위해 `NUMERIC`을 사용하였으며 동적인 속성은 `JSONB`로 관리합니다.

[샘플 예제 다섯번째] JSONB GIN 인덱스 추가
```sql
-- 5. 속성 검색을 위한 GIN 인덱스 구성
CREATE INDEX idx_products_attributes ON products USING GIN (attributes);
```
- 샘플 예제 설명: attributes 필드에 GIN 인덱스를 걸어 차후 키-값 필터링 쿼리가 B-Tree를 타지 않게 최적화합니다.

## 주의사항 
- Ltree에서 지원하는 문자열은 알파벳, 숫자, 언더스코어로 제한됩니다. 카테고리 한글명은 별도의 `name` 칼럼에 두고 ID 패턴을 `path`(예: 1.10.100)로 사용해야 합니다.
- 삭제 정책 시 `ON DELETE CASCADE`를 무분별하게 사용하면 연쇄 삭제로 부하가 생길 수 있습니다. 현업에서는 `deleted_at` 등을 사용해 소프트 딜리트(Soft Delete)를 많이 적용합니다.

## 성능 최적화 방안
[부분 인덱스를 활용한 검색 최적화]
```sql
-- 기본 배송지만 빠르게 찾기 위한 인덱스스
CREATE INDEX idx_default_address \nON addresses(user_id) WHERE is_default = true;
```
- 성능 개선이 되는 이유: 특정 조건이 들어간 레코드만 인덱싱하므로 인덱스 크기가 대폭 축소되어 조회 성능이 빨라집니다.
