-- =====================================================================
-- CHECKPOINT 4 (CP4): POSTGRESQL DECLARATIVE PARTITIONING STRATEGY
-- Database: PostgreSQL 18.x (Postgres.app / macOS Apple Silicon)
-- Team: T0103 | Team Name: SkillSwap | Section: A
-- Target Table: amazon.orders partitioned by RANGE (ordered_at)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ARCHITECTURAL RATIONALE FOR PARTITIONING ORDERS BY RANGE(ordered_at)
-- ---------------------------------------------------------------------
-- In an e-commerce platform operating at scale (120,000 orders in seed data,
-- 2,400,000 orders in 20x large data, and 12,000,000+ orders at 100x scale),
-- the `orders` table exhibits distinct operational characteristics:
--
-- a) Natural Time-Series Lifecycle:
--    Orders follow a strict unidirectional state progression:
--    PLACED -> PACKED -> SHIPPED -> OUT_FOR_DELIVERY -> DELIVERED / CANCELLED.
--    Active writes, updates, and fulfillment tracking occur almost exclusively
--    within the current quarter (hot working set). Once delivered, orders become
--    immutable cold historical records.
--
-- b) Query Workload Alignment:
--    The 30-query workload heavily filters by temporal boundaries:
--    - R06 (Seller Central): June 2026 orders (ordered_at in June 2026)
--    - R08 (Best sellers): June 2026 orders (ordered_at >= '2026-06-01')
--    - R09 (Prime AOV): Monthly in 2026 (EXTRACT(YEAR FROM ordered_at) = 2026)
--    - R10 (Abandoned cart): Orders after '2026-05-01'
--    - R15 (Seller performance): Orders in 2026 (ordered_at >= '2026-01-01')
--    - R18 (Mumbai spend tiers): Orders in 2026 (ordered_at >= '2026-01-01')
--    - R20 (Finance Daily GMV): Daily sales in June 2026
--    - R21 (Logistics delays): Deliveries in June 2026
--    - R22 (Admin pagination): Ordered by ordered_at DESC
--
-- c) Partition Pruning Efficiency:
--    Declarative range partitioning enables PostgreSQL's query optimizer
--    (via `enable_partition_pruning = on`) to eliminate irrelevant quarters
--    entirely during planning and execution. A query for June 2026 accesses
--    ONLY the 2026 Q2 partition, pruning away 87.5% of the table data and
--    index pages from memory cache.
--
-- d) Storage Tiering, Vacuuming & Lifecycle Management:
--    - Autovacuum overhead: Historical closed partitions require zero vacuuming.
--      Only the current active partition incurs write/update churn.
--    - Instant Archival: Old partitions (e.g. 2025) can be detached in O(1) time
--      via `ALTER TABLE orders DETACH PARTITION` without locks or bloat,
--      replacing costly, multi-million-row DELETE operations.
--
-- ---------------------------------------------------------------------
-- 2. THE POSTGRESQL PRIMARY KEY RULE FOR PARTITIONED TABLES
-- ---------------------------------------------------------------------
-- IMPORTANT POSTGRESQL CONSTRAINT RULE:
-- In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY constraint
-- on a partitioned table MUST contain all columns present in the partition key.
--
-- Rationale:
-- PostgreSQL partitions are physical child tables (`pg_inherits`). Unique indexes
-- are built locally on each partition. To guarantee global uniqueness without
-- requiring cross-partition index scans on every INSERT, PostgreSQL requires
-- the partition key (`ordered_at`) to be part of the primary key.
--
-- Consequently:
-- Standalone `PRIMARY KEY (order_id)` is NOT permissible on partitioned `orders`.
-- The primary key MUST be defined as a composite key:
--   PRIMARY KEY (order_id, ordered_at)
--
-- Foreign Key Implication:
-- In PostgreSQL 12+, foreign keys CAN reference a partitioned table, but the
-- referenced columns must match the partitioned table's unique/primary key.
-- Therefore, child tables (e.g., `order_items`) referencing `orders` must either:
-- 1. Include `ordered_at` and declare FK `(order_id, ordered_at) REFERENCES orders(order_id, ordered_at)`
--    (enabling co-partitioning of `order_items`), OR
-- 2. Enforce cross-table integrity via business logic/sequences while maintaining
--    local partition integrity.
-- =====================================================================

SET search_path TO amazon, public;

-- ---------------------------------------------------------------------
-- STEP 1: CREATE RANGE-PARTITIONED ORDERS TABLE
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS amazon.orders_partitioned (
    order_id        INTEGER        NOT NULL,
    customer_id     INTEGER        NOT NULL REFERENCES amazon.customers(customer_id) ON DELETE RESTRICT,
    address_id      INTEGER        REFERENCES amazon.addresses(address_id) ON DELETE SET NULL,
    ordered_at      TIMESTAMPTZ    NOT NULL,
    payment_method  VARCHAR(10)    NOT NULL CHECK (payment_method IN ('UPI', 'CARD', 'COD', 'GIFT_CARD', 'NETBANKING', 'EMI')),
    total_amount    NUMERIC(10,2)  NOT NULL CHECK (total_amount >= 0),
    status          VARCHAR(16)    NOT NULL CHECK (status IN ('PLACED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'RETURNED')),
    shipped_at      TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,

    -- The partition key (ordered_at) MUST be part of the primary key
    CONSTRAINT pk_orders_partitioned PRIMARY KEY (order_id, ordered_at)
) PARTITION BY RANGE (ordered_at);

-- ---------------------------------------------------------------------
-- STEP 2: CREATE QUARTERLY PARTITIONS (2025 - 2026) + DEFAULT PARTITION
-- ---------------------------------------------------------------------
-- Partition range boundaries use half-open intervals: [start, end)

-- Year 2025 Partitions
CREATE TABLE IF NOT EXISTS amazon.orders_2025_q1 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS amazon.orders_2025_q2 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS amazon.orders_2025_q3 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS amazon.orders_2025_q4 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- Year 2026 Partitions
CREATE TABLE IF NOT EXISTS amazon.orders_2026_q1 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS amazon.orders_2026_q2 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS amazon.orders_2026_q3 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS amazon.orders_2026_q4 PARTITION OF amazon.orders_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

-- Default Partition for catch-all / forward compatibility
CREATE TABLE IF NOT EXISTS amazon.orders_default PARTITION OF amazon.orders_partitioned
    DEFAULT;

-- ---------------------------------------------------------------------
-- STEP 3: PROPAGATE TARGETED WORKLOAD INDEXES TO PARTITIONS
-- ---------------------------------------------------------------------
-- Creating indexes on the partitioned parent automatically cascades
-- matching indexes to each existing partition and any future child partitions.

-- 1. Index for R04 ("Your Orders" customer lookup)
CREATE INDEX IF NOT EXISTS idx_orders_part_customer_ordered
    ON amazon.orders_partitioned (customer_id, ordered_at DESC);

-- 2. Partial index for R05 (delayed in-transit shipments)
CREATE INDEX IF NOT EXISTS idx_orders_part_shipped_transit
    ON amazon.orders_partitioned (shipped_at)
    WHERE status = 'SHIPPED';

-- 3. Composite covering index for R08, R09, R20 (active orders aggregation)
CREATE INDEX IF NOT EXISTS idx_orders_part_ordered_at_active
    ON amazon.orders_partitioned (ordered_at) INCLUDE (total_amount, customer_id)
    WHERE status <> 'CANCELLED';

-- 4. Partial index for R13 (unused delivery address anti-join)
CREATE INDEX IF NOT EXISTS idx_orders_part_address_id
    ON amazon.orders_partitioned (address_id)
    WHERE address_id IS NOT NULL;

-- 5. Covering index for R17, R18 (fulfilled orders by customer)
CREATE INDEX IF NOT EXISTS idx_orders_part_customer_delivered
    ON amazon.orders_partitioned (customer_id, order_id) INCLUDE (total_amount)
    WHERE status IN ('DELIVERED', 'RETURNED');

-- 6. Index for R22 (Admin newest-first pagination)
CREATE INDEX IF NOT EXISTS idx_orders_part_ordered_at_desc
    ON amazon.orders_partitioned (ordered_at DESC);

-- 7. Partial index for W05 (Logistics: oldest packed order)
CREATE INDEX IF NOT EXISTS idx_orders_part_packed_id
    ON amazon.orders_partitioned (order_id)
    WHERE status = 'PACKED';

-- ---------------------------------------------------------------------
-- STEP 4: DATA MIGRATION FROM EXISTING UNPARTITIONED TABLE
-- ---------------------------------------------------------------------
-- Safely copy records from unpartitioned orders into partitioned table
INSERT INTO amazon.orders_partitioned
SELECT * FROM amazon.orders
ON CONFLICT (order_id, ordered_at) DO NOTHING;

-- Refresh statistics for query planner
ANALYZE amazon.orders_partitioned;

-- ---------------------------------------------------------------------
-- STEP 5: VERIFICATION OF PARTITION DISTRIBUTION
-- ---------------------------------------------------------------------
SELECT tableoid::regclass AS partition_name,
       count(*)           AS row_count,
       min(ordered_at)    AS min_date,
       max(ordered_at)    AS max_date
FROM amazon.orders_partitioned
GROUP BY tableoid
ORDER BY partition_name;

-- ---------------------------------------------------------------------
-- STEP 6: VERIFICATION OF PARTITION PRUNING WITH EXPLAIN (ANALYZE, BUFFERS)
-- ---------------------------------------------------------------------
-- Query R20 Slice (Finance Daily GMV for June 2026):
-- PostgreSQL planner prunes all partitions except orders_2026_q2!
EXPLAIN (ANALYZE, BUFFERS)
SELECT ordered_at::date AS day,
       sum(total_amount) AS gmv
FROM amazon.orders_partitioned
WHERE status <> 'CANCELLED'
  AND ordered_at >= '2026-06-01 00:00:00+05:30'
  AND ordered_at < '2026-07-01 00:00:00+05:30'
GROUP BY 1
ORDER BY day;
