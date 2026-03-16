# 34강: 쇼핑몰 핵심 비즈니스 로직 쿼리 구현

## 개요 
이번 34강에서는 앞서 물리적으로 구축한 테이블들을 활용하여 쇼핑몰의 생명인 핵심 비즈니스 로직들을 DML로 실습합니다. 장바구니에 아이템을 담을 때 덮어쓰거나(UPSERT) 더하는 작업, 주문 접수 시 재고를 감소시키며 동시성을 제어하는 `Pessimistic Locking` 락 기법 등을 직접 다룹니다.

## 사용형식 / 메뉴얼 
- 장바구니 UPSERT: `INSERT INTO ... ON CONFLICT (A, B) DO UPDATE` 구문을 활용해 수량을 +1 혹은 덮어씁니다.
- 재고 감소: 트랜잭션 도중 다른 프로세스의 수정을 막기 위해 `SELECT ... FOR UPDATE`를 사용합니다.

## 샘플예제 5선 

[샘플 예제 첫번째] 장바구니 상품 담기 (UPSERT)
```sql
INSERT INTO cart_items (cart_id, product_id, option_id, quantity)
VALUES ('cart-uuid', 'prod-uuid', 'opt-uuid', 1)
ON CONFLICT (cart_id, product_id, option_id)
DO UPDATE SET quantity = cart_items.quantity + 1;
```
- 샘플 예제 설명: 이미 장바구니에 동일한 옵션의 상품이 존재한다면 `INSERT` 대신 기존 수량인 `quantity`를 1 증가시킵니다.

[샘플 예제 두번째] 가입 및 배송지 다중 입력 (CTE 및 RETURNING 활용)
```sql
WITH new_user AS (
    INSERT INTO users (email, password_hash)
    VALUES ('new@mail.com', 'hash_abc')
    RETURNING user_id
)
INSERT INTO addresses (user_id, address_line, is_default)
SELECT user_id, '서울시 서초구', true
FROM new_user;
```
- 샘플 예제 설명: 회원 가입과 기본 배송지 입력을 단일 쿼리-가상 테이블(CTE)로 묶어 네트워크 왕복 비용(Round Trip)을 없앴습니다.

[샘플 예제 세번째] 하위 카테고리 품목 순회 (Ltree)
```sql
SELECT p.title, p.price, c.name
FROM products p
JOIN categories c ON p.category_id = c.category_id
WHERE c.path <@ '1.1'; -- 1.1 하위 노드 상품 모두 검색
```
- 샘플 예제 설명: ltree의 `<@` 연산자를 활용하여 상위 의류 카테고리를 눌렀을 때 하위 남성의류, 자켓 상품이 모두 노출되게 합니다.

[샘플 예제 네번째] 결제 시 상품 재고 차감 (Pessimistic Lock)
```sql
BEGIN;
SELECT stock_quantity 
FROM inventory 
WHERE option_id = 'opt-uuid' FOR UPDATE;

UPDATE inventory 
SET stock_quantity = stock_quantity - 2, updated_at = NOW()
WHERE option_id = 'opt-uuid' AND stock_quantity >= 2;
COMMIT;
```
- 샘플 예제 설명: 락을 통해 다른 트랜잭션이 선점하지 못하게 막고, 재고가 요청 수량(2)보다 같거나 많을 때만 UPDATE가 적용되게 하여 음수 재고 오류(초과 구매)를 원천 차단합니다.

[샘플 예제 다섯번째] JSONB 동적 속성 필터링 (다중 조건)
```sql
SELECT title, price, attributes
FROM products
WHERE attributes @> '{"color": "RED", "size": "L"}';
```
- 샘플 예제 설명: `JSONB` 형식으로 저장된 옵션에 대해 `@>`(포함 연산자)를 활용하여 색상이 빨강이고 L사이즈인 상품만 필터링합니다. GIN 인덱스를 역으로 탑니다.

## 주의사항 
- `FOR UPDATE` 동시성 락을 걸 때는 테이블 전체 락(Table Lock)으로 승격될 위험성이나 데드락(Deadlock)이 발생하는지 교차 검증해야합니다. 가급적 짧은 트랜잭션을 유지하세요.
- CTE를 활용한 다중 `INSERT/RETURNING`은 매우 빠르고 효율적이지만 데이터 검증(Validation)은 애플리케이션 레벨에서 한 번 더 처리하는 것이 좋습니다.

## 성능 최적화 방안
[락 경합 시간 최소화 하기]
- 성능 개선이 되는 이유: 트랜잭션의 시작(`BEGIN`)과 끝(`COMMIT`) 사이엔 무거운 배치, 이메일 발송 등 외부 I/O 로직을 절대 포함시키면 안됩니다. DB 연산만을 수행해야 데드락 확률을 줄일 수 있습니다.
