# Database Analysis Guide

## PostgreSQL

### EXPLAIN Syntax
```sql
-- Basic plan
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- With execution stats (actually runs the query)
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT * FROM orders WHERE user_id = 42;

-- JSON format for programmatic parsing
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM orders WHERE user_id = 42;
```

### Reading EXPLAIN Output
Key things to look for:
- **Seq Scan** — full table scan, may need index
- **Index Scan** — using an index, generally good
- **Index Only Scan** — best case, data served from index alone
- **Bitmap Heap Scan** — index used but many rows matched, reads heap in batches
- **Nested Loop** — fine for small result sets, bad for large joins
- **Hash Join** — good for large joins with equality conditions
- **Sort** — in-memory if `Sort Method: quicksort`, spills to disk if `external merge`
- **actual time** — first row..last row in ms. Large gap = streaming results
- **rows** — planned vs actual. Large discrepancy = stale statistics, run `ANALYZE`

### Index Types
```sql
-- B-tree (default, most common)
CREATE INDEX idx_orders_user ON orders (user_id);

-- Composite (for multi-column WHERE/ORDER BY)
CREATE INDEX idx_orders_user_date ON orders (user_id, created_at DESC);

-- Partial (for filtered subsets)
CREATE INDEX idx_active_orders ON orders (user_id) WHERE status = 'active';

-- GIN (for array/JSONB/full-text search)
CREATE INDEX idx_tags ON posts USING GIN (tags);

-- Covering index (Index Only Scan)
CREATE INDEX idx_orders_cover ON orders (user_id) INCLUDE (total, status);
```

### Slow Query Log
```sql
-- postgresql.conf or ALTER SYSTEM
ALTER SYSTEM SET log_min_duration_statement = 100;  -- log queries > 100ms
SELECT pg_reload_conf();

-- Check current slow queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active' AND now() - pg_stat_activity.query_start > interval '1 second';
```

### Useful Statistics Queries
```sql
-- Table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(oid))
FROM pg_class WHERE relkind = 'r' ORDER BY pg_total_relation_size(oid) DESC LIMIT 10;

-- Index usage
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes ORDER BY idx_scan ASC;

-- Unused indexes (candidates for removal)
SELECT indexrelid::regclass, idx_scan FROM pg_stat_user_indexes WHERE idx_scan = 0;

-- Cache hit ratio (should be > 99%)
SELECT sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) AS ratio
FROM pg_statio_user_tables;
```

## MySQL

### EXPLAIN Syntax
```sql
-- Basic plan
EXPLAIN SELECT * FROM orders WHERE user_id = 42;

-- With execution stats (MySQL 8.0+)
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 42;

-- Extended information
EXPLAIN FORMAT=JSON SELECT * FROM orders WHERE user_id = 42;
```

### Reading EXPLAIN Output
Key columns:
- **type**: `ALL` (full scan, bad) → `index` → `range` → `ref` → `eq_ref` → `const` (best)
- **key**: which index is used, NULL = no index
- **rows**: estimated rows to examine
- **Extra**:
  - `Using index` — covering index, good
  - `Using filesort` — extra sort pass, consider index
  - `Using temporary` — temp table created, optimize query
  - `Using where` — filtering after fetch, index might help

### Index Types
```sql
-- Standard B-tree
CREATE INDEX idx_orders_user ON orders (user_id);

-- Composite
CREATE INDEX idx_orders_user_date ON orders (user_id, created_at);

-- Full-text
CREATE FULLTEXT INDEX idx_content ON posts (title, body);

-- Prefix index (for long strings)
CREATE INDEX idx_email ON users (email(50));
```

### Slow Query Log
```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.1;  -- 100ms
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Check current log location
SHOW VARIABLES LIKE 'slow_query_log_file';
```

## SQLite

### EXPLAIN Syntax
```sql
-- Query plan
EXPLAIN QUERY PLAN SELECT * FROM orders WHERE user_id = 42;

-- Full bytecode (rarely needed)
EXPLAIN SELECT * FROM orders WHERE user_id = 42;
```

### Reading EXPLAIN QUERY PLAN
- `SCAN orders` — full table scan
- `SEARCH orders USING INDEX idx_user (user_id=?)` — index lookup
- `SEARCH orders USING COVERING INDEX ...` — index-only scan
- `USE TEMP B-TREE FOR ORDER BY` — sorting without index

### Index Creation
```sql
CREATE INDEX idx_orders_user ON orders (user_id);
CREATE INDEX idx_orders_compound ON orders (user_id, created_at);

-- Check existing indexes
SELECT * FROM sqlite_master WHERE type = 'index';

-- Analyze for query planner
ANALYZE;
```

## Index Decision Tree

```
Query has WHERE clause?
├── No → Probably don't need an index for this query
└── Yes → Column(s) in WHERE indexed?
    ├── Yes → Check if index is being used (EXPLAIN)
    │   ├── Used → Check selectivity (few rows matched = good)
    │   └── Not used → Statistics stale? Run ANALYZE. Wrong index type?
    └── No → Is the table > 1000 rows?
        ├── No → Index overhead may not be worth it
        └── Yes → Add index. Consider:
            ├── Single column → simple B-tree
            ├── Multiple columns in WHERE → composite index (most selective first)
            ├── WHERE + ORDER BY → composite covering both
            ├── Array/JSON field → GIN (PostgreSQL) or generated column + index
            └── Only subset of rows queried → partial index (PostgreSQL)
```
