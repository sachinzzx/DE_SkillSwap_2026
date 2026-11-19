# Checkpoint 3: Workload Optimization Report

**Course:** Database Management Systems · **Team:** T0103 (SkillSwap) · **Section:** A  
**Database:** PostgreSQL 18.4 (Postgres.app) · **Hardware:** MacBook Pro M4 · **Date:** November 2026  
**Repository:** `sachinzzx/DE_SkillSwap_2026` · **Branch:** `main`  

---

## 1. Project & Benchmark Overview

In Checkpoint 2, we established the empirical performance baseline across all 30 production workload queries on an unindexed schema containing 555,584 records across 11 relational tables. The baseline cumulative execution time was **20,957.264 ms** (~20.96 seconds), dominated by sequential table scans on large tables (`orders` with 120,000 rows and `order_items` with 240,000 rows), missing foreign-key indexes, and quadratic nested-loop correlated subqueries.

In Checkpoint 3, our goal is to systematically optimize the database engine:
1. Design and deploy targeted secondary B-tree, partial, covering, expression, and GIN trigram indexes in [`sql/05_indexes.sql`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/sql/05_indexes.sql).
2. Rewrite bottleneck queries and fix the subtle SQL three-valued logic NULL bug in [`sql/06_optimized_queries.sql`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/sql/06_optimized_queries.sql).
3. Validate mathematical result equivalence using `EXCEPT` difference proofs.
4. Measure performance improvements using the exact same three-run benchmark methodology.

---

## 2. Optimization Methodology

Optimization was performed adhering strictly to project integrity rules:
- **Zero Server-Side Workarounds:** No changes to `work_mem`, no `enable_seqscan = off`, and no external caching layers.
- **Pure PostgreSQL Tuning:** All optimizations are self-contained within index definitions and SQL query rewrites.
- **Result Preservation:** The underlying data was never modified or deleted. Every rewritten query was proven to return the exact same rows as the original workload query.
- **Three-Run Averaging:** Each optimized query was executed three consecutive times (`RUNS=3`) using [`benchmarks/run_benchmark.sh`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/run_benchmark.sh), capturing buffer hits, execution times, and plan nodes into [`benchmarks/results/optimized/`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/results/optimized/).

---

## 3. Indexes Added and Technical Justification

A total of **19 optimized indexes** were created in `sql/05_indexes.sql`, totaling **32.8 MB** in storage:

| Table | Index Name | Type / Structure | Target Queries | Technical Justification |
|---|---|---|---|---|
| `products` | `idx_products_title_trgm` | GIN Trigram (`title`) `WHERE status = 'ACTIVE'` | `R01` | Enables index acceleration for `ILIKE '%wireless%'` wildcards via trigram matching. |
| `products` | `idx_products_category_price` | Composite B-Tree `(category_id, price)` `WHERE status = 'ACTIVE'` | `R02` | Eliminates sequential scan for recursive category browsing with price range filter. |
| `products` | `idx_products_seller_stock` | Composite Partial B-Tree `(seller_id, stock_qty)` | `R07` | Instant point lookup for seller low stock alerts (`<= 20`). |
| `products` | `idx_products_discount` | Expression Partial B-Tree `((price / mrp))` | `R14` | Pre-computes and orders discounts < 50% MRP, turning full table scan into 0.17ms index scan. |
| `orders` | `idx_orders_customer_ordered` | Composite B-Tree `(customer_id, ordered_at DESC)` | `R04`, `R10` | Provides pre-sorted order history per customer without in-memory quicksort. |
| `orders` | `idx_orders_shipped_transit` | Partial B-Tree `(shipped_at)` `WHERE status = 'SHIPPED'` | `R05` | Indexes only the ~877 in-transit orders (40 kB index size) for fast latency queries. |
| `orders` | `idx_orders_ordered_at_active` | Composite Covering Partial B-Tree `(ordered_at)` `INCLUDE (total_amount, customer_id)` | `R08`, `R09`, `R20` | Satisfies June 2026 and FY2026 financial aggregations via Index-Only Scans. |
| `orders` | `idx_orders_address_id` | Partial B-Tree `(address_id)` `WHERE address_id IS NOT NULL` | `R13` | Speeds up `NOT EXISTS` anti-join checking for unused customer delivery addresses. |
| `orders` | `idx_orders_customer_delivered` | Composite Covering Partial B-Tree `(customer_id, order_id)` `INCLUDE (total_amount)` | `R17`, `R18` | Validates customer purchase history for fraud checks and Mumbai spending tiers. |
| `orders` | `idx_orders_ordered_at_desc` | B-Tree `(ordered_at DESC)` | `R22` | Enables index scan for large offset pagination (`OFFSET 75000 LIMIT 25`) without quicksort. |
| `orders` | `idx_orders_packed_id` | Partial B-Tree `(order_id)` `WHERE status = 'PACKED'` | `W05` | Tiny 16 kB index turning `min(order_id)` lookups into an $O(1)$ single-page index fetch. |
| `order_items` | `idx_order_items_product_id` | Composite Covering B-Tree `(product_id, order_id)` `INCLUDE (quantity)` | `R08`, `R11`, `R12`, `R17`, `R19` | Indexes the foreign key `product_id`. Resolves the single largest bottleneck in the database. |
| `order_items` | `idx_order_items_seller_order` | Composite Covering B-Tree `(seller_id, order_id)` `INCLUDE (product_id, quantity, unit_price)` | `R06`, `R15` | Enables Index-Only Scans for Seller Central order lines and revenue dashboards. |
| `product_reviews`| `idx_product_reviews_product_rating` | Composite Covering B-Tree `(product_id, rating)` | `R03` | Index-Only Scan for product page rating breakdowns. |
| `product_reviews`| `idx_product_reviews_body_trgm` | GIN Trigram (`body`) | `R16` | Trigram index for full review body substring searches (`ILIKE '%battery%'`). |
| `product_reviews`| `idx_product_reviews_verified` | Composite Partial B-Tree `(customer_id, product_id)` `WHERE verified_purchase = true` | `R17` | Indexes verified customer reviews for fraud auditing. |
| `cart_items` | `idx_cart_items_added_at` | Composite Covering B-Tree `(added_at)` `INCLUDE (quantity)` | `R10`, `W06` | Accelerates abandoned cart marketing queries and nightly batch deletions. |
| `customers` | `idx_customers_city_id` | Composite B-Tree `(city_id, customer_id)` | `R18` | Fast index filtering for city-level customer demographic segmentation (`city_id = 2`). |
| `returns` | `idx_returns_order_line` | Composite Foreign-Key B-Tree `(order_id, line_no)` | `R12` | Indexes the unindexed foreign key to `order_items` for return percentage calculations. |

---

## 4. Query Rewriting Techniques & The Subtle NULL Bug

### 4.1 The Wrong-Answer NULL Bug in Query R13 (Problem P6)
- **Original Workload Query:**
  ```sql
  SELECT a.address_id, a.customer_id, a.label
  FROM addresses a
  WHERE a.address_id NOT IN (SELECT o.address_id FROM orders o);
  ```
- **The Bug:**  
  In the seed dataset, **5,882 orders** represent digital purchases (E-Books and Gift Cards) and appropriately have `address_id IS NULL`. Under SQL's three-valued logic (`TRUE`, `FALSE`, `UNKNOWN`), the expression:
  $$\text{address\_id} \notin \{1, 2, \dots, \text{NULL}\}$$
  evaluates to `UNKNOWN` whenever the candidate address is not found in the non-null set. Because a `WHERE` clause accepts only rows that evaluate to `TRUE`, **every single row was rejected**. The original query falsely returned **0 rows**, contradicting customer support reports.
- **The Optimization & Fix:**  
  Rewritten in `sql/06_optimized_queries.sql` using `NOT EXISTS`:
  ```sql
  SELECT a.address_id, a.customer_id, a.label
  FROM addresses a
  WHERE NOT EXISTS (
      SELECT 1 FROM orders o
      WHERE o.address_id = a.address_id
  );
  ```
- **Result:** Correctly returns **15,679 unused saved addresses** using an index-assisted anti-join in **25.363 ms**.

### 4.2 Eliminating Correlated Subqueries in Query R19
- **Problem:** For each of the 937 products in category `Mobiles`, R19 executed two separate scalar subqueries across 240,000 order item rows:
  1. `SELECT max(o.ordered_at) FROM order_items oi JOIN orders o ...`
  2. `SELECT coalesce(sum(oi.quantity), 0) FROM order_items oi ...`
  This caused 1,874 table scans and over 224,000,000 row comparisons in memory (~20.2 seconds).
- **The Optimization:**  
  Pre-aggregating order sales in a single grouped join using `idx_order_items_product_id`:
  ```sql
  SELECT p.product_id, p.title,
         agg.last_sold_at,
         coalesce(agg.units_sold, 0) AS units_sold
  FROM products p
  LEFT JOIN (
      SELECT oi.product_id,
             max(o.ordered_at) AS last_sold_at,
             sum(oi.quantity) AS units_sold
      FROM order_items oi
      JOIN orders o ON o.order_id = oi.order_id
      WHERE oi.product_id IN (
          SELECT p2.product_id FROM products p2
          WHERE p2.category_id = (SELECT category_id FROM categories WHERE category_name = 'Mobiles')
      )
      GROUP BY oi.product_id
  ) agg ON agg.product_id = p.product_id
  WHERE p.category_id = (SELECT category_id FROM categories WHERE category_name = 'Mobiles')
  ORDER BY units_sold DESC, p.product_id;
  ```
- **Equivalence Proof:** Mathematical set difference `(orig EXCEPT opt)` and `(opt EXCEPT orig)` returned **0 rows**.
- **Result:** Execution time dropped from **20,200.852 ms to 23.982 ms** (an **842× speedup / 99.88% latency drop**).

### 4.3 Sargable Date Range Transformations (Queries R06, R09, R20)
- In `R06`, replaced `date_trunc('month', o.ordered_at) = '2026-06-01'` with:
  `o.ordered_at >= '2026-06-01 00:00:00+05:30' AND o.ordered_at < '2026-07-01 00:00:00+05:30'`
- In `R09`, replaced `EXTRACT(YEAR FROM o.ordered_at) = 2026` with:
  `o.ordered_at >= '2026-01-01 00:00:00+05:30' AND o.ordered_at < '2027-01-01 00:00:00+05:30'`
- In `R20`, replaced `ordered_at::date BETWEEN ...` with timestamp bounds.
- **Result:** Allows the planner to perform B-tree index range scans rather than scanning entire tables evaluating functions per row.

---

## 5. Comprehensive Before vs. After Benchmark Results

All timings are in milliseconds (ms), calculated as the arithmetic average of 3 consecutive runs matching [`benchmarks/results/baseline/summary.csv`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/results/baseline/summary.csv) and [`benchmarks/results/optimized/summary.csv`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/results/optimized/summary.csv).

$$\text{Improvement \%} = \frac{\text{Baseline} - \text{Optimized}}{\text{Baseline}} \times 100$$

| Query | Baseline (ms) | Problem Found in Baseline Plan | Optimization Applied | Optimized (ms) | Improvement (%) | Same Result? |
|:---|---:|:---|:---|---:|---:|:---:|
| **R01** | 25.999 | Seq Scan on 30k products for wildcard text | GIN Trigram index `idx_products_title_trgm` | **3.941** | **+84.8%** (6.6×) | ✅ |
| **R02** | 5.915 | Seq Scan filtering category and price | Composite B-tree `(category_id, price)` | **3.204** | **+45.8%** (1.8×) | ✅ |
| **R03** | 3.266 | Seq Scan on 38k reviews | Composite covering `(product_id, rating)` | **0.115** | **+96.5%** (28×) | ✅ |
| **R04** | 6.624 | Seq Scan on 120k orders + in-memory sort | Composite B-tree `(customer_id, ordered_at DESC)` | **0.139** | **+97.9%** (48×) | ✅ |
| **R05** | 9.492 | Seq Scan on 120k orders for shipped status | Partial index on `shipped_at` (877 rows) | **0.533** | **+94.4%** (18×) | ✅ |
| **R06** | 10.138 | Non-sargable `date_trunc` + Seq Scan on items | Sargable rewrite + `idx_order_items_seller_order` | **1.191** | **+88.3%** (8.5×) | ✅ |
| **R07** | 3.551 | Seq Scan on 30k products | Partial index on `(seller_id, stock_qty)` | **0.029** | **+99.2%** (122×) | ✅ |
| **R08** | 47.199 | Triple Seq Scan on orders, items, products | Date range index + `idx_order_items_product_id` | **41.826** | **+11.4%** | ✅ |
| **R09** | 46.758 | Non-sargable `EXTRACT(YEAR)` on orders | Sargable range + covering index on `ordered_at` | **26.764** | **+42.8%** (1.7×) | ✅ |
| **R10** | 33.414 | Seq Scan on cart_items and orders | Index on `cart_items(added_at)` + customer orders | **28.696** | **+14.1%** | ✅ |
| **R11** | 9.369 | Seq Scan on 240k order_items for self-join | Composite index `(product_id, order_id)` | **0.167** | **+98.2%** (56×) | ✅ |
| **R12** | 119.734 | Must read all 240k order_items and returns | Foreign-key index `returns(order_id, line_no)` | **118.450** | **+1.1%** | ✅ |
| **R13** | 31.441 | Three-valued logic bug returns 0 rows | Rewrite to `NOT EXISTS` + `idx_orders_address_id` | **25.363** | **+19.3%** | ⚠️ Fixed (0 → 15,679) |
| **R14** | 7.742 | Seq Scan on 30k products + quicksort | Partial expression index `((price / mrp))` | **0.168** | **+97.8%** (46×) | ✅ |
| **R15** | 43.318 | Aggregation over 2026 fulfilled order lines | Covering index on seller lines + orders index | **42.606** | **+1.6%** | ✅ |
| **R16** | 25.351 | Seq Scan on 38k reviews for ILIKE keyword | GIN Trigram index `idx_product_reviews_body_trgm` | **9.515** | **+62.5%** (2.7×) | ✅ |
| **R17** | 104.509 | Hash Anti Join with large table scans | Nested Loop Anti Join over verified reviews | **187.233** | **-79.2%** (Trade-off) | ✅ |
| **R18** | 19.097 | Seq Scan on customers and orders | `idx_customers_city_id` + delivered orders index | **14.017** | **+26.6%** (1.4×) | ✅ |
| **R19** | 20200.852 | Double correlated subquery (224M inspections)| Grouped join rewrite + `idx_order_items_product_id`| **23.982** | **+99.9%** (842×) | ✅ |
| **R20** | 18.643 | Date cast filter on orders | Sargable timestamp bounds + covering index | **2.234** | **+88.0%** (8.3×) | ✅ |
| **R21** | 11.687 | Seq Scan on 120k orders | Index scan on `idx_orders_ordered_at_desc` | **1.888** | **+83.8%** (6.2×) | ✅ |
| **R22** | 61.061 | Full 120k quicksort to discard 75k rows | Descending B-tree index `orders(ordered_at DESC)` | **13.592** | **+77.7%** (4.5×) | ✅ |
| **R23** | 0.464 | Order details lines lookup | Covered by existing PK and index lookups | **0.133** | **+71.3%** (3.5×) | ✅ |
| **R24** | 0.187 | ASIN barcode scanner lookup | Pre-indexed unique B-tree (`products_asin_key`) | **0.042** | **+77.7%** (4.5×) | ✅ |
| **W01** | 2.457 | Single row INSERT into orders | Efficient single page write | **1.280** | **+47.9%** | ✅ |
| **W02** | 1.057 | Single row stock decrement | Minor index update overhead on seller stock | **1.144** | **-8.2%** (0.08ms) | ✅ |
| **W03** | 4.277 | Seq Scan on products for Watches | Index scan on `idx_products_seller_stock` | **2.434** | **+43.1%** | ✅ |
| **W04** | 76.791 | Batch insert of 5,000 cart items | PK index check + rollback benchmarking | **64.914** | **+15.5%** | ✅ |
| **W05** | 15.030 | Seq Scan on 120k orders to find min packed ID| Partial index `idx_orders_packed_id` ($O(1)$) | **0.398** | **+97.4%** (38×) | ✅ |
| **W06** | 11.841 | Seq Scan on cart_items to delete stale items | Range index scan on `idx_cart_items_added_at` | **5.267** | **+55.5%** (2.2×) | ✅ |
| **TOTAL** | **20957.264** | **Cumulative Workload Latency** | **Cumulative Optimized Latency** | **621.265** | **+97.0% (33.7×)**| ✅ |

---

## 6. Before vs. After Execution Plans (Top 5 Improvements)

### 1. Query R19 (Mobiles Category Sales Report): 20,200.852 ms → 23.982 ms (842× Speedup)
- **Before:** Nested Loop with two correlated subqueries executing Seq Scan on `order_items` (240k rows) and Index Scan on `orders` for each of the 937 products. Total execution time: `20,116.542 ms`.
- **After:** Hash Left Join on pre-aggregated subquery using `idx_order_items_product_id` (Index Only Scan on `order_items`) and `orders_pkey`. Total execution time: `23.982 ms`.

### 2. Query R07 (Seller Low Stock Alert): 3.551 ms → 0.029 ms (122× Speedup)
- **Before:** `Seq Scan on products p (cost=0.00..851.00 rows=3)` scanning 30,000 rows. Execution time: `3.551 ms`.
- **After:** `Index Scan using idx_products_seller_stock on products (cost=0.29..11.85 rows=3)`. 3 index rows fetched directly. Execution time: `0.029 ms`.

### 3. Query R11 (Frequently Bought Together): 9.369 ms → 0.167 ms (56× Speedup)
- **Before:** `Seq Scan on order_items a (cost=0.00..4192.00 rows=10)` across 240,000 rows followed by join on `order_items b`. Execution time: `9.369 ms`.
- **After:** `Index Only Scan using idx_order_items_product_id on order_items a (cost=0.42..8.58 rows=9)` with 0 heap fetches. Execution time: `0.167 ms`.

### 4. Query R04 ("Your Orders" History): 6.624 ms → 0.139 ms (48× Speedup)
- **Before:** `Seq Scan on orders o` across 120,000 rows followed by in-memory sort on `ordered_at DESC`. Execution time: `6.624 ms`.
- **After:** `Bitmap Index Scan on idx_orders_customer_ordered` fetching pre-sorted orders in `0.026 ms` and `Index Only Scan` on line items. Execution time: `0.139 ms`.

### 5. Query W05 (Logistics Oldest Packed Order): 15.030 ms → 0.398 ms (38× Speedup)
- **Before:** Subquery `SELECT min(order_id) FROM orders WHERE status = 'PACKED'` performed a full sequential scan across 120,000 rows. Execution time: `15.030 ms`.
- **After:** `Index Only Scan using idx_orders_packed_id on orders` fetching the single minimum value in $O(1)$ time (`0.216 ms`). Execution time: `0.398 ms`.

---

## 7. Write Overhead Analysis

Indexing tables accelerates read queries but incurs a write penalty during `INSERT`, `UPDATE`, and `DELETE` operations as secondary index B-trees must be kept synchronized.

| Query ID | Write Operation | Baseline (ms) | Optimized (ms) | Overhead / Speedup | Analysis |
|---|---|---:|---:|:---:|---|
| **W01** | INSERT 1 row into `orders` | 2.457 | 1.280 | **+47.9%** (Faster) | Page allocation in cache; new indexes add < 0.05ms insert overhead, easily absorbed. |
| **W02** | UPDATE `stock_qty` on 1 product | 1.057 | 1.144 | **-8.2%** (+0.087 ms) | Updating `stock_qty` updates `idx_products_seller_stock`. Overhead is negligible (under 0.1 ms). |
| **W03** | UPDATE 10% price cut on Watches | 4.277 | 2.434 | **+43.1%** (Faster) | The speedup in locating matching products via index outweighs the minor B-tree update cost. |
| **W04** | Batch INSERT 5,000 cart items | 76.791 | 64.914 | **+15.5%** (Faster) | Only `idx_cart_items_added_at` was added; sequential batch insert remains highly efficient. |
| **W05** | UPDATE oldest packed order | 15.030 | 0.398 | **+97.4%** (Faster) | The $O(1)$ index lookup for the target row completely dwarfs the single index update cost. |
| **W06** | DELETE stale cart items | 11.841 | 5.267 | **+55.5%** (Faster) | Range index scan speeds up finding rows to delete, reducing I/O. |

**Conclusion on Write Overhead:** Write overhead is exceptionally low and fully acceptable in a marketplace workload where reads vastly outnumber writes (typically 95:5 read-to-write ratio).

---

## 8. Index Storage & Table Size Comparison

Generated via PostgreSQL relation inspection:

| Table Name | Table Size | Primary/Unique Indexes | New Optimized Indexes | Total Index Size | Index / Table Ratio |
|---|---:|---:|---:|---:|---:|
| `orders` | 11 MB | 2.6 MB (`orders_pkey`) | 15.7 MB (7 indexes) | 18.3 MB | 166% |
| `order_items` | 14 MB | 5.3 MB (`order_items_pkey`)| 16.9 MB (2 indexes) | 22.2 MB | 158% |
| `products` | 3.8 MB | 1.6 MB (`pkey`, `asin`) | 3.1 MB (4 indexes) | 4.7 MB | 124% |
| `product_reviews` | 3.7 MB | 0.8 MB (`reviews_pkey`) | 3.1 MB (3 indexes) | 3.9 MB | 105% |
| `cart_items` | 2.3 MB | 1.2 MB (`cart_items_pkey`)| 1.4 MB (1 index) | 2.6 MB | 113% |
| `customers` | 3.0 MB | 3.8 MB (`pkey`, `email`, `phone`) | 0.7 MB (1 index) | 4.5 MB | 150% |
| `addresses` | 3.7 MB | 1.0 MB (`addresses_pkey`) | 0 kB | 1.0 MB | 27% |
| `returns` | 424 kB | 136 kB (`returns_pkey`) | 136 kB (1 index) | 272 kB | 64% |
| `sellers` | 144 kB | 136 kB (`pkey`, `gstin`) | 0 kB | 136 kB | 94% |
| `categories` | 8 kB | 32 kB (`pkey`, `name`) | 0 kB | 32 kB | 400% |
| `cities` | 8 kB | 16 kB (`cities_pkey`) | 0 kB | 16 kB | 200% |
| **TOTALS** | **42.1 MB** | **16.6 MB** | **41.0 MB** | **57.6 MB** | **137%** |

---

## 9. Queries That Could Not Be Accelerated and Why

1. **`R12` (Category Return Rate: 119.7 ms → 118.4 ms):**  
   - **Reason:** The query computes aggregate return percentages across all categories. It must read all 240,000 rows in `order_items`, join them with all 30,000 `products` and all 40 `categories`, and perform a hash left join against 5,374 `returns`. Because the query has no selective `WHERE` filter and aggregates over 100% of the table, an index cannot skip pages. In Phase 4/5, a Materialized View with periodic refresh would be the appropriate enterprise solution.
2. **`R15` (Top 20 Sellers by Revenue: 43.3 ms → 42.6 ms):**  
   - **Reason:** Requires aggregating all fulfilled order lines across the entire year 2026. Over 110,000 order lines meet the date/status filter. The engine must sum quantities and prices across tens of thousands of rows; sequential access remains faster than index random I/O.
3. **`R17` (Verified Reviews Anti-Join: 104.5 ms → 187.2 ms):**  
   - **Reason:** The PostgreSQL planner chose a Nested Loop Anti Join using the new index on `order_items(product_id)`. While individual index probes are fast, repeating the loop 35,662 times accumulates CPU overhead compared to a single batch hash join over all fulfilled orders. This trade-off is documented and will be addressed in Phase 5 scalability testing.

---

## 10. Summary & Conclusion

- **CP3 Optimization Goals Met:** All 30 workload queries execute cleanly and reliably.
- **Speedup Achieved:** Overall workload execution time fell from **20,957.264 ms to 621.265 ms**—a **97.0% overall performance improvement** (over **33× higher throughput**).
- **Core Bottleneck Eliminated:** Query `R19` dropped from **20.2 seconds down to 23.9 ms** (842× faster).
- **Wrong-Result Bug Solved:** Problem P6 (R13 returning 0 rows due to SQL three-valued logic with NULLs) was identified, explained, and fixed to return the true **15,679 unused addresses**.
- **Deliverables Verified:** `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `benchmarks/results/optimized/summary.csv`, and `docs/04_optimization_report.md` are 100% synchronized and tested against PostgreSQL 18.4.
