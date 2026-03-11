---
name: backend-perf
description: Use when assessing API response times, diagnosing slow database queries, evaluating caching strategies, or profiling backend resource usage. Guides systematic measurement of server-side performance from request to response.
---

# Backend Performance Assessment

Measure at each layer. Bottlenecks hide behind averages — find the slowest link in the chain.

## Process

### 1. Identify Bottleneck Layer

Start by measuring where time is spent. For any slow endpoint:

```
Total response time = TTFB + DB time + App logic + External API calls + Serialization
```

**Decision tree:**
- TTFB > 200ms on first byte → server-side bottleneck (continue below)
- TTFB fast but response slow → large payload, check serialization and transfer
- Inconsistent latency → likely external dependency or resource contention

**Quick layer test:** Add timing logs at each boundary:
```
[request start] → [after auth] → [after DB queries] → [after business logic] → [before response]
```

The largest gap is your bottleneck layer. Focus there.

### 2. Database Query Analysis

**Enable query logging** to see what's actually running:

```sql
-- PostgreSQL
SET log_min_duration_statement = 0;  -- log all queries (temporary!)
SET log_statement = 'all';

-- MySQL
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0;
```

**Count queries per request.** If a single API call generates dozens of queries, you likely have N+1 problems.

**Detect N+1 pattern:**
```
GET /api/posts
  SELECT * FROM posts                    -- 1 query
  SELECT * FROM users WHERE id = 1       -- N queries (one per post)
  SELECT * FROM users WHERE id = 2
  SELECT * FROM users WHERE id = 3
  ...
```

**Fix N+1:**
- ORM eager loading: `Post.findAll({ include: User })` / `Post.objects.select_related('user')`
- Batch queries: `SELECT * FROM users WHERE id IN (1, 2, 3)`
- DataLoader pattern for GraphQL

**Query count thresholds:**
| Operation | Expected Queries |
|-----------|-----------------|
| Single resource GET | 1-3 |
| List endpoint | 2-5 |
| Create/Update | 2-4 |
| Complex dashboard | 5-10 |
| > 10 per request | Investigate |

### 3. EXPLAIN Plan Analysis

Run EXPLAIN on slow queries to understand execution:

```sql
-- PostgreSQL
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;

-- MySQL
EXPLAIN ANALYZE SELECT ...;
```

**Decision tree for EXPLAIN results:**

- **Sequential Scan / Full Table Scan** on large table?
  - Is there a WHERE clause? → Add index on filtered column(s)
  - Scanning < 10% of rows? → Index would help
  - Scanning > 50% of rows? → Sequential scan may actually be optimal
- **Nested Loop** with high row counts?
  - Check join column has index
  - Consider if a hash join would be better (PostgreSQL: `SET enable_nestloop = off` to test)
- **Sort** without index?
  - If sorting by a column frequently queried → add index
  - `LIMIT` + `ORDER BY` without index = full sort then truncate
- **High actual time vs estimated rows?**
  - Run `ANALYZE tablename` to update statistics

See `references/database-analysis-guide.md` for database-specific EXPLAIN syntax.

### 4. API Endpoint Profiling

**Response time thresholds by operation:**

| Operation | Target | Acceptable | Slow |
|-----------|--------|-----------|------|
| Read (cached) | < 10ms | < 50ms | > 50ms |
| Read (DB) | < 50ms | < 200ms | > 200ms |
| Write (simple) | < 100ms | < 500ms | > 500ms |
| Write (complex) | < 500ms | < 1s | > 1s |
| Search/filter | < 200ms | < 1s | > 1s |
| Report/aggregation | < 1s | < 5s | > 5s |

**Profiling approach:**
1. Measure total endpoint time
2. Break down by layer (auth, validation, DB, business logic, serialization)
3. Compare against thresholds
4. Focus optimization on the largest time consumer

### 5. Caching Assessment

**Decision tree — should you cache this?**

```
Is data read frequently?
├── No → Don't cache
└── Yes → Is data expensive to compute/fetch?
    ├── No → Don't cache (DB is fast enough)
    └── Yes → Can users tolerate stale data?
        ├── No → Cache with short TTL or cache-aside with invalidation
        └── Yes → Cache aggressively (longer TTL)
```

**Cache hit rate evaluation:**
- > 90% hit rate → caching is working well
- 50-90% hit rate → review TTL and invalidation strategy
- < 50% hit rate → cache may be counterproductive (overhead without benefit)

**Common caching layers:**
1. HTTP caching headers (Cache-Control, ETag) — client/CDN level
2. Application cache (Redis, Memcached) — shared across instances
3. In-process cache — single instance, fastest but not shared
4. Database query cache — often disabled in production (invalidation cost)

See `references/caching-patterns.md` for implementation patterns.

### 6. Resource Lifecycle

**Connection pooling:**
- Database connections: pool size = (core_count * 2) + effective_spindle_count (PostgreSQL rule of thumb)
- HTTP client connections: reuse connections, set reasonable pool limits
- Redis connections: use connection pooling, avoid connect-per-request

**Leak detection checklist:**
- Memory growing over time without load increase → likely a leak
- Connection count growing → connections not being returned to pool
- File descriptors growing → files/sockets not being closed
- Event listeners accumulating → missing cleanup/unsubscribe

**Check current resource usage:**
```bash
# Database connections (PostgreSQL)
SELECT count(*) FROM pg_stat_activity;
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

# Process memory (Node.js)
process.memoryUsage()

# Open file descriptors (Linux)
ls /proc/<pid>/fd | wc -l
```

### 7. Common Antipatterns Checklist

Review code for these patterns:

- [ ] **Unbounded queries** — `SELECT *` without `LIMIT`, loading entire tables into memory
- [ ] **Missing pagination** — list endpoints returning all records
- [ ] **Over-fetching** — selecting all columns when only a few are needed
- [ ] **Synchronous external calls** — blocking on third-party APIs in the request path
- [ ] **Missing database indexes** — queries filtering/sorting on unindexed columns
- [ ] **String concatenation for queries** — SQL injection risk AND prevents query plan caching
- [ ] **Logging in hot paths** — synchronous logging in every request handler
- [ ] **Large payloads** — returning nested objects when flat references suffice
- [ ] **Missing connection pooling** — creating new DB connections per request
- [ ] **Computed values on read** — calculating derived data on every request instead of on write

### 8. Report Findings

Organize by severity:

**Critical** (user-facing impact):
- Response times > 1s for common operations
- N+1 queries causing linear slowdown with data growth
- Missing indexes on tables > 10K rows
- Connection leaks or pool exhaustion

**Improvements** (measurable gains):
- Response times above target but below critical
- Caching opportunities for frequently-read, rarely-changed data
- Over-fetching that increases serialization and transfer time
- Missing pagination on growing datasets

**Observations** (preventive):
- Antipatterns that will cause issues at scale
- Opportunities for async processing (queues, background jobs)
- Monitoring gaps — metrics that should be tracked but aren't

Include specific numbers: query count, response times, row counts. Vague recommendations are not actionable.
