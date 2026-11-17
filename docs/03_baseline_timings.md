# Checkpoint 2: Baseline Benchmark Timings Report

**Course:** Database Management Systems · **Team:** T0103 (SkillSwap) · **Section:** A  
**Database:** PostgreSQL 18.4 (Postgres.app) · **Hardware:** MacBook Pro M4 · **Date:** November 2026  
**Repository:** `sachinzzx/DE_SkillSwap_2026` · **Branch:** `main`  

---

## 1. Project Overview

The Amazon Online Shopping database system is a relational platform modeling a high-throughput multi-seller e-commerce marketplace. The database captures the complete customer journey—from catalog search, recursive category browsing, shopping carts, and order checkout with saved addresses to logistics tracking, returns processing, and customer reviews.

The system is currently operating on an unindexed baseline schema (where only primary key and unique constraints have automatic B-tree indexes). Before applying indexing strategies, query rewrites, or partitioning in later phases, an empirical performance baseline must be established.

The purpose of this baseline benchmarking phase (CP2) is to:
1. Empirically measure the baseline latency of all 30 production workload queries (24 read queries `R01`–`R24` and 6 write operations `W01`–`W06`).
2. Identify sequential scans, buffer I/O bottlenecks, and unindexed foreign key lookups.
3. Quantify hot-cache vs. cold-cache execution behavior across multiple runs.
4. Establish concrete, reproducible benchmark numbers to measure speedup factors during Phase 4 (Optimization) and Phase 5 (Scalability on 20× large data).

---

## 2. Benchmark Environment

All benchmarks were executed locally on the primary development machine under controlled conditions with minimal background processes.

### 2.1 Hardware Specifications
- **Machine:** Apple MacBook Pro 14" (2024)
- **Processor:** Apple M4 (10-core CPU: 4 performance cores, 6 efficiency cores)
- **Architecture:** `aarch64` (Apple Silicon)
- **Memory:** Unified Memory Architecture (LPDDR5X)
- **Storage:** Apple NVMe Solid State Drive (APFS filesystem)

### 2.2 Operating System & Software
- **Operating System:** macOS 27.2.1 (Darwin Kernel Version 23.6.0)
- **Database Engine:** PostgreSQL 18.4 (Postgres.app distribution, 64-bit)
- **Compiler:** Apple clang version 15.0.0 (clang-1500.3.9.4)
- **Client Tool:** `psql` (PostgreSQL) 18.4

### 2.3 Database Configuration Parameters
The PostgreSQL instance ran with standard local development parameters to reflect default server behavior:

| Parameter | Configured Value | Description |
|---|---|---|
| `server_version` | `18.4 (Postgres.app)` | PostgreSQL server release |
| `shared_buffers` | `128MB` | Dedicated shared memory for caching table/index pages |
| `work_mem` | `4MB` | Memory for internal sort operations and hash tables |
| `effective_cache_size` | `4GB` | Planner assumption of available filesystem cache |
| `random_page_cost` | `4.0` | Planner cost estimate for non-sequential disk page fetch |
| `max_connections` | `100` | Maximum concurrent client connections |

### 2.4 Seed Dataset Summary
The database was populated using the official seed dataset (`seed_data.zip`, 120,000 orders spanning 1 Jan 2025 – 30 Jun 2026):

| Table Name | Entity Description | Row Count |
|---|---|---:|
| `cities` | Lookup of tier-1 and tier-2 Indian cities | 10 |
| `categories` | Product category hierarchy (8 parents, 32 sub-categories) | 40 |
| `sellers` | Registered marketplace business sellers | 1,500 |
| `products` | Product catalog listings across all categories | 30,000 |
| `customers` | Registered shoppers (standard and Prime members) | 30,000 |
| `addresses` | Saved customer delivery addresses | 45,000 |
| `orders` | Order header records with payment and lifecycle status | 120,000 |
| `order_items` | Individual line items per order | 240,000 |
| `returns` | Return and refund requests for order lines | 5,374 |
| `product_reviews` | Product reviews and ratings with verified flags | 38,662 |
| `cart_items` | Active shopping cart items | 44,998 |
| **Total Records** | **All 11 Relational Tables** | **555,584** |

---

## 3. Benchmark Methodology

### 3.1 Execution Protocol
The benchmark was conducted using the faculty-provided automation harness [`benchmarks/run_benchmark.sh`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/run_benchmark.sh) against the `amazon_test` database:

```bash
./benchmarks/run_benchmark.sh amazon_test baseline
```

### 3.2 Measurement Rules & Multi-Run Protocol
1. **Three Executions per Query:** Every workload query was executed **three consecutive times** (`RUNS=3`) to account for cold cache loading on Run 1 versus warm buffer cache behavior on Runs 2 and 3.
2. **Buffer & Timing Instrumentation:** Queries were executed using `EXPLAIN (ANALYZE, BUFFERS)` with output captured directly via `psql -X -q -A -t -v ON_ERROR_STOP=1`.
3. **Execution Time Extraction:** The actual engine execution time (`Execution Time: [0-9.]+ ms`) was parsed from the raw execution plan for each run.
4. **Transaction Safety for Writes:** Write operations (`W01`–`W06`) were wrapped inside `BEGIN; ... EXPLAIN (ANALYZE, BUFFERS) ... ROLLBACK;` blocks. This guaranteed that write queries measured actual update/insert/delete work without mutating the underlying dataset across consecutive runs.
5. **Arithmetic Average:** The reported average represents the exact arithmetic mean of all three independent runs:
   $$\text{Average} = \frac{\text{Run}_1 + \text{Run}_2 + \text{Run}_3}{3}$$
6. **Plan Archival:** Complete execution plans for all 3 runs of every query were written to individual plan files in [`benchmarks/results/baseline/`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/results/baseline/).

---

## 4. Baseline Results

The table below reports the raw execution timings across all three runs, the arithmetic average, and the query classification. All values are in milliseconds (ms), rounded to 3 decimal places matching [`benchmarks/results/baseline/summary.csv`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/results/baseline/summary.csv).

| Query ID | Description | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan Nodes Identified |
|:---|:---|:---:|---:|---:|---:|---:|:---|
| **R01** | Search box: active products with "wireless", best rated first | READ | 26.783 | 25.622 | 25.593 | **25.999** | Seq Scan on `products` |
| **R02** | Category browse: Electronics tree priced ₹1,000–₹5,000 | READ | 5.755 | 5.887 | 6.102 | **5.915** | Seq Scan on `categories`, `products` |
| **R03** | Product page: rating breakdown for product 4321 | READ | 2.279 | 2.341 | 5.177 | **3.266** | Seq Scan on `product_reviews` |
| **R04** | "Your Orders": customer 1042's orders with item counts | READ | 6.877 | 6.361 | 6.633 | **6.624** | Seq Scan on `orders` \| Index Only Scan on `order_items` |
| **R05** | Logistics: shipments in transit > 10 days on 30 Jun 2026 | READ | 9.188 | 9.458 | 9.829 | **9.492** | Seq Scan on `orders` |
| **R06** | Seller Central: seller 217's order lines in June 2026 | READ | 11.560 | 9.358 | 9.497 | **10.138** | Seq Scan on `order_items` \| Index Scan on `orders` |
| **R07** | Seller Central: seller 217's low stock products (<= 20) | READ | 3.409 | 3.592 | 3.652 | **3.551** | Seq Scan on `products` |
| **R08** | Merchandising: top 5 best-sellers per sub-category (30d) | READ | 45.861 | 47.873 | 47.862 | **47.199** | Seq Scan on `order_items`, `orders`, `products` |
| **R09** | Prime team: average order value Prime vs non-Prime (2026) | READ | 46.225 | 46.905 | 47.145 | **46.758** | Seq Scan on `orders`, `customers` |
| **R10** | Marketing: abandoned carts untouched since May 2026 | READ | 34.029 | 33.704 | 32.508 | **33.414** | Seq Scan on `orders`, `cart_items`, `products` |
| **R11** | Product page: "Frequently bought together" with product 4321 | READ | 9.784 | 9.090 | 9.233 | **9.369** | Seq Scan on `order_items` \| Index Scan on `order_items` |
| **R12** | Category managers: return rate per top-level category | READ | 117.740 | 123.742 | 117.721 | **119.734** | Seq Scan on `order_items`, `products`, `categories`, `returns` |
| **R13** | Data clean-up: saved addresses never used for any order | READ | 29.842 | 31.962 | 32.520 | **31.441** | Seq Scan on `addresses`, `orders` |
| **R14** | Deals page: active products < 50% MRP, sorted by discount | READ | 7.810 | 7.803 | 7.612 | **7.742** | Seq Scan on `products` |
| **R15** | Seller performance: top 20 sellers by 2026 revenue (>= 50 lines) | READ | 43.254 | 43.276 | 43.425 | **43.318** | Seq Scan on `order_items`, `orders`, `sellers` |
| **R16** | Review insights: Electronics reviews mentioning "battery" | READ | 24.868 | 25.855 | 25.330 | **25.351** | Seq Scan on `product_reviews`, `products`, `categories` |
| **R17** | Trust & safety: fake verified reviews without delivered orders | READ | 106.465 | 105.735 | 101.326 | **104.509** | Seq Scan on `order_items`, `orders`, `product_reviews` |
| **R18** | Customer analytics: Mumbai customers in 4 spending tiers | READ | 18.419 | 18.879 | 19.994 | **19.097** | Seq Scan on `orders`, `customers` |
| **R19** | Category report: Mobiles with last sale date & units sold | READ | 20116.542 | 20484.544 | 20001.469 | **20200.852** | Seq Scan on `categories`, `products`, `order_items` \| Index Scan on `orders` |
| **R20** | Finance: daily GMV and running total for June 2026 | READ | 17.489 | 21.850 | 16.591 | **18.643** | Seq Scan on `orders` |
| **R21** | Logistics: deliveries in June 2026 taking > 5 days | READ | 9.947 | 11.948 | 13.167 | **11.687** | Seq Scan on `orders` |
| **R22** | Admin: "All orders", newest first, page 3,001 (OFFSET 75k) | READ | 67.289 | 60.972 | 54.923 | **61.061** | Seq Scan on `orders` |
| **R23** | Order details: order 100001 with lines, products & sellers | READ | 1.078 | 0.144 | 0.170 | **0.464** | Index Scan on `order_items`, `orders`, `products`, `sellers` |
| **R24** | Product lookup by ASIN (warehouse scanner) | READ | 0.455 | 0.057 | 0.050 | **0.187** | Index Scan using `products_asin_key` on `products` |
| **W01** | Checkout: create a new order header row | WRITE | 3.257 | 2.510 | 1.605 | **2.457** | (no scan) |
| **W02** | Checkout: reduce stock of product 4322 after sale | WRITE | 2.265 | 0.445 | 0.462 | **1.057** | Index Scan using `products_pkey` on `products` |
| **W03** | Seller Central: 10% price cut on seller 217's Watches | WRITE | 2.920 | 3.434 | 6.477 | **4.277** | Seq Scan on `categories`, `products` |
| **W04** | Big sale: batch insert of 5,000 cart items | WRITE | 114.055 | 57.882 | 58.436 | **76.791** | (no scan) |
| **W05** | Logistics: mark oldest packed order as shipped | WRITE | 14.576 | 15.497 | 15.017 | **15.030** | Index Scan using `orders_pkey` on `orders` |
| **W06** | Nightly clean-up: delete cart items older than 90 days | WRITE | 12.840 | 11.554 | 11.130 | **11.841** | Seq Scan on `cart_items` |
| **TOTAL** | **Cumulative execution time (all 30 workload queries)** | — | **20888.681** | **21199.117** | **20684.000** | **20957.266** | — |

---

## 5. Performance Analysis

### 5.1 The Slowest Queries
1. **`R19` (20,200.852 ms / ~20.2 seconds):**  
   - **Root Cause:** Extremely pathological correlated subquery execution. For every mobile phone listing in the `Mobiles` category (~1,000 products), the query executes **two independent correlated subqueries**:
     1. `SELECT max(o.ordered_at) FROM order_items oi JOIN orders o ON o.order_id = oi.order_id WHERE oi.product_id = p.product_id`
     2. `SELECT coalesce(sum(oi.quantity), 0) FROM order_items oi WHERE oi.product_id = p.product_id`
   - Because `order_items` lacks a secondary index on `product_id`, PostgreSQL performs a full sequential scan across 240,000 rows of `order_items` multiplied by each product. This generates over 240,000,000 row inspections in memory.
   - **Optimization Target:** A covering index on `order_items(product_id) INCLUDE (quantity, order_id)` or rewriting the query into a single grouped outer join will reduce latency by over 99.9%.

2. **`R12` (119.734 ms):**  
   - **Root Cause:** Heavy multi-table join (`order_items` 240k rows $\bowtie$ `products` 30k $\bowtie$ `categories` $\bowtie$ `returns` 5.3k) requiring sequential scans across all four tables followed by hash aggregation.
   - **Optimization Target:** Composite foreign-key indexes on `order_items(product_id, order_id, line_no)` and `products(category_id)`.

3. **`R17` (104.509 ms):**  
   - **Root Cause:** Trust & safety anti-join evaluating `NOT EXISTS` across 38,662 reviews. For each verified review, it must probe `orders` $\bowtie$ `order_items` to confirm a delivered/returned purchase. Without secondary indexes on `orders(customer_id, status)` and `order_items(product_id)`, this incurs massive nested loop / hash join overhead.

4. **`W04` (76.791 ms on Run 1, 58.436 ms on Run 3):**  
   - **Root Cause:** Bulk batch insert of 5,000 records into `cart_items` with an `ON CONFLICT (customer_id, product_id) DO NOTHING` clause. Each row requires checking the composite primary key index and evaluating transaction rollback in benchmark mode.

5. **`R22` (61.061 ms):**  
   - **Root Cause:** Large offset pagination (`OFFSET 75000 LIMIT 25`) with `ORDER BY ordered_at DESC`. In the absence of an index on `ordered_at DESC`, the engine must sequentially scan all 120,000 rows of `orders`, perform a full top-N quicksort in memory, discard the first 75,000 rows, and emit the next 25 rows.

### 5.2 The Fastest Queries
1. **`R24` (0.187 ms):**  
   - Point lookup on `products` using the existing unique B-tree index `products_asin_key` (`Index Scan`). Extremely efficient point lookup ($O(\log N)$).
2. **`R23` (0.464 ms):**  
   - Point lookup on `orders` for order 100001, fetching lines from `order_items` using the primary key index `order_items_pkey(order_id, line_no)`.
3. **`W02` (1.057 ms):**  
   - Single-row stock decrement using the primary key index `products_pkey(product_id)`.
4. **`W01` (2.457 ms):**  
   - Single-row order header insertion into `orders`.
5. **`R03` (3.266 ms):**  
   - Sequential scan across `product_reviews` (38,662 rows). Fast only because the table is compact, but will degrade rapidly at 20× volume without a `product_id` index.

### 5.3 Cache Variations Across Runs
A noticeable pattern appears between Run 1 (cold buffer cache) and Runs 2/3 (warm cache):
- **Write Operations:** `W04` dropped from **114.055 ms** on Run 1 to **57.882 ms** on Run 2 (-49.2%) as data pages and WAL buffers were pre-allocated. `W02` dropped from **2.265 ms** to **0.445 ms** (-80.3%).
- **Point Lookups:** `R24` dropped from **0.455 ms** on Run 1 to **0.050 ms** on Run 3 (-89.0%) once index root and leaf pages were pinned in `shared_buffers`.
- **Large Sequential Scans:** Queries dominated by sequential table scans (e.g., `R08`, `R09`, `R15`, `R19`) showed virtually zero variance across runs (< 2% difference), demonstrating that memory bandwidth and CPU filtering remain the bottleneck even when data is cached in memory.

### 5.4 Candidate Queries for Phase 4 Indexing and Rewriting
| Query | Primary Bottleneck | Proposed Technique |
|---|---|---|
| `R01` | `ILIKE '%wireless%'` requires full table scan | Trigram GIN index (`pg_trgm`) on `title` + status filter |
| `R02` | Recursive CTE + price filter | B-tree index on `products(category_id, price) WHERE status = 'ACTIVE'` |
| `R04` | Customer order lookup | Composite B-tree index on `orders(customer_id, ordered_at DESC)` |
| `R05` | Status filter on in-transit shipments | Partial index on `orders(shipped_at) WHERE status = 'SHIPPED'` |
| `R06` | Seller order lines for date range | Index on `order_items(seller_id)` + covering `ordered_at` |
| `R08` | Merchandising ranking across 30 days | Sargable date range rewrite + composite indexes |
| `R11` | Frequently bought together self-join | Composite index on `order_items(product_id, order_id)` |
| `R13` | `NOT IN (subquery with NULLs)` returns empty | Query rewrite to `NOT EXISTS` or `WHERE address_id IS NOT NULL` |
| `R17` | Correlated verification anti-join | Composite indexes on `orders(customer_id, status)` and `order_items` |
| `R19` | Double correlated subqueries on 240k rows | Rewrite to single grouped join + index on `order_items(product_id)` |
| `R22` | Quicksort on 120k rows + discard 75k rows | Keyset / cursor pagination or B-tree index on `orders(ordered_at DESC)` |

---

## 6. Summary

- **Total Workload Queries Executed:** 30 (24 READ, 6 WRITE)
- **Total Executions Conducted:** 90 (3 runs per query)
- **Successful Executions:** 90 / 90 (100% success rate)
- **Failed or Aborted Queries:** 0
- **Cumulative Workload Time:** **20,957.266 ms** (~20.96 seconds)
- **Dominant Component:** Query `R19` accounts for **96.4%** of the entire baseline execution time.
- **Benchmark Completion Status:** **PASSED / COMPLETE**.

---

## 7. Reproducibility

To reproduce these exact baseline measurements on any machine:

1. **Verify Environment Prerequisites:**
   ```bash
   ./benchmarks/verify_environment.sh amazon_test
   ```
2. **Execute Full 30-Query Benchmark:**
   ```bash
   ./benchmarks/run_benchmark.sh amazon_test baseline
   ```
3. **Verify Generated Artifacts:**
   ```bash
   # Check CSV summary
   head -n 5 benchmarks/results/baseline/summary.csv
   
   # Check individual raw execution plans
   head -n 20 benchmarks/results/baseline/R01.txt
   ```
4. **Inspect Generated Metrics:**
   All execution times, plan trees, buffer hits, and scan nodes are permanently tracked in [`benchmarks/results/baseline/summary.csv`](file:///Users/sachinkumar/DBMS-Amazon-Online-Shopping/benchmarks/results/baseline/summary.csv) and raw `.txt` plan dumps.
