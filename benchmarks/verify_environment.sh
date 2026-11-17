#!/usr/bin/env bash
# =====================================================================
# Amazon Online Shopping Database: Baseline Environment Verifier
# Team: T0103 (SkillSwap) · Section: A · Database: PostgreSQL 18
#
# Verifies that PostgreSQL is running, schema 'amazon' is populated,
# row counts match the 120,000-order seed data, and no secondary
# indexes exist prior to baseline benchmarking.
#
# Usage: ./benchmarks/verify_environment.sh [database_name]
# =====================================================================
set -euo pipefail

DB="${1:-amazon_test}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Verifying PostgreSQL Baseline Environment for: $DB ==="

# 1. Check psql
if ! command -v psql >/dev/null 2>&1; then
    if [ -x "/Applications/Postgres.app/Contents/Versions/latest/bin/psql" ]; then
        export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"
    else
        echo "ERROR: psql not found in PATH." >&2
        exit 1
    fi
fi

# 2. Check PostgreSQL connection
if ! psql -d "$DB" -c "SELECT 1;" >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to database '$DB'." >&2
    exit 1
fi
PG_VER=$(psql -d "$DB" -t -A -c "SELECT version();")
echo "[✓] PostgreSQL connected: $PG_VER"

# 3. Verify schema 'amazon' exists
SCHEMA_EXISTS=$(psql -d "$DB" -t -A -c "SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'amazon';")
if [ "$SCHEMA_EXISTS" -ne 1 ]; then
    echo "ERROR: Schema 'amazon' does not exist in database '$DB'." >&2
    exit 1
fi
echo "[✓] Schema 'amazon' exists"

# 4. Verify all 11 tables and row counts
echo "[*] Checking table row counts..."
EXPECTED_COUNTS=(
    "cities:10"
    "categories:40"
    "sellers:1500"
    "products:30000"
    "customers:30000"
    "addresses:45000"
    "orders:120000"
    "order_items:240000"
    "returns:5374"
    "product_reviews:38662"
    "cart_items:44998"
)

TOTAL_ROWS=0
for entry in "${EXPECTED_COUNTS[@]}"; do
    tbl="${entry%%:*}"
    expected="${entry##*:}"
    actual=$(psql -d "$DB" -t -A -c "SELECT count(*) FROM amazon.$tbl;")
    if [ "$actual" -ne "$expected" ]; then
        echo "ERROR: Row count mismatch for table '$tbl': expected $expected, got $actual" >&2
        exit 1
    fi
    TOTAL_ROWS=$((TOTAL_ROWS + actual))
    printf "    %-16s %8d rows [✓]\n" "$tbl" "$actual"
done
echo "[✓] All 11 tables verified (Total: $TOTAL_ROWS rows)"

# 5. Verify no secondary indexes exist (pure baseline)
INDEX_COUNT=$(psql -d "$DB" -t -A -c "
SELECT count(*)
FROM pg_indexes
WHERE schemaname = 'amazon'
  AND indexname NOT LIKE '%_pkey'
  AND indexname NOT LIKE '%_key';")

if [ "$INDEX_COUNT" -ne 0 ]; then
    echo "WARNING: $INDEX_COUNT secondary index(es) detected in 'amazon' schema! Baseline requires unindexed tables." >&2
else
    echo "[✓] Verified pure baseline state: 0 secondary indexes (only PK/UNIQUE constraints exist)"
fi

# 6. Verify workload file
WORKLOAD="$ROOT/queries/workload_30.sql"
if [ ! -f "$WORKLOAD" ]; then
    echo "ERROR: Workload file '$WORKLOAD' not found." >&2
    exit 1
fi
QUERY_COUNT=$(grep -cE '^-- @[RW][0-9]+' "$WORKLOAD" || true)
if [ "$QUERY_COUNT" -ne 30 ]; then
    echo "ERROR: Expected 30 queries in workload, found $QUERY_COUNT" >&2
    exit 1
fi
echo "[✓] Workload file verified: 30 queries present"

# 7. Verify benchmark runner script
RUNNER="$ROOT/benchmarks/run_benchmark.sh"
if [ ! -x "$RUNNER" ]; then
    chmod +x "$RUNNER"
fi
echo "[✓] Benchmark runner verified: $RUNNER"

echo "=== Environment verification complete: Ready for baseline benchmarking ==="
