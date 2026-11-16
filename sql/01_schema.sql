-- =====================================================================
-- Amazon Online Shopping Database — Schema Definition
-- Team T0103 (SkillSwap) · Section A · PostgreSQL 18
--
-- Run this file top-to-bottom on an empty database:
--   psql -d <database> -f sql/01_schema.sql
--
-- Tables are created in dependency-safe order (parents before children).
-- Only constraints are created here: PK, FK, UNIQUE, NOT NULL, CHECK.
-- No additional indexes are created in this phase.
-- =====================================================================

-- Create the schema namespace
DROP SCHEMA IF EXISTS amazon CASCADE;
CREATE SCHEMA amazon;
SET search_path TO amazon;

-- =====================================================================
-- 1. cities — lookup table for Indian cities
-- =====================================================================
CREATE TABLE cities (
    city_id     INTEGER       PRIMARY KEY,
    city_name   VARCHAR(50)   NOT NULL,
    state       VARCHAR(50)   NOT NULL
);

-- =====================================================================
-- 2. categories — hierarchical product category tree (self-referential)
--    8 top-level categories (parent_category_id IS NULL)
--    32 sub-categories (parent_category_id references a top-level row)
-- =====================================================================
CREATE TABLE categories (
    category_id         INTEGER       PRIMARY KEY,
    category_name       VARCHAR(100)  NOT NULL UNIQUE,
    parent_category_id  INTEGER       REFERENCES categories(category_id) ON DELETE RESTRICT,
    is_digital          BOOLEAN       NOT NULL DEFAULT FALSE
);
-- parent_category_id is NULL for top-level categories

-- =====================================================================
-- 3. sellers — businesses selling on the marketplace
-- =====================================================================
CREATE TABLE sellers (
    seller_id      INTEGER        PRIMARY KEY,
    business_name  VARCHAR(100)   NOT NULL,
    gstin          VARCHAR(15)    NOT NULL UNIQUE,
    city_id        INTEGER        NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    joined_on      DATE           NOT NULL,
    seller_rating  NUMERIC(2,1)   CHECK (seller_rating BETWEEN 1.0 AND 5.0),
    status         VARCHAR(10)    NOT NULL CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED')),

    -- GSTIN is a 15-character alphanumeric code
    CONSTRAINT chk_sellers_gstin_len CHECK (length(gstin) = 15)
);

-- =====================================================================
-- 4. products — product listings
--    avg_rating and review_count are denormalized from product_reviews
--    (kept for query performance; documented trade-off)
-- =====================================================================
CREATE TABLE products (
    product_id        INTEGER        PRIMARY KEY,
    asin              CHAR(10)       NOT NULL UNIQUE,
    seller_id         INTEGER        NOT NULL REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    category_id       INTEGER        NOT NULL REFERENCES categories(category_id) ON DELETE RESTRICT,
    title             VARCHAR(200)   NOT NULL,
    brand             VARCHAR(50)    NOT NULL,
    mrp               NUMERIC(10,2)  NOT NULL CHECK (mrp > 0),
    price             NUMERIC(10,2)  NOT NULL CHECK (price > 0),
    stock_qty         INTEGER        NOT NULL CHECK (stock_qty >= 0),
    is_prime_eligible BOOLEAN        NOT NULL DEFAULT FALSE,
    avg_rating        NUMERIC(2,1)   CHECK (avg_rating BETWEEN 1.0 AND 5.0),
    -- avg_rating is NULL when the product has zero reviews (7,968 products)
    review_count      INTEGER        NOT NULL DEFAULT 0 CHECK (review_count >= 0),
    listed_on         DATE           NOT NULL,
    status            VARCHAR(12)    NOT NULL CHECK (status IN ('ACTIVE', 'INACTIVE', 'OUT_OF_STOCK')),

    -- Selling price must not exceed MRP
    CONSTRAINT chk_products_price_le_mrp CHECK (price <= mrp)
);

-- =====================================================================
-- 5. customers — registered shoppers
--    prime_since is NULL for non-Prime customers (21,034 rows)
-- =====================================================================
CREATE TABLE customers (
    customer_id  INTEGER        PRIMARY KEY,
    full_name    VARCHAR(100)   NOT NULL,
    email        VARCHAR(100)   NOT NULL UNIQUE,
    phone        VARCHAR(15)    NOT NULL UNIQUE,
    city_id      INTEGER        NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    signup_date  DATE           NOT NULL,
    is_prime     BOOLEAN        NOT NULL DEFAULT FALSE,
    prime_since  DATE
    -- prime_since should be NOT NULL when is_prime = true, and NULL otherwise.
    -- A CHECK like (is_prime = false OR prime_since IS NOT NULL) is desirable
    -- but we omit it here to avoid blocking data load if edge cases exist.
);

-- =====================================================================
-- 6. addresses — saved delivery addresses of customers
--    Each customer has 1 HOME and optionally 1 WORK address
--    is_default marks the primary address
-- =====================================================================
CREATE TABLE addresses (
    address_id   INTEGER        PRIMARY KEY,
    customer_id  INTEGER        NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    label        VARCHAR(5)     NOT NULL CHECK (label IN ('HOME', 'WORK')),
    line1        VARCHAR(200)   NOT NULL,
    city_id      INTEGER        NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    pincode      CHAR(6)        NOT NULL CHECK (pincode ~ '^\d{6}$'),
    is_default   BOOLEAN        NOT NULL DEFAULT FALSE
);

-- =====================================================================
-- 7. orders — order headers
--    address_id is NULL for digital-only orders (5,882 orders)
--    shipped_at is NULL if the order has not been shipped yet
--    delivered_at is NULL if the order has not been delivered yet
--    total_amount is denormalized from SUM(order_items.quantity * unit_price)
-- =====================================================================
CREATE TABLE orders (
    order_id        INTEGER        PRIMARY KEY,
    customer_id     INTEGER        NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    address_id      INTEGER        REFERENCES addresses(address_id) ON DELETE SET NULL,
    ordered_at      TIMESTAMPTZ    NOT NULL,
    payment_method  VARCHAR(10)    NOT NULL CHECK (payment_method IN ('UPI', 'CARD', 'COD', 'GIFT_CARD', 'NETBANKING', 'EMI')),
    total_amount    NUMERIC(10,2)  NOT NULL CHECK (total_amount >= 0),
    status          VARCHAR(16)    NOT NULL CHECK (status IN ('PLACED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'RETURNED')),
    shipped_at      TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ
);

-- =====================================================================
-- 8. order_items — line items within each order
--    Composite PK: (order_id, line_no)
--    seller_id is denormalized from products.seller_id (snapshot at
--    purchase time); required by queries R06, R15, R23
-- =====================================================================
CREATE TABLE order_items (
    order_id    INTEGER        NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    line_no     INTEGER        NOT NULL,
    product_id  INTEGER        NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    seller_id   INTEGER        NOT NULL REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    quantity    INTEGER        NOT NULL CHECK (quantity >= 1),
    unit_price  NUMERIC(10,2)  NOT NULL CHECK (unit_price >= 0),

    PRIMARY KEY (order_id, line_no)
);

-- =====================================================================
-- 9. returns — return requests for order lines
--    FK references order_items composite key (order_id, line_no)
--    refund_amount is NULL when the return is not yet refunded
-- =====================================================================
CREATE TABLE returns (
    return_id      INTEGER        PRIMARY KEY,
    order_id       INTEGER        NOT NULL,
    line_no        INTEGER        NOT NULL,
    reason         VARCHAR(20)    NOT NULL CHECK (reason IN ('QUALITY_ISSUE', 'WRONG_ITEM', 'DAMAGED', 'SIZE_ISSUE', 'NOT_AS_DESCRIBED', 'NO_LONGER_NEEDED')),
    requested_at   TIMESTAMPTZ    NOT NULL,
    status         VARCHAR(10)    NOT NULL CHECK (status IN ('REQUESTED', 'PICKED_UP', 'REFUNDED', 'REJECTED')),
    refund_amount  NUMERIC(10,2)  CHECK (refund_amount > 0),

    CONSTRAINT fk_returns_order_item
        FOREIGN KEY (order_id, line_no)
        REFERENCES order_items(order_id, line_no)
        ON DELETE RESTRICT
);

-- =====================================================================
-- 10. product_reviews — customer reviews for products
--     body can be NULL (review with no text)
-- =====================================================================
CREATE TABLE product_reviews (
    review_id          INTEGER        PRIMARY KEY,
    product_id         INTEGER        NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    customer_id        INTEGER        NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    rating             SMALLINT       NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title              VARCHAR(200)   NOT NULL,
    body               TEXT,
    verified_purchase  BOOLEAN        NOT NULL DEFAULT FALSE,
    helpful_votes      INTEGER        NOT NULL DEFAULT 0 CHECK (helpful_votes >= 0),
    created_at         TIMESTAMPTZ    NOT NULL
);

-- =====================================================================
-- 11. cart_items — current shopping cart contents
--     Composite PK: (customer_id, product_id)
--     A customer can have each product in their cart at most once.
--     W04 uses ON CONFLICT (customer_id, product_id) DO NOTHING.
-- =====================================================================
CREATE TABLE cart_items (
    customer_id  INTEGER        NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    product_id   INTEGER        NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity     INTEGER        NOT NULL CHECK (quantity >= 1),
    added_at     TIMESTAMPTZ    NOT NULL,

    PRIMARY KEY (customer_id, product_id)
);

-- =====================================================================
-- End of schema definition
-- PostgreSQL automatically creates indexes for PRIMARY KEY and UNIQUE
-- constraints. No additional indexes are created in this phase.
-- =====================================================================

