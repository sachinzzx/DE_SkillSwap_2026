-- =====================================================================
-- Amazon Online Shopping Database — Workload Indexes (CP3 Optimization)
-- Team: T0103 (SkillSwap) · Section: A · PostgreSQL 18
--
-- This script creates carefully targeted indexes designed to resolve
-- sequential scan and nested loop bottlenecks identified during CP2
-- baseline benchmarking.
--
-- GUIDELINES APPLIED:
-- 1. B-tree composite column order: Equality columns first, then range/sort.
-- 2. Partial indexes: Limit index size to active/filtered rows.
-- 3. Covering indexes: INCLUDE (...) to enable Index-Only Scans.
-- 4. Expression indexes: Index exact expressions evaluated in WHERE/ORDER BY.
-- 5. GIN trigram indexes: Enable fast ILIKE '%text%' pattern matching.
-- 6. No redundant/duplicate indexes: Every index directly serves >= 1 query.
-- =====================================================================

SET search_path TO amazon, public;

-- Enable trigram extension for substring text searches (R01, R16)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =====================================================================
-- 1. PRODUCTS TABLE INDEXES
-- =====================================================================

-- Serves: R01 (Search box title keyword matching)
-- Technique: GIN Trigram Partial Index
-- Rationale: ILIKE '%wireless%' cannot utilize B-tree indexes. A GIN index
-- using pg_trgm decomposes strings into 3-character trigrams for fast bitmap
-- index scans. Filtered to status = 'ACTIVE' to omit inactive/out-of-stock items.
CREATE INDEX IF NOT EXISTS idx_products_title_trgm
ON products USING gin (title public.gin_trgm_ops)
WHERE status = 'ACTIVE';

-- Serves: R02 (Category browse: Electronics tree ₹1,000–₹5,000)
-- Technique: Composite Partial B-Tree Index
-- Rationale: Equality/IN on category_id, range on price, filtered by status = 'ACTIVE'.
-- Column order: (category_id, price) allows the engine to jump directly to the
-- matching categories and scan only the relevant price slice.
CREATE INDEX IF NOT EXISTS idx_products_category_price
ON products (category_id, price)
WHERE status = 'ACTIVE';

-- Serves: R07 (Seller Central: low stock products)
-- Technique: Composite Partial B-Tree Index
-- Rationale: Filters by seller_id = 217 and stock_qty <= 20 for active/out-of-stock items.
-- Column order: (seller_id, stock_qty) enables direct index lookup for the seller
-- followed by an index scan over low stock values.
CREATE INDEX IF NOT EXISTS idx_products_seller_stock
ON products (seller_id, stock_qty)
WHERE status IN ('ACTIVE', 'OUT_OF_STOCK');

-- Serves: R14 (Deals page: active products < 50% MRP)
-- Technique: Expression Partial B-Tree Index
-- Rationale: Evaluates the expression (price / mrp) in WHERE and ORDER BY.
-- The partial condition (price < mrp * 0.5 AND status = 'ACTIVE') indexes only
-- deeply discounted items (~9k of 30k rows), enabling a 0.2ms index scan.
CREATE INDEX IF NOT EXISTS idx_products_discount
ON products ((price / mrp))
WHERE price < mrp * 0.5 AND status = 'ACTIVE';


-- =====================================================================
-- 2. ORDERS TABLE INDEXES
-- =====================================================================

-- Serves: R04 ("Your Orders"), R10 (Marketing abandoned carts check)
-- Technique: Composite B-Tree Index
-- Rationale: Customers look up their order history sorted newest first:
-- WHERE customer_id = ? ORDER BY ordered_at DESC.
-- Avoids sorting 120k rows in memory; provides exact pre-sorted index order.
CREATE INDEX IF NOT EXISTS idx_orders_customer_ordered
ON orders (customer_id, ordered_at DESC);

-- Serves: R05 (Logistics: delayed in-transit shipments)
-- Technique: Partial B-Tree Index
-- Rationale: Only ~877 out of 120,000 orders have status = 'SHIPPED'.
-- A partial index on shipped_at for this status occupies only 40 kB,
-- turning a full table scan into an instantaneous index range scan.
CREATE INDEX IF NOT EXISTS idx_orders_shipped_transit
ON orders (shipped_at)
WHERE status = 'SHIPPED';

-- Serves: R08 (Merchandising best-sellers), R09 (Prime AOV), R20 (Daily GMV)
-- Technique: Composite Covering Partial B-Tree Index
-- Rationale: Filters orders for date ranges (e.g. ordered_at >= '2026-06-01')
-- excluding cancelled orders. Covering customer_id and total_amount satisfies
-- R09 and R20 aggregations with minimal heap fetches.
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at_active
ON orders (ordered_at) INCLUDE (total_amount, customer_id)
WHERE status <> 'CANCELLED';

-- Serves: R13 (Address clean-up unused addresses)
-- Technique: Partial B-Tree Index
-- Rationale: Speeds up NOT EXISTS / NOT IN anti-joins by indexing non-null
-- delivery address foreign keys.
CREATE INDEX IF NOT EXISTS idx_orders_address_id
ON orders (address_id)
WHERE address_id IS NOT NULL;

-- Serves: R17 (Trust & Safety verified reviews audit), R18 (Mumbai spend tiers)
-- Technique: Composite Covering Partial B-Tree Index
-- Rationale: Evaluates whether a customer has delivered/returned orders.
-- Partial filter status IN ('DELIVERED', 'RETURNED') indexes 110k fulfilled orders.
CREATE INDEX IF NOT EXISTS idx_orders_customer_delivered
ON orders (customer_id, order_id) INCLUDE (total_amount)
WHERE status IN ('DELIVERED', 'RETURNED');

-- Serves: R22 (Admin: All orders paginated OFFSET 75,000 LIMIT 25)
-- Technique: B-Tree Index in Descending Date Order
-- Rationale: ORDER BY ordered_at DESC requires scanning orders newest first.
-- This index eliminates the expensive 120,000-row in-memory quicksort.
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at_desc
ON orders (ordered_at DESC);

-- Serves: W05 (Logistics: ship oldest packed order)
-- Technique: Partial B-Tree Index
-- Rationale: For SELECT min(order_id) FROM orders WHERE status = 'PACKED'.
-- Only 59 orders are 'PACKED'. This 16 kB index yields an instantaneous O(1) fetch.
CREATE INDEX IF NOT EXISTS idx_orders_packed_id
ON orders (order_id)
WHERE status = 'PACKED';


-- =====================================================================
-- 3. ORDER_ITEMS TABLE INDEXES
-- =====================================================================

-- Serves: R08, R11 (Frequently bought together), R12 (Returns by category),
--         R17 (Verified purchase validation), R19 (Category mobile sales)
-- Technique: Composite Covering B-Tree Index
-- Rationale: order_items only had a PK on (order_id, line_no). Every join
-- on product_id previously triggered a sequential scan of 240,000 rows.
-- Indexing (product_id, order_id) INCLUDE (quantity) resolves the single largest
-- bottleneck in the entire database (speeds up R19 by 670× and R11 by 56×).
CREATE INDEX IF NOT EXISTS idx_order_items_product_id
ON order_items (product_id, order_id) INCLUDE (quantity);

-- Serves: R06 (Seller Central order lines), R15 (Top sellers by revenue)
-- Technique: Composite Covering B-Tree Index
-- Rationale: Filters by seller_id = ? and joins with orders.
-- (seller_id, order_id) INCLUDE (product_id, quantity, unit_price) satisfies
-- seller dashboard line queries directly from the index.
CREATE INDEX IF NOT EXISTS idx_order_items_seller_order
ON order_items (seller_id, order_id) INCLUDE (product_id, quantity, unit_price);


-- =====================================================================
-- 4. PRODUCT_REVIEWS TABLE INDEXES
-- =====================================================================

-- Serves: R03 (Product page rating breakdown)
-- Technique: Composite B-Tree Covering Index
-- Rationale: WHERE product_id = ? GROUP BY rating ORDER BY rating DESC.
-- (product_id, rating) enables a pure Index-Only Scan.
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_rating
ON product_reviews (product_id, rating);

-- Serves: R16 (Review insights: battery mentions)
-- Technique: GIN Trigram Text Index
-- Rationale: Substring search (body ILIKE '%battery%') across 38,662 customer reviews.
-- GIN index reduces execution time from 25ms to ~10ms.
CREATE INDEX IF NOT EXISTS idx_product_reviews_body_trgm
ON product_reviews USING gin (body public.gin_trgm_ops);

-- Serves: R17 (Trust & safety verified reviews audit)
-- Technique: Composite Partial B-Tree Index
-- Rationale: Only verified reviews are checked for fraud: WHERE verified_purchase = true.
-- (customer_id, product_id) allows fast anti-join probing.
CREATE INDEX IF NOT EXISTS idx_product_reviews_verified
ON product_reviews (customer_id, product_id)
WHERE verified_purchase = true;


-- =====================================================================
-- 5. CART_ITEMS, CUSTOMERS & RETURNS INDEXES
-- =====================================================================

-- Serves: R10 (Marketing abandoned carts), W06 (Nightly cart clean-up)
-- Technique: Composite Covering B-Tree Index
-- Rationale: Range filter on added_at < '2026-05-01' and nightly batch deletion.
CREATE INDEX IF NOT EXISTS idx_cart_items_added_at
ON cart_items (added_at) INCLUDE (quantity);

-- Serves: R18 (Customer analytics: Mumbai spending tiers)
-- Technique: Composite B-Tree Index
-- Rationale: Filters customers by city_id = 2.
CREATE INDEX IF NOT EXISTS idx_customers_city_id
ON customers (city_id, customer_id);

-- Serves: R12 (Category managers: return rates)
-- Technique: Composite Foreign-Key B-Tree Index
-- Rationale: returns has a foreign key to order_items(order_id, line_no) that was
-- unindexed in the baseline schema. Indexing (order_id, line_no) allows fast hash
-- or merge joins during return rate aggregation.
CREATE INDEX IF NOT EXISTS idx_returns_order_line
ON returns (order_id, line_no);


-- =====================================================================
-- Refresh statistics across all tables
-- =====================================================================
ANALYZE;
