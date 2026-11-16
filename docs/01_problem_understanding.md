# Phase 1: Problem Understanding

**Team:** T0103 – SkillSwap · **Section:** A · **Database:** PostgreSQL 18

---

## 1. Project Overview

Amazon India's marketplace database was built quickly by a prior engineering team. No documented schema survives—only raw data exports (11 CSV files, ~120,000 orders spanning Jan 2025 – Jun 2026). Product teams have raised nine performance and data-quality complaints. Our job is to rebuild a correct, well-constrained relational schema from the data, measure query performance, optimise it, and prove scalability for a 20× traffic surge expected during the next festive season.

## 2. Background and Context

Amazon India operates a multi-seller e-commerce marketplace. Sellers list products in a hierarchical category tree (e.g., Electronics → Mobiles). Customers browse, add items to a cart, check out to saved delivery addresses, pay via multiple methods (UPI, Card, COD, Net Banking, EMI, Gift Card), and track shipments. Returns and reviews form separate workflows. Prime membership provides faster delivery and special eligibility. The database serves both real-time customer-facing pages and internal analytics/reporting dashboards.

## 3. Problem Statement

Nine problems have been reported by internal teams. These fall into two categories: **customer-facing / real-time** latency issues that degrade user experience, and **reporting / analytics** timeouts that block business decisions.

## 4. Objectives

1. Design a correct, normalized relational schema from the raw data exports.
2. Define appropriate constraints (PK, FK, UNIQUE, NOT NULL, CHECK) that enforce data integrity.
3. Load all 555,574 seed records without errors.
4. Document the schema with an ER diagram, data dictionary, and normalization analysis.
5. Establish a baseline for all 30 benchmark queries in later phases.

## 5. Scope

- **In scope:** Schema design, constraint definition, data loading, ER diagramming, normalization analysis for the 11 supplied CSV tables, and preparation for the 30 benchmark queries.
- **Out of scope:** Application code, authentication, front-end UI, payment gateway integration, external API integrations, advanced analytics pipelines.

## 6. Stakeholders and User Roles

| Stakeholder | Role | Concerned with |
|---|---|---|
| **Customer** | End-user shopper | Search, browse, cart, orders, reviews, fast page loads |
| **Seller** | Business listing products | Seller Central dashboards, stock management, pricing, order fulfilment |
| **Category Manager** | Internal merchandiser | Category pages, return rates, best-seller reports |
| **Logistics Team** | Shipping & delivery operations | Shipment tracking, packing queue, delivery SLAs |
| **Prime Team** | Prime membership programme | Prime vs non-Prime analytics, eligibility flagging |
| **Marketing Team** | Campaign managers | Abandoned-cart campaigns, deals pages |
| **Trust & Safety** | Fraud / quality team | Fake review detection, verified-purchase auditing |
| **Finance / Analytics** | Revenue & reporting | GMV, AOV, spending tiers, return rates, daily sales |
| **Admin / DBA** | System administrators | Data quality, paginated order views, maintenance |

## 7. Problem Analysis (P1–P9)

| # | Problem Summary | Affected Stakeholder(s) | Classification | Related Queries |
|---|---|---|---|---|
| **P1** | Search and category pages feel sluggish, especially when categories have many sub-categories. The recursive category tree traversal combined with product filtering is slow. | Customer, Category Manager | **Customer-facing / Real-time** | R01, R02, R14 |
| **P2** | Product pages (ratings breakdown, "frequently bought together") load slowly for popular products. Aggregation across reviews and self-joins on order_items are expensive. | Customer | **Customer-facing / Real-time** | R03, R11, R24 |
| **P3** | "Your Orders" page and order details take too long. Joining orders with order_items per customer is slow at scale. | Customer | **Customer-facing / Real-time** | R04, R23 |
| **P4** | Seller Central dashboards (monthly orders, low-stock alerts, price changes) are slow. Filtering order_items by seller across large order tables is expensive. | Seller | **Mixed: Real-time dashboards + Reporting** | R06, R07, R15, W02, W03 |
| **P5** | Logistics cannot quickly find stuck/late shipments, and the packing queue lags. Status-based filtering on the large orders table without proper indexing. | Logistics | **Customer-facing / Real-time** | R05, R21, W05 |
| **P6** | Address clean-up report incorrectly says no address is unused. Query R13 uses `NOT IN` with a subquery that may contain NULLs, causing all rows to be filtered out due to SQL's three-valued logic. | Admin, Data Quality | **Reporting / Analytics** | R13 |
| **P7** | Abandoned-cart campaigns and cart clean-up jobs run too long. Full table scans on cart_items and correlated subqueries against orders. | Marketing | **Reporting / Analytics** | R10, W04, W06 |
| **P8** | Trust & Safety needs to catch fake "verified purchase" reviews and analyse review text. Complex NOT EXISTS with multi-table joins and ILIKE text search. | Trust & Safety | **Reporting / Analytics** | R16, R17 |
| **P9** | Category, Prime, and finance reports (returns, AOV, GMV, spend tiers) time out. Heavy aggregation across orders, order_items, customers, and categories. Traffic will grow 20× by next festive season. | Analytics, Finance, Prime Team, Category Manager | **Reporting / Analytics** | R08, R09, R12, R18, R19, R20, R22, W01 |

## 8. Main Business Processes

1. **Product Listing:** Sellers list products in categories, set prices, manage stock.
2. **Search & Browse:** Customers search by keyword, browse by category tree, filter by price/rating.
3. **Cart Management:** Add/remove items, quantity changes, abandoned-cart cleanup.
4. **Checkout & Payment:** Place order, select address (except digital products), choose payment method.
5. **Order Fulfilment:** Order → Placed → Packed → Shipped → Out for Delivery → Delivered.
6. **Returns & Refunds:** Customer requests return, item picked up, refund processed or rejected.
7. **Reviews & Ratings:** Customers write reviews (verified/unverified), vote on helpfulness.
8. **Seller Management:** Seller registration, performance monitoring, suspension handling.
9. **Reporting & Analytics:** GMV, AOV, return rates, spending tiers, category performance.

## 9. Functional Requirements

1. Store and retrieve products with category hierarchy (parent–child tree).
2. Support multi-seller marketplace (multiple sellers list independent products).
3. Maintain customer profiles with Prime membership tracking.
4. Store multiple delivery addresses per customer with a default address flag.
5. Process orders with multiple line items from different sellers.
6. Track order lifecycle (PLACED → PACKED → SHIPPED → OUT_FOR_DELIVERY → DELIVERED / CANCELLED / RETURNED).
7. Handle returns with reasons, status tracking, and conditional refund amounts.
8. Store product reviews with verified-purchase flagging and helpfulness votes.
9. Manage shopping carts with per-customer, per-product uniqueness.
10. Support digital products that require no delivery address.

## 10. Non-Functional Requirements

1. **Performance:** Customer-facing queries must execute under 5 ms; reports under 5 seconds.
2. **Scalability:** Schema must support 20× data growth without structural changes.
3. **Data Integrity:** All constraints must accept all seed data rows; referential integrity enforced.
4. **Consistency:** Naming conventions and data types must be uniform across all tables.
5. **Portability:** Schema must be executable on PostgreSQL 15+.

## 11. Data Requirements

| Entity | Records | Key Attributes |
|---|---:|---|
| Cities | 10 | city_id, city_name, state |
| Categories | 40 | category_id, category_name, parent_category_id, is_digital |
| Sellers | 1,500 | seller_id, business_name, gstin, city_id, seller_rating, status |
| Products | 30,000 | product_id, asin, seller_id, category_id, title, brand, mrp, price, stock_qty, etc. |
| Customers | 30,000 | customer_id, full_name, email, phone, city_id, is_prime, prime_since |
| Addresses | 45,000 | address_id, customer_id, label, line1, city_id, pincode, is_default |
| Orders | 120,000 | order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status |
| Order Items | 240,000 | order_id, line_no, product_id, seller_id, quantity, unit_price |
| Returns | 5,374 | return_id, order_id, line_no, reason, requested_at, status, refund_amount |
| Product Reviews | 38,662 | review_id, product_id, customer_id, rating, title, body, verified_purchase, helpful_votes |
| Cart Items | 44,998 | customer_id, product_id, quantity, added_at |

**Total: 555,584 records across 11 tables.**

## 12. Database Assumptions

1. Each product belongs to exactly one seller and one category.
2. Categories form a two-level tree: 8 top-level parents and 32 sub-categories.
3. Orders without an `address_id` contain only digital products (E-Books or Gift Cards).
4. `prime_since` is NULL when `is_prime` is false; always populated when `is_prime` is true.
5. `shipped_at` is NULL for orders not yet shipped (PLACED, PACKED, CANCELLED statuses).
6. `delivered_at` is NULL for orders not yet delivered.
7. `refund_amount` is populated only when a return has status `REFUNDED`.
8. A customer can have multiple addresses but each customer has exactly one default address per label type.
9. `(customer_id, product_id)` is unique in `cart_items` (one cart entry per product per customer).
10. `avg_rating` and `review_count` in products are derived/denormalized from `product_reviews`.
11. `seller_id` in `order_items` is denormalized from `products` (snapshot at time of order).
12. `total_amount` in `orders` is derived from `order_items` (sum of quantity × unit_price).
13. Product `price` must not exceed `mrp`.
14. ASIN (Amazon Standard Identification Number) is unique per product.
15. Customer email and phone are unique identifiers.

## 13. Business Rules and Constraints

1. **Price ≤ MRP**: A product's selling price must never exceed its maximum retail price.
2. **Stock non-negative**: `stock_qty` must be ≥ 0.
3. **Quantity positive**: Order item and cart item quantities must be ≥ 1.
4. **Rating range**: Product review ratings must be between 1 and 5.
5. **Helpful votes non-negative**: Cannot be negative.
6. **Valid statuses**: Orders, products, sellers, and returns have enumerated status values.
7. **Valid payment methods**: UPI, CARD, COD, GIFT_CARD, NETBANKING, EMI.
8. **Valid address labels**: HOME, WORK.
9. **Valid return reasons**: QUALITY_ISSUE, WRONG_ITEM, DAMAGED, SIZE_ISSUE, NOT_AS_DESCRIBED, NO_LONGER_NEEDED.
10. **Referential integrity**: All foreign keys must reference valid parent records.
11. **GSTIN format**: 15-character alphanumeric code for sellers.
12. **Pincode format**: 6-digit numeric code for Indian postal codes.

## 14. Expected Database Operations

| Operation Type | Examples | Frequency |
|---|---|---|
| **Point lookups** | Product by ASIN, order by ID, customer by ID | Very high (real-time) |
| **Range scans** | Orders by date, products by price range | High |
| **Aggregations** | Rating breakdowns, GMV, AOV, return rates | Medium (reports) |
| **Joins** | Order details (orders + items + products + sellers) | Very high |
| **Text search** | Product title ILIKE, review body ILIKE | Medium |
| **Recursive queries** | Category tree traversal | Medium |
| **Inserts** | New orders, cart additions, reviews | High (real-time) |
| **Updates** | Stock decrement, price changes, status transitions | High |
| **Deletes** | Cart cleanup, old data archival | Low (batch) |

## 15. Challenges and Limitations

1. **NULL-handling in R13**: `NOT IN (subquery)` returns no rows when the subquery contains NULLs—this is the data-quality bug reported in P6.
2. **Denormalized columns**: `avg_rating`, `review_count`, `seller_id` in order_items, and `total_amount` in orders are redundant but kept for query performance (documented trade-off).
3. **Two-level category tree**: The recursive CTE in R02 works for deeper trees, but the seed data only has two levels.
4. **Digital-product address rule**: Orders for digital products have NULL `address_id`; the schema must allow this while still enforcing FK for physical orders.
5. **Scale preparation**: The 20× growth target means the schema must avoid structural bottlenecks (e.g., excessive OFFSET pagination in R22).

## 16. Expected Outcomes

1. A fully normalised (3NF/BCNF) schema with documented trade-offs for intentional denormalization.
2. All 555,584 records loaded without errors, verified by row counts and integrity checks.
3. An ER diagram that accurately represents all 11 entities and their relationships.
4. A schema that supports all 30 benchmark queries without modification.
5. A solid foundation for subsequent optimization and scalability phases.

