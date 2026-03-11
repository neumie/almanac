# Caching Patterns

## Cache-Aside (Lazy Loading)

Most common pattern. Application checks cache first, falls back to DB.

```
Read:
1. Check cache for key
2. Cache hit → return cached value
3. Cache miss → query DB, store in cache, return value

Write:
1. Write to DB
2. Invalidate cache key (delete, don't update)
```

**When to use:** Read-heavy workloads, data that can tolerate brief staleness.

**Pitfalls:**
- Cache stampede: many requests hit cache miss simultaneously → all query DB. Fix with locking or pre-warming.
- Stale data: cache doesn't know about direct DB updates. Set appropriate TTL.

```javascript
// Example: cache-aside in Node.js with Redis
async function getUser(id) {
  const cached = await redis.get(`user:${id}`);
  if (cached) return JSON.parse(cached);

  const user = await db.query('SELECT * FROM users WHERE id = $1', [id]);
  await redis.set(`user:${id}`, JSON.stringify(user), 'EX', 300); // 5 min TTL
  return user;
}

async function updateUser(id, data) {
  await db.query('UPDATE users SET ... WHERE id = $1', [id, ...data]);
  await redis.del(`user:${id}`); // Invalidate, don't update
}
```

## Write-Through

Cache is always in sync. Writes go through cache to DB.

```
Write:
1. Write to cache
2. Cache writes to DB (synchronously)
3. Return success

Read:
1. Always read from cache (it's always current)
```

**When to use:** Data where consistency is critical and reads far outnumber writes.

**Pitfalls:**
- Write latency increases (two writes per operation)
- Cache fills with data that may never be read

## Write-Behind (Write-Back)

Cache absorbs writes, flushes to DB asynchronously.

```
Write:
1. Write to cache
2. Return success immediately
3. Cache flushes to DB in background (batched)
```

**When to use:** Write-heavy workloads where brief data loss risk is acceptable (analytics, counters).

**Pitfalls:**
- Data loss if cache crashes before flush
- Complexity in ordering and conflict resolution

## Cache Invalidation Strategies

### TTL-Based
```javascript
redis.set('key', value, 'EX', 300); // Expires after 5 minutes
```
Simple but allows staleness up to TTL duration.

### Event-Based
```javascript
// On user update, invalidate all related caches
async function onUserUpdate(userId) {
  await Promise.all([
    redis.del(`user:${userId}`),
    redis.del(`user:${userId}:posts`),
    redis.del(`user:${userId}:profile`),
  ]);
}
```
Precise but requires tracking all cache keys per entity.

### Version-Based
```javascript
// Include version in cache key
const version = await redis.get('users:version'); // incremented on any user change
const cached = await redis.get(`users:list:v${version}`);
```
Atomic invalidation of groups of keys.

## Redis vs In-Process Cache

| Aspect | Redis | In-Process (Map/LRU) |
|--------|-------|---------------------|
| Shared across instances | Yes | No |
| Network latency | ~0.5ms | ~0.001ms |
| Memory limit | Dedicated server | Shares app memory |
| Persistence | Optional | None (lost on restart) |
| Eviction policies | LRU, LFU, TTL | Custom |
| Best for | Multi-instance apps | Single-instance, hot data |

**Rule of thumb:** Use in-process for data accessed > 100 times/second that rarely changes (config, feature flags). Use Redis for everything else in multi-instance deployments.

## HTTP Caching Headers

### Cache-Control
```
# Public, cacheable by CDN and browser for 1 hour
Cache-Control: public, max-age=3600

# Private, browser only, 5 minutes
Cache-Control: private, max-age=300

# No caching (dynamic content, user-specific)
Cache-Control: no-store

# Revalidate every time (ETag/Last-Modified)
Cache-Control: no-cache
```

### ETag
```javascript
// Server sets ETag on response
res.setHeader('ETag', hash(responseBody));

// Client sends If-None-Match on next request
// Server returns 304 Not Modified if ETag matches
if (req.headers['if-none-match'] === currentETag) {
  return res.status(304).end();
}
```

### Stale-While-Revalidate
```
Cache-Control: max-age=60, stale-while-revalidate=300
```
Serve stale content immediately while fetching fresh content in background. Great for content that changes but doesn't need to be instantly fresh.

## Cache Sizing

**Estimate memory needs:**
```
entries × average_entry_size_bytes = total_cache_bytes
```

**Set max memory with eviction:**
```
# Redis
maxmemory 256mb
maxmemory-policy allkeys-lru
```

**Monitor hit rates:**
```bash
# Redis
redis-cli INFO stats | grep keyspace
# keyspace_hits: 1234567
# keyspace_misses: 12345
# hit rate = hits / (hits + misses)
```
