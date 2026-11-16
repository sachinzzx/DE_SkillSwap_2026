# Phase 2: Schema Design Document

**Team:** T0103 – SkillSwap · **Section:** A · **Database:** PostgreSQL 18

---

## 1. Entity Identification

The seed data export contains **11 CSV files** mapping to **11 database tables**:

| # | Entity | CSV File | Rows | Description |
|---|--------|----------|-----:|-------------|
| 1 | `cities` | cities.csv | 10 | Indian cities where customers and sellers are located |
| 2 | `categories` | categories.csv | 40 | Product category tree (8 top-level, 32 sub-categories) |
| 3 | `sellers` | sellers.csv | 1,500 | Businesses selling on the Amazon marketplace |
| 4 | `products` | products.csv | 30,000 | Product listings by sellers |
| 5 | `customers` | customers.csv | 30,000 | Registered shoppers |
| 6 | `addresses` | addresses.csv | 45,000 | Saved delivery addresses of customers |
| 7 | `orders` | orders.csv | 120,000 | Order headers |
| 8 | `order_items` | order_items.csv | 240,000 | Line items within each order |
| 9 | `returns` | returns.csv | 5,374 | Return requests for order lines |
| 10 | `product_reviews` | product_reviews.csv | 38,662 | Product reviews by customers |
| 11 | `cart_items` | cart_items.csv | 44,998 | Current shopping cart contents |

---

## 2. Data Dictionary

### 2.1 cities

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `city_id` | `INTEGER` | `PRIMARY KEY` | Unique city identifier |
| `city_name` | `VARCHAR(50)` | `NOT NULL` | City name, always present |
| `state` | `VARCHAR(50)` | `NOT NULL` | Indian state name, always present |

### 2.2 categories

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `category_id` | `INTEGER` | `PRIMARY KEY` | Unique category identifier |
| `category_name` | `VARCHAR(100)` | `NOT NULL, UNIQUE` | Category names are unique across the tree |
| `parent_category_id` | `INTEGER` | `FK → categories(category_id), NULL allowed` | NULL for top-level categories (8 rows); points to parent for sub-categories |
| `is_digital` | `BOOLEAN` | `NOT NULL, DEFAULT FALSE` | Whether products in this category are digital (no shipping needed) |

**Design decision:** Self-referential FK for the category tree. `ON DELETE RESTRICT` prevents deleting a parent that has children.

### 2.3 sellers

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `seller_id` | `INTEGER` | `PRIMARY KEY` | Unique seller identifier |
| `business_name` | `VARCHAR(100)` | `NOT NULL` | Always present in data |
| `gstin` | `VARCHAR(15)` | `NOT NULL, UNIQUE, CHECK (length = 15)` | Indian GST Identification Number; 15-char alphanumeric, unique per seller |
| `city_id` | `INTEGER` | `NOT NULL, FK → cities(city_id)` | Seller's registered city |
| `joined_on` | `DATE` | `NOT NULL` | Registration date |
| `seller_rating` | `NUMERIC(2,1)` | `CHECK (seller_rating BETWEEN 1.0 AND 5.0)` | Rating on a 1–5 scale with one decimal |
| `status` | `VARCHAR(10)` | `NOT NULL, CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED'))` | Seller account status |

### 2.4 products

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `product_id` | `INTEGER` | `PRIMARY KEY` | Unique product identifier |
| `asin` | `CHAR(10)` | `NOT NULL, UNIQUE` | Amazon Standard Identification Number; 10-char unique code (e.g., B000001EEF) |
| `seller_id` | `INTEGER` | `NOT NULL, FK → sellers(seller_id)` | The seller who lists this product |
| `category_id` | `INTEGER` | `NOT NULL, FK → categories(category_id)` | Product's sub-category |
| `title` | `VARCHAR(200)` | `NOT NULL` | Product title |
| `brand` | `VARCHAR(50)` | `NOT NULL` | Brand name |
| `mrp` | `NUMERIC(10,2)` | `NOT NULL, CHECK (mrp > 0)` | Maximum Retail Price |
| `price` | `NUMERIC(10,2)` | `NOT NULL, CHECK (price > 0)` | Current selling price |
| `stock_qty` | `INTEGER` | `NOT NULL, CHECK (stock_qty >= 0)` | Available stock; non-negative |
| `is_prime_eligible` | `BOOLEAN` | `NOT NULL, DEFAULT FALSE` | Whether eligible for Prime delivery |
| `avg_rating` | `NUMERIC(2,1)` | `NULL allowed, CHECK (avg_rating BETWEEN 1.0 AND 5.0)` | **Derived column**: NULL when no reviews exist (7,968 products) |
| `review_count` | `INTEGER` | `NOT NULL, DEFAULT 0, CHECK (review_count >= 0)` | **Derived column**: count of reviews |
| `listed_on` | `DATE` | `NOT NULL` | Date the product was first listed |
| `status` | `VARCHAR(12)` | `NOT NULL, CHECK (status IN ('ACTIVE','INACTIVE','OUT_OF_STOCK'))` | Product listing status |

**CHECK:** `price <= mrp` — selling price must not exceed MRP.

### 2.5 customers

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `customer_id` | `INTEGER` | `PRIMARY KEY` | Unique customer identifier |
| `full_name` | `VARCHAR(100)` | `NOT NULL` | Customer's display name |
| `email` | `VARCHAR(100)` | `NOT NULL, UNIQUE` | Email; unique per customer |
| `phone` | `VARCHAR(15)` | `NOT NULL, UNIQUE` | Phone number; unique per customer |
| `city_id` | `INTEGER` | `NOT NULL, FK → cities(city_id)` | Customer's city |
| `signup_date` | `DATE` | `NOT NULL` | Registration date |
| `is_prime` | `BOOLEAN` | `NOT NULL, DEFAULT FALSE` | Prime membership flag |
| `prime_since` | `DATE` | `NULL allowed` | When Prime started; NULL for non-Prime (21,034 customers) |

### 2.6 addresses

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `address_id` | `INTEGER` | `PRIMARY KEY` | Unique address identifier |
| `customer_id` | `INTEGER` | `NOT NULL, FK → customers(customer_id)` | The customer who owns this address |
| `label` | `VARCHAR(5)` | `NOT NULL, CHECK (label IN ('HOME','WORK'))` | Address label |
| `line1` | `VARCHAR(200)` | `NOT NULL` | Street address |
| `city_id` | `INTEGER` | `NOT NULL, FK → cities(city_id)` | City of the address |
| `pincode` | `CHAR(6)` | `NOT NULL, CHECK (pincode ~ '^\d{6}$')` | 6-digit Indian postal code |
| `is_default` | `BOOLEAN` | `NOT NULL, DEFAULT FALSE` | Whether this is the customer's default address |

### 2.7 orders

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `order_id` | `INTEGER` | `PRIMARY KEY` | Unique order identifier |
| `customer_id` | `INTEGER` | `NOT NULL, FK → customers(customer_id)` | The customer who placed the order |
| `address_id` | `INTEGER` | `FK → addresses(address_id), NULL allowed` | Delivery address; NULL for digital-only orders (5,882 orders) |
| `ordered_at` | `TIMESTAMPTZ` | `NOT NULL` | When the order was placed |
| `payment_method` | `VARCHAR(10)` | `NOT NULL, CHECK (payment_method IN ('UPI','CARD','COD','GIFT_CARD','NETBANKING','EMI'))` | Payment method |
| `total_amount` | `NUMERIC(10,2)` | `NOT NULL, CHECK (total_amount >= 0)` | **Derived column**: total order value |
| `status` | `VARCHAR(16)` | `NOT NULL, CHECK (status IN ('PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY','DELIVERED','CANCELLED','RETURNED'))` | Order lifecycle status |
| `shipped_at` | `TIMESTAMPTZ` | `NULL allowed` | When shipped; NULL if not yet shipped (13,926 orders) |
| `delivered_at` | `TIMESTAMPTZ` | `NULL allowed` | When delivered; NULL if not yet delivered (9,354 orders) |

### 2.8 order_items

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `order_id` | `INTEGER` | `NOT NULL, FK → orders(order_id), part of PK` | Parent order |
| `line_no` | `INTEGER` | `NOT NULL, part of PK` | Line number within the order |
| `product_id` | `INTEGER` | `NOT NULL, FK → products(product_id)` | The product ordered |
| `seller_id` | `INTEGER` | `NOT NULL, FK → sellers(seller_id)` | **Denormalized**: seller at time of purchase (snapshot) |
| `quantity` | `INTEGER` | `NOT NULL, CHECK (quantity >= 1)` | Must be at least 1 |
| `unit_price` | `NUMERIC(10,2)` | `NOT NULL, CHECK (unit_price >= 0)` | Price per unit at time of order |

**Primary Key:** `(order_id, line_no)` — composite key.

**Design decision on `seller_id`:** This is intentionally denormalized from `products.seller_id`. It captures the seller who fulfilled the order at the time of purchase. If a product changes seller later, historical orders retain the original seller. The 30 queries (R06, R15, R23) use `order_items.seller_id` directly. Removing it would break those queries.

### 2.9 returns

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `return_id` | `INTEGER` | `PRIMARY KEY` | Unique return identifier |
| `order_id` | `INTEGER` | `NOT NULL, FK composite → order_items(order_id, line_no)` | The order containing the returned item |
| `line_no` | `INTEGER` | `NOT NULL, FK composite → order_items(order_id, line_no)` | The specific line item returned |
| `reason` | `VARCHAR(20)` | `NOT NULL, CHECK (reason IN ('QUALITY_ISSUE','WRONG_ITEM','DAMAGED','SIZE_ISSUE','NOT_AS_DESCRIBED','NO_LONGER_NEEDED'))` | Return reason |
| `requested_at` | `TIMESTAMPTZ` | `NOT NULL` | When the return was requested |
| `status` | `VARCHAR(10)` | `NOT NULL, CHECK (status IN ('REQUESTED','PICKED_UP','REFUNDED','REJECTED'))` | Return processing status |
| `refund_amount` | `NUMERIC(10,2)` | `NULL allowed, CHECK (refund_amount > 0)` | Only populated when status = 'REFUNDED' (3,986 rows have a value; 1,388 are NULL) |

**FK:** `(order_id, line_no)` references `order_items(order_id, line_no)`. `ON DELETE RESTRICT` — cannot delete an order item that has a return.

### 2.10 product_reviews

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `review_id` | `INTEGER` | `PRIMARY KEY` | Unique review identifier |
| `product_id` | `INTEGER` | `NOT NULL, FK → products(product_id)` | The product being reviewed |
| `customer_id` | `INTEGER` | `NOT NULL, FK → customers(customer_id)` | The reviewer |
| `rating` | `SMALLINT` | `NOT NULL, CHECK (rating BETWEEN 1 AND 5)` | 1–5 star rating |
| `title` | `VARCHAR(200)` | `NOT NULL` | Review title |
| `body` | `TEXT` | `NULL allowed` | Review text; sometimes empty |
| `verified_purchase` | `BOOLEAN` | `NOT NULL, DEFAULT FALSE` | Whether the reviewer actually bought the product |
| `helpful_votes` | `INTEGER` | `NOT NULL, DEFAULT 0, CHECK (helpful_votes >= 0)` | Number of "helpful" votes |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | When the review was posted |

### 2.11 cart_items

| Column | Type | Constraints | Why |
|--------|------|-------------|-----|
| `customer_id` | `INTEGER` | `NOT NULL, FK → customers(customer_id), part of PK` | The customer |
| `product_id` | `INTEGER` | `NOT NULL, FK → products(product_id), part of PK` | The product in the cart |
| `quantity` | `INTEGER` | `NOT NULL, CHECK (quantity >= 1)` | Must be at least 1 |
| `added_at` | `TIMESTAMPTZ` | `NOT NULL` | When the item was added |

**Primary Key:** `(customer_id, product_id)` — a customer can have each product in their cart at most once. This matches the `ON CONFLICT (customer_id, product_id) DO NOTHING` in query W04.

---

## 3. Relationships

| Relationship | Type | FK Column(s) | Parent Table | ON DELETE |
|---|---|---|---|---|
| Seller → City | N:1 | `sellers.city_id` | `cities` | RESTRICT |
| Category → Category (self) | N:1 | `categories.parent_category_id` | `categories` | RESTRICT |
| Product → Seller | N:1 | `products.seller_id` | `sellers` | RESTRICT |
| Product → Category | N:1 | `products.category_id` | `categories` | RESTRICT |
| Customer → City | N:1 | `customers.city_id` | `cities` | RESTRICT |
| Address → Customer | N:1 | `addresses.customer_id` | `customers` | CASCADE |
| Address → City | N:1 | `addresses.city_id` | `cities` | RESTRICT |
| Order → Customer | N:1 | `orders.customer_id` | `customers` | RESTRICT |
| Order → Address | N:1 | `orders.address_id` | `addresses` | SET NULL |
| Order Item → Order | N:1 | `order_items.order_id` | `orders` | CASCADE |
| Order Item → Product | N:1 | `order_items.product_id` | `products` | RESTRICT |
| Order Item → Seller | N:1 | `order_items.seller_id` | `sellers` | RESTRICT |
| Return → Order Item | N:1 | `returns.(order_id, line_no)` | `order_items` | RESTRICT |
| Review → Product | N:1 | `product_reviews.product_id` | `products` | CASCADE |
| Review → Customer | N:1 | `product_reviews.customer_id` | `customers` | RESTRICT |
| Cart Item → Customer | N:1 | `cart_items.customer_id` | `customers` | CASCADE |
| Cart Item → Product | N:1 | `cart_items.product_id` | `products` | RESTRICT |

### Cardinality Details

- **City ↔ Seller:** 1:N — one city has many sellers.
- **City ↔ Customer:** 1:N — one city has many customers.
- **City ↔ Address:** 1:N — one city has many addresses.
- **Category ↔ Category:** 1:N — one parent has many children (self-referential hierarchy).
- **Category ↔ Product:** 1:N — one sub-category has many products.
- **Seller ↔ Product:** 1:N — one seller lists many products.
- **Customer ↔ Address:** 1:N — one customer has 1–2 addresses (HOME, WORK).
- **Customer ↔ Order:** 1:N — one customer places many orders.
- **Address ↔ Order:** 1:N — one address is used by many orders (nullable for digital orders).
- **Order ↔ Order Item:** 1:N — one order has 1+ line items (typically 2 in seed data).
- **Product ↔ Order Item:** 1:N — one product appears in many order lines.
- **Order Item ↔ Return:** 1:0..1 — an order line may have at most one return.
- **Product ↔ Review:** 1:N — one product has many reviews.
- **Customer ↔ Review:** 1:N — one customer writes many reviews.
- **Customer ↔ Cart Item:** 1:N — one customer has many cart items.
- **Product ↔ Cart Item:** 1:N — one product appears in many carts.

**Participation:** All participation from child to parent is **total** (every order item references an order, etc.) except `orders.address_id` which is **partial** (NULL for digital orders).

---

## 4. Referential Integrity / ON DELETE Actions — Justification

| FK | ON DELETE | Rationale |
|---|---|---|
| `sellers.city_id → cities` | RESTRICT | Cannot delete a city that has sellers |
| `categories.parent_category_id → categories` | RESTRICT | Cannot delete a category that has sub-categories |
| `products.seller_id → sellers` | RESTRICT | Cannot delete a seller who has products listed |
| `products.category_id → categories` | RESTRICT | Cannot delete a category that has products |
| `customers.city_id → cities` | RESTRICT | Cannot delete a city that has customers |
| `addresses.customer_id → customers` | CASCADE | If a customer is deleted, their addresses are deleted |
| `addresses.city_id → cities` | RESTRICT | Cannot delete a city that has addresses |
| `orders.customer_id → customers` | RESTRICT | Cannot delete a customer who has orders |
| `orders.address_id → addresses` | SET NULL | If an address is deleted, orders keep their record but address becomes NULL |
| `order_items.order_id → orders` | CASCADE | Deleting an order cascades to its line items |
| `order_items.product_id → products` | RESTRICT | Cannot delete a product that was ordered |
| `order_items.seller_id → sellers` | RESTRICT | Cannot delete a seller who fulfilled orders |
| `returns.(order_id,line_no) → order_items` | RESTRICT | Cannot delete an order item that has a return |
| `product_reviews.product_id → products` | CASCADE | Deleting a product cascades to its reviews |
| `product_reviews.customer_id → customers` | RESTRICT | Cannot delete a customer who wrote reviews |
| `cart_items.customer_id → customers` | CASCADE | If a customer is deleted, their cart is cleared |
| `cart_items.product_id → products` | RESTRICT | Cannot delete a product that is in someone's cart |

---

## 5. Candidate Keys and UNIQUE Constraints

| Table | Candidate Key / UNIQUE | Type |
|---|---|---|
| `categories` | `category_name` | Natural key (unique names in tree) |
| `sellers` | `gstin` | Natural key (unique GST number per business) |
| `products` | `asin` | Natural key (unique Amazon product code) |
| `customers` | `email` | Candidate key |
| `customers` | `phone` | Candidate key |

All verified from the seed data: zero duplicates found for each.

---

## 6. CHECK Constraints Summary (≥ 12 required)

| # | Table | Constraint | Expression |
|---|---|---|---|
| C1 | `products` | Price ≤ MRP | `price <= mrp` |
| C2 | `products` | Positive MRP | `mrp > 0` |
| C3 | `products` | Positive price | `price > 0` |
| C4 | `products` | Non-negative stock | `stock_qty >= 0` |
| C5 | `products` | Valid status | `status IN ('ACTIVE','INACTIVE','OUT_OF_STOCK')` |
| C6 | `products` | Valid avg_rating | `avg_rating BETWEEN 1.0 AND 5.0` |
| C7 | `products` | Non-negative review count | `review_count >= 0` |
| C8 | `order_items` | Positive quantity | `quantity >= 1` |
| C9 | `order_items` | Non-negative unit price | `unit_price >= 0` |
| C10 | `orders` | Non-negative total | `total_amount >= 0` |
| C11 | `orders` | Valid status | `status IN ('PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY','DELIVERED','CANCELLED','RETURNED')` |
| C12 | `orders` | Valid payment method | `payment_method IN ('UPI','CARD','COD','GIFT_CARD','NETBANKING','EMI')` |
| C13 | `returns` | Valid reason | `reason IN ('QUALITY_ISSUE','WRONG_ITEM','DAMAGED','SIZE_ISSUE','NOT_AS_DESCRIBED','NO_LONGER_NEEDED')` |
| C14 | `returns` | Valid status | `status IN ('REQUESTED','PICKED_UP','REFUNDED','REJECTED')` |
| C15 | `returns` | Positive refund | `refund_amount > 0` (when not NULL) |
| C16 | `product_reviews` | Valid rating | `rating BETWEEN 1 AND 5` |
| C17 | `product_reviews` | Non-negative votes | `helpful_votes >= 0` |
| C18 | `cart_items` | Positive quantity | `quantity >= 1` |
| C19 | `sellers` | Valid status | `status IN ('ACTIVE','SUSPENDED','CLOSED')` |
| C20 | `sellers` | GSTIN length | `length(gstin) = 15` |
| C21 | `sellers` | Valid rating | `seller_rating BETWEEN 1.0 AND 5.0` |
| C22 | `addresses` | Valid label | `label IN ('HOME','WORK')` |
| C23 | `addresses` | Valid pincode | `pincode ~ '^\d{6}$'` |

---

## 7. Functional Dependencies & Normal Form Analysis

### 7.1 cities
**FDs:** `city_id → city_name, state`
**Candidate key:** `{city_id}`
**Normal form:** BCNF ✓ (single determinant is the key)

### 7.2 categories
**FDs:** `category_id → category_name, parent_category_id, is_digital`; `category_name → category_id, parent_category_id, is_digital`
**Candidate keys:** `{category_id}`, `{category_name}`
**Normal form:** BCNF ✓ (both determinants are candidate keys)

### 7.3 sellers
**FDs:** `seller_id → business_name, gstin, city_id, joined_on, seller_rating, status`; `gstin → seller_id, business_name, city_id, joined_on, seller_rating, status`
**Candidate keys:** `{seller_id}`, `{gstin}`
**Normal form:** BCNF ✓

### 7.4 products
**FDs:** `product_id → asin, seller_id, category_id, title, brand, mrp, price, stock_qty, is_prime_eligible, avg_rating, review_count, listed_on, status`; `asin → product_id, ...`
**Candidate keys:** `{product_id}`, `{asin}`
**Derived/redundant columns:**
- `avg_rating` = AVG of `product_reviews.rating` WHERE `product_id = X`
- `review_count` = COUNT of `product_reviews` WHERE `product_id = X`

These are denormalized for performance. Queries R01, R02, R14 use `avg_rating` and `review_count` directly. Recomputing them on every product page load would be expensive. **Justified denormalization.**

**Normal form:** BCNF ✓ (ignoring the derived columns, which are a controlled redundancy documented here)

### 7.5 customers
**FDs:** `customer_id → full_name, email, phone, city_id, signup_date, is_prime, prime_since`; `email → customer_id, ...`; `phone → customer_id, ...`
**Candidate keys:** `{customer_id}`, `{email}`, `{phone}`
**Normal form:** BCNF ✓

### 7.6 addresses
**FDs:** `address_id → customer_id, label, line1, city_id, pincode, is_default`
**Candidate key:** `{address_id}`
**Normal form:** BCNF ✓

### 7.7 orders
**FDs:** `order_id → customer_id, address_id, ordered_at, payment_method, total_amount, status, shipped_at, delivered_at`
**Candidate key:** `{order_id}`
**Derived column:** `total_amount` = SUM of `order_items.quantity * order_items.unit_price` for this order.
This is denormalized for performance. Recomputing it requires joining to order_items. Many queries (R04, R09, R18, R22) use `total_amount` directly. **Justified denormalization.**
**Normal form:** BCNF ✓

### 7.8 order_items
**FDs:** `(order_id, line_no) → product_id, seller_id, quantity, unit_price`
**Candidate key:** `{order_id, line_no}`
**Derived column:** `seller_id` could be derived from `products.seller_id`, but it captures the seller at purchase time (a snapshot). Also required by queries R06, R15, R23. **Justified denormalization.**
**Normal form:** BCNF ✓

### 7.9 returns
**FDs:** `return_id → order_id, line_no, reason, requested_at, status, refund_amount`
**Candidate key:** `{return_id}`
**Normal form:** BCNF ✓

### 7.10 product_reviews
**FDs:** `review_id → product_id, customer_id, rating, title, body, verified_purchase, helpful_votes, created_at`
**Candidate key:** `{review_id}`
**Normal form:** BCNF ✓

### 7.11 cart_items
**FDs:** `(customer_id, product_id) → quantity, added_at`
**Candidate key:** `{customer_id, product_id}`
**Normal form:** BCNF ✓

### Summary
**All 11 tables are in BCNF.** Three instances of intentional, documented denormalization exist:
1. `products.avg_rating` and `products.review_count` (derived from `product_reviews`)
2. `orders.total_amount` (derived from `order_items`)
3. `order_items.seller_id` (snapshot from `products.seller_id`)

---

## 8. ER Diagram

The ER diagram is at [`diagrams/er_diagram.png`](../diagrams/er_diagram.png).

Mermaid source (for editability):

```mermaid
erDiagram
    cities {
        INTEGER city_id PK
        VARCHAR city_name
        VARCHAR state
    }
    categories {
        INTEGER category_id PK
        VARCHAR category_name UK
        INTEGER parent_category_id FK
        BOOLEAN is_digital
    }
    sellers {
        INTEGER seller_id PK
        VARCHAR business_name
        VARCHAR gstin UK
        INTEGER city_id FK
        DATE joined_on
        NUMERIC seller_rating
        VARCHAR status
    }
    products {
        INTEGER product_id PK
        CHAR asin UK
        INTEGER seller_id FK
        INTEGER category_id FK
        VARCHAR title
        VARCHAR brand
        NUMERIC mrp
        NUMERIC price
        INTEGER stock_qty
        BOOLEAN is_prime_eligible
        NUMERIC avg_rating
        INTEGER review_count
        DATE listed_on
        VARCHAR status
    }
    customers {
        INTEGER customer_id PK
        VARCHAR full_name
        VARCHAR email UK
        VARCHAR phone UK
        INTEGER city_id FK
        DATE signup_date
        BOOLEAN is_prime
        DATE prime_since
    }
    addresses {
        INTEGER address_id PK
        INTEGER customer_id FK
        VARCHAR label
        VARCHAR line1
        INTEGER city_id FK
        CHAR pincode
        BOOLEAN is_default
    }
    orders {
        INTEGER order_id PK
        INTEGER customer_id FK
        INTEGER address_id FK
        TIMESTAMPTZ ordered_at
        VARCHAR payment_method
        NUMERIC total_amount
        VARCHAR status
        TIMESTAMPTZ shipped_at
        TIMESTAMPTZ delivered_at
    }
    order_items {
        INTEGER order_id PK_FK
        INTEGER line_no PK
        INTEGER product_id FK
        INTEGER seller_id FK
        INTEGER quantity
        NUMERIC unit_price
    }
    returns {
        INTEGER return_id PK
        INTEGER order_id FK
        INTEGER line_no FK
        VARCHAR reason
        TIMESTAMPTZ requested_at
        VARCHAR status
        NUMERIC refund_amount
    }
    product_reviews {
        INTEGER review_id PK
        INTEGER product_id FK
        INTEGER customer_id FK
        SMALLINT rating
        VARCHAR title
        TEXT body
        BOOLEAN verified_purchase
        INTEGER helpful_votes
        TIMESTAMPTZ created_at
    }
    cart_items {
        INTEGER customer_id PK_FK
        INTEGER product_id PK_FK
        INTEGER quantity
        TIMESTAMPTZ added_at
    }

    cities ||--o{ sellers : "city_id"
    cities ||--o{ customers : "city_id"
    cities ||--o{ addresses : "city_id"
    categories ||--o{ categories : "parent_category_id"
    categories ||--o{ products : "category_id"
    sellers ||--o{ products : "seller_id"
    sellers ||--o{ order_items : "seller_id"
    customers ||--o{ addresses : "customer_id"
    customers ||--o{ orders : "customer_id"
    customers ||--o{ product_reviews : "customer_id"
    customers ||--o{ cart_items : "customer_id"
    addresses ||--o{ orders : "address_id"
    products ||--o{ order_items : "product_id"
    products ||--o{ product_reviews : "product_id"
    products ||--o{ cart_items : "product_id"
    orders ||--o{ order_items : "order_id"
    order_items ||--o| returns : "order_id, line_no"
```

---

## 9. Design Decisions

### 9.1 Composite Keys
- **`order_items(order_id, line_no)`**: Natural composite key. Each order has sequentially numbered lines.
- **`cart_items(customer_id, product_id)`**: Natural composite key. A customer can have each product in their cart once. Required by W04's `ON CONFLICT` clause.

### 9.2 Surrogate vs Natural Keys
All tables use **integer surrogate PKs** (auto-numbered by the data export) except `cart_items` which uses a natural composite key. The surrogate keys are lightweight for joins and indexing.

### 9.3 Nullable Attributes
| Column | When NULL | Why |
|---|---|---|
| `categories.parent_category_id` | Top-level categories (8 rows) | No parent to point to |
| `products.avg_rating` | Products with 0 reviews (7,968) | No rating to average |
| `customers.prime_since` | Non-Prime customers (21,034) | Not applicable |
| `orders.address_id` | Digital-only orders (5,882) | No physical delivery needed |
| `orders.shipped_at` | Not-yet-shipped orders (13,926) | Event hasn't occurred |
| `orders.delivered_at` | Not-yet-delivered orders (9,354) | Event hasn't occurred |
| `returns.refund_amount` | Non-refunded returns (1,388) | Refund not processed |
| `product_reviews.body` | Reviews with no text | Optional field |

### 9.4 Table Creation Order (Dependency-Safe)
1. `cities` (no FK dependencies)
2. `categories` (self-ref FK, but parent rows inserted first by data ordering)
3. `sellers` (depends on `cities`)
4. `products` (depends on `sellers`, `categories`)
5. `customers` (depends on `cities`)
6. `addresses` (depends on `customers`, `cities`)
7. `orders` (depends on `customers`, `addresses`)
8. `order_items` (depends on `orders`, `products`, `sellers`)
9. `returns` (depends on `order_items`)
10. `product_reviews` (depends on `products`, `customers`)
11. `cart_items` (depends on `customers`, `products`)

### 9.5 Schema Namespace
All tables are created under `CREATE SCHEMA amazon;` with `SET search_path TO amazon;` as required by the project specification and the workload queries.

---

## 10. Integrity Check Results

All three integrity checks were executed against PostgreSQL 18.4 after loading all 555,584 records:

### Check 1: `order_items.seller_id` matches `products.seller_id`
```sql
SELECT count(*) AS mismatch_count
FROM amazon.order_items oi
JOIN amazon.products p ON p.product_id = oi.product_id
WHERE oi.seller_id <> p.seller_id;
```
**Result:**
```
 mismatch_count 
----------------
              0
(1 row)
```
**Conclusion:** Passed. Every historical order line's seller matches the current product listing seller across all 240,000 order item rows.

### Check 2: Every customer has exactly one default address
```sql
SELECT customer_id, count(*) AS default_count
FROM amazon.addresses
WHERE is_default = true
GROUP BY customer_id
HAVING count(*) <> 1;
```
**Result:**
```
 customer_id | default_count 
-------------+---------------
(0 rows)
```
**Conclusion:** Passed. Every one of the 30,000 customers has exactly one default address.

### Check 3: Orders without an address contain only digital products
```sql
SELECT o.order_id
FROM amazon.orders o
WHERE o.address_id IS NULL
AND EXISTS (
    SELECT 1 FROM amazon.order_items oi
    JOIN amazon.products p ON p.product_id = oi.product_id
    JOIN amazon.categories c ON c.category_id = p.category_id
    WHERE oi.order_id = o.order_id AND c.is_digital = false
);
```
**Result:**
```
 order_id 
----------
(0 rows)
```
**Conclusion:** Passed. Exactly 5,882 orders have `address_id IS NULL`, and 100% of these orders contain exclusively digital products (E-Books and Gift Cards from digital categories). Physical orders invariably have a non-null delivery address.

---

## 11. Data Problems Found

1. **R13 NULL bug (P6):** Query R13 uses `NOT IN (SELECT o.address_id FROM orders o)`. Since 5,882 orders have `address_id = NULL`, the subquery returns NULLs. In SQL's three-valued logic, `x NOT IN (…, NULL, …)` never evaluates to TRUE, so R13 returns **zero rows** — the report falsely claims "no address is unused." The fix (for Phase 4) is to use `NOT EXISTS` or add `WHERE o.address_id IS NOT NULL` in the subquery.

2. **Derived columns:** `products.avg_rating`, `products.review_count`, and `orders.total_amount` are denormalized. We keep them for query compatibility but document that they could drift from the source-of-truth tables (`product_reviews`, `order_items`).

