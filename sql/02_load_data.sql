-- =====================================================================
-- Amazon Online Shopping Database — Seed Data Loader
-- Team T0103 (SkillSwap) · Section A · PostgreSQL 18
--
-- Usage (from the project root directory):
--   psql -d <database> -f sql/02_load_data.sql
--
-- Prerequisites:
--   1. sql/01_schema.sql has been executed successfully.
--   2. seed_data/ directory exists in the project root (unzipped from seed_data.zip).
--
-- Tables are loaded in dependency-safe order (parents before children).
-- Uses \copy which reads files from the client machine (not the server).
-- The paths are relative to the directory where psql is launched.
-- =====================================================================

SET search_path TO amazon;

-- ----- Parent tables (no FK dependencies) -----

\echo 'Loading cities...'
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading categories...'
\copy categories FROM 'seed_data/categories.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ----- Second tier (depend on cities/categories) -----

\echo 'Loading sellers...'
\copy sellers FROM 'seed_data/sellers.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading customers...'
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ----- Third tier (depend on sellers, categories, customers, cities) -----

\echo 'Loading products...'
\copy products FROM 'seed_data/products.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading addresses...'
\copy addresses FROM 'seed_data/addresses.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ----- Fourth tier (depend on customers, addresses) -----

\echo 'Loading orders...'
\copy orders FROM 'seed_data/orders.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ----- Fifth tier (depend on orders, products, sellers) -----

\echo 'Loading order_items...'
\copy order_items FROM 'seed_data/order_items.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ----- Sixth tier (depend on order_items, products, customers) -----

\echo 'Loading returns...'
\copy returns FROM 'seed_data/returns.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading product_reviews...'
\copy product_reviews FROM 'seed_data/product_reviews.csv' WITH (FORMAT csv, HEADER true, NULL '')

\echo 'Loading cart_items...'
\copy cart_items FROM 'seed_data/cart_items.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ----- Update statistics for the query planner -----
ANALYZE;

-- ----- Verify row counts -----
\echo ''
\echo '========== Row Count Verification =========='
SELECT 'cities' AS table_name, count(*) AS rows FROM cities
UNION ALL SELECT 'categories', count(*) FROM categories
UNION ALL SELECT 'sellers', count(*) FROM sellers
UNION ALL SELECT 'products', count(*) FROM products
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'addresses', count(*) FROM addresses
UNION ALL SELECT 'orders', count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items
UNION ALL SELECT 'returns', count(*) FROM returns
UNION ALL SELECT 'product_reviews', count(*) FROM product_reviews
UNION ALL SELECT 'cart_items', count(*) FROM cart_items
ORDER BY 1;

\echo ''
\echo '========== Seed data loading complete =========='

