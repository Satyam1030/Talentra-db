# Talentra — Phase 1: Problems & Optimizations Guide

---

## Problem Categories Overview

| Category | Risk Level | Tables Affected |
|---|---|---|
| Missing or wrong indexes | 🔴 Critical | job_application, candidate_profile |
| N+1 query problem | 🔴 Critical | candidate_profile + child tables |
| Duplicate application race condition | 🔴 Critical | job_application |
| Full table scans on soft-deleted rows | 🔴 Critical | candidate_profile, job_requirement |
| Salary / date constraint bypass | 🟡 Medium | job_requirement, candidate_experience |
| Unbounded text search | 🟡 Medium | job_requirement, candidate_profile |
| Foreign key lock contention | 🟡 Medium | All tables with FK |
| Sequence exhaustion (PK overflow) | 🟢 Low | All tables |
| Timezone inconsistency | 🟡 Medium | All TIMESTAMPTZ columns |

---

## Problem 1 — Full Table Scan on Soft-Deleted Rows 🔴

### What is the problem?
When you soft-delete a candidate (set `deleted_at`), they still physically exist in the table. Every search query must filter them out with `WHERE deleted_at IS NULL`. At 10 million rows with 500,000 deleted, PostgreSQL without a partial index scans all 10 million rows every time.

### How it fails at scale
```sql
-- This query at 10M rows WITHOUT optimization:
SELECT * FROM candidate_profile
WHERE city_id = 5
AND is_open_to_work = TRUE
AND deleted_at IS NULL;

-- Execution plan (BAD):
-- Seq Scan on candidate_profile
-- Filter: (deleted_at IS NULL AND city_id = 5)
-- Rows Removed by Filter: 9,800,000   ← scanning everything!
-- Execution time: 4200ms
```

### The Fix — Partial Indexes
```sql
-- Already added in Milestone 1.4 — verify these exist:

-- Index 1: Active candidates only
CREATE INDEX idx_candidate_profile_deleted
    ON candidate_profile (deleted_at)
    WHERE deleted_at IS NULL;

-- Index 2: Active job postings only
CREATE INDEX idx_jr_deleted
    ON job_requirement (deleted_at)
    WHERE deleted_at IS NULL;

-- Index 3: Active organizations only
CREATE INDEX idx_organization_deleted
    ON organization (deleted_at)
    WHERE deleted_at IS NULL;
```

### After optimization:
```sql
-- Execution plan (GOOD):
-- Index Scan using idx_candidate_profile_deleted
-- Filter: (city_id = 5 AND is_open_to_work = TRUE)
-- Rows Removed by Filter: 2,000       ← only active rows scanned!
-- Execution time: 3ms
```

> **Defense Answer:** "Partial indexes are one of PostgreSQL's most powerful features. By indexing only WHERE deleted_at IS NULL, we reduce the index size by the percentage of deleted rows and make every search query dramatically faster. At 10M rows with 5% deleted, this alone saves scanning 500,000 rows on every query."

---

## Problem 2 — The N+1 Query Problem 🔴

### What is the problem?
When displaying a candidate's full profile, a naive implementation fetches:
1. `candidate_profile` — 1 query
2. `candidate_skill` — 1 query
3. `candidate_experience` — 1 query
4. `candidate_education` — 1 query

For 100 candidates on a search results page = **400 queries** instead of 1.
At 10,000 concurrent users = **4,000,000 queries per second** — the database collapses.

### How it looks (BAD approach):
```sql
-- Query 1: Get candidates
SELECT * FROM candidate_profile WHERE city_id = 5 LIMIT 100;

-- Then for EACH of the 100 candidates, run 3 more queries:
-- Query 2 (×100): SELECT * FROM candidate_skill WHERE candidate_profile_id = ?
-- Query 3 (×100): SELECT * FROM candidate_experience WHERE candidate_profile_id = ?
-- Query 4 (×100): SELECT * FROM candidate_education WHERE candidate_profile_id = ?
-- Total: 301 queries for one page load!
```

### The Fix — Single JOIN Query
```sql
-- ONE query to get everything:
SELECT
    cp.id,
    cp.first_name,
    cp.last_name,
    cp.headline,
    cp.total_experience_months,

    -- Aggregate skills into a JSON array
    JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
        'skill',       s.skill_name,
        'level',       cs.proficiency_level,
        'months',      cs.experience_months,
        'is_primary',  cs.is_primary
    )) FILTER (WHERE cs.id IS NOT NULL) AS skills,

    -- Aggregate latest experience
    JSON_AGG(DISTINCT JSONB_BUILD_OBJECT(
        'company',     ce.company_name,
        'designation', ce.designation,
        'is_current',  ce.is_current
    )) FILTER (WHERE ce.id IS NOT NULL) AS experience

FROM candidate_profile cp
LEFT JOIN candidate_skill cs      ON cs.candidate_profile_id = cp.id
LEFT JOIN skill s                 ON s.id = cs.skill_id
LEFT JOIN candidate_experience ce ON ce.candidate_profile_id = cp.id
WHERE cp.city_id = 5
AND   cp.is_open_to_work = TRUE
AND   cp.deleted_at IS NULL
GROUP BY cp.id
LIMIT 100;
-- Total: 1 query. Always.
```

> **Defense Answer:** "The N+1 problem is the most common database performance killer in web applications. We solve it by using LEFT JOINs with JSON_AGG aggregation to fetch all related data in a single query. This reduces 300 round-trips to 1, which is critical at 10M candidates."

---

## Problem 3 — Duplicate Application Race Condition 🔴

### What is the problem?
Two browser tabs or two API requests submit an application for the same job at exactly the same time. Both check "does this application exist?" and both get "No" — so both INSERT. Result: duplicate applications.

### How it fails (BAD):
```sql
-- Request 1 checks:        Request 2 checks simultaneously:
SELECT COUNT(*) FROM job_application  |  SELECT COUNT(*) FROM job_application
WHERE job_requirement_id = 10         |  WHERE job_requirement_id = 10
AND candidate_profile_id = 99;        |  AND candidate_profile_id = 99;
-- Both get 0 (no existing row)       |  -- Both get 0 (no existing row)

-- Both INSERT:
INSERT INTO job_application ...       |  INSERT INTO job_application ...
-- RESULT: 2 duplicate rows!
```

### The Fix — Unique Constraint + ON CONFLICT
The UNIQUE constraint we added prevents this at the database level:
```sql
-- Already in our schema:
CONSTRAINT uq_candidate_job_application
    UNIQUE (job_requirement_id, candidate_profile_id)

-- In the application code, use ON CONFLICT to handle gracefully:
INSERT INTO job_application
    (job_requirement_id, candidate_profile_id, current_status_id, source_type)
VALUES
    (10, 99, 1, 'ORGANIC')
ON CONFLICT (job_requirement_id, candidate_profile_id)
DO NOTHING;  -- Silently ignore if already applied

-- OR return a useful message:
ON CONFLICT (job_requirement_id, candidate_profile_id)
DO UPDATE SET updated_at = NOW()  -- Touch the row, return it
RETURNING id, submitted_at;
```

> **Defense Answer:** "Race conditions cannot be solved in application code alone — two simultaneous requests both pass the application-level check. The UNIQUE constraint is enforced inside a database transaction with row-level locking, making it physically impossible for two identical rows to exist regardless of concurrency. ON CONFLICT gives us graceful handling without exceptions."

---

## Problem 4 — Slow Job Search (Missing Composite Index) 🔴

### What is the problem?
The most common query on the platform is: "Show me published jobs in Mumbai for a Java developer with 2-5 years experience." This query filters on 4 columns simultaneously.

### How it fails (BAD):
```sql
-- Common job search query:
SELECT * FROM job_requirement
WHERE city_id = 12
AND   publish_state = 'PUBLISHED'
AND   min_experience_months <= 24
AND   max_experience_months >= 24
AND   deleted_at IS NULL;

-- Without composite index, PostgreSQL uses the weakest single index
-- then filters everything else in memory.
-- At 1M jobs: Execution time = 800ms  (too slow for a search page)
```

### The Fix — Composite Index for Job Search
```sql
-- Add a composite index that matches the exact query pattern:
CREATE INDEX idx_jr_search
    ON job_requirement (city_id, publish_state, min_experience_months, max_experience_months)
    WHERE deleted_at IS NULL;

-- Now the query uses ONE index scan instead of multiple:
-- Index Scan using idx_jr_search
-- Index Cond: (city_id = 12 AND publish_state = 'PUBLISHED'
--              AND min_experience_months <= 24
--              AND max_experience_months >= 24)
-- Execution time: 2ms  ← 400x improvement!
```

> **Defense Answer:** "A composite index on (city_id, publish_state, min_experience_months, max_experience_months) combined with a partial WHERE deleted_at IS NULL matches the most frequent job search pattern exactly. PostgreSQL reads the index from left to right — high-selectivity columns (city_id) come first to eliminate the most rows early. The partial condition ensures deleted jobs are never in the index at all."

---

## Problem 5 — Constraint Bypass via NULL 🟡

### What is the problem?
CHECK constraints in SQL have a three-valued logic: TRUE, FALSE, and UNKNOWN. A CHECK constraint only rejects rows when the result is FALSE. If any part of the expression is NULL, the result is UNKNOWN — and the row is ACCEPTED even if the business rule is violated.

### How it can go wrong:
```sql
-- Our salary range constraint:
CONSTRAINT chk_salary_range
    CHECK (max_salary >= min_salary)

-- This PASSES even though it should fail in some edge cases:
INSERT INTO job_requirement (..., min_salary, max_salary)
VALUES (..., NULL, NULL);   -- Passes: NULL >= NULL = UNKNOWN → accepted ✅
VALUES (..., 50000, NULL);  -- Passes: NULL >= 50000 = UNKNOWN → accepted ✅
VALUES (..., NULL, 50000);  -- Passes: 50000 >= NULL = UNKNOWN → accepted ✅
VALUES (..., 80000, 50000); -- FAILS: 50000 >= 80000 = FALSE → rejected ✅
```

### The Fix — Explicit NULL Handling in Constraints
```sql
-- Already correctly written in our schema:
CONSTRAINT chk_salary_range
    CHECK (
        min_salary IS NULL OR    -- Skip check if min is unknown
        max_salary IS NULL OR    -- Skip check if max is unknown
        max_salary >= min_salary  -- Only enforce when BOTH are present
    )

-- This is the correct pattern. When both are provided, the rule is enforced.
-- When either is NULL (employer hiding salary), the constraint is skipped.
```

> **Defense Answer:** "SQL's three-valued logic means NULL comparisons return UNKNOWN, not FALSE, so CHECK constraints silently pass on NULL values. Our constraints explicitly handle NULLs using IS NULL guards — the salary range constraint only enforces the rule when both min and max are provided. This is a documented design decision in our deviation register."

---

## Problem 6 — Unbounded Text Search Performance 🟡

### What is the problem?
Candidates search for jobs by keyword (e.g., "machine learning engineer"). Without full-text search, every query does a LIKE scan across all job descriptions — extremely slow at 1M rows.

```sql
-- BAD: LIKE scan (no index possible)
SELECT * FROM job_requirement
WHERE job_description LIKE '%machine learning%';
-- Full sequential scan: 1.2 seconds at 1M rows
```

### The Fix — Full Text Search Index (Add in Phase 5)
```sql
-- Step 1: Add a tsvector column for pre-computed search tokens
ALTER TABLE job_requirement
ADD COLUMN search_vector TSVECTOR
GENERATED ALWAYS AS (
    TO_TSVECTOR('english',
        COALESCE(title, '') || ' ' ||
        COALESCE(job_description, '')
    )
) STORED;

-- Step 2: Add GIN index on it
CREATE INDEX idx_jr_search_vector
    ON job_requirement USING GIN (search_vector);

-- Step 3: Now search is blazing fast
SELECT * FROM job_requirement
WHERE search_vector @@ TO_TSQUERY('english', 'machine & learning')
AND publish_state = 'PUBLISHED'
AND deleted_at IS NULL;
-- Index Scan using GIN: 4ms at 1M rows!
```

> **Defense Answer:** "LIKE '%keyword%' cannot use a B-Tree index because the wildcard is at the start. PostgreSQL's full-text search uses GIN-indexed tsvector columns — pre-tokenized and stemmed word lists. 'engineering' matches 'engineer', 'engineers', 'engineered'. This is added in Phase 5 as part of our benchmark optimization."

---

## Problem 7 — Foreign Key Lock Contention 🟡

### What is the problem?
When you INSERT into `job_application`, PostgreSQL places a short-lived share lock on the referenced `job_requirement` row to verify it exists. At 100M applications with high concurrency, these micro-locks stack up and slow down the entire system.

### How it manifests:
```
job_application INSERT rate: 10,000/second (expected at peak)
Lock wait time on job_requirement rows: increasing
Deadlock warnings: beginning to appear in pg_locks
```

### The Fix — Proper Index on Referenced FK Columns
```sql
-- PostgreSQL uses the PK index on job_requirement to resolve FK checks.
-- But for the reverse lookup (cascade operations), we need:

-- "When a job is deleted, find all its applications" — needs this index:
CREATE INDEX idx_ja_job_requirement ON job_application (job_requirement_id);
-- Already created in Milestone 1.6 ✅

-- "When a candidate profile is deleted, find their applications":
CREATE INDEX idx_ja_candidate ON job_application (candidate_profile_id);
-- Already created in Milestone 1.6 ✅

-- Without these indexes, a CASCADE delete on job_requirement
-- would do a full sequential scan of 100M job_application rows!
```

> **Defense Answer:** "Foreign key constraints require PostgreSQL to verify the referenced row exists on every INSERT and to find dependent rows on every DELETE. Without indexes on the FK columns in child tables, a cascade delete does a full sequential scan. Our indexes on job_requirement_id and candidate_profile_id in job_application make FK operations use index scans instead — critical at 100M rows."

---

## Problem 8 — Timezone Inconsistency 🟡

### What is the problem?
If different team members store timestamps in different timezones (one stores IST, another stores UTC), date-based queries and reporting will be wrong by 5.5 hours.

```sql
-- Member A inserts at 2pm IST:
submitted_at = '2024-01-15 14:00:00+05:30'

-- Member B inserts at 2pm IST but without timezone:
submitted_at = '2024-01-15 14:00:00'  -- Interpreted as UTC = 7:30pm IST!

-- Now a report for "applications on Jan 15" misses Member B's records
```

### The Fix — Always use TIMESTAMPTZ, Never TIMESTAMP
```sql
-- We already used TIMESTAMPTZ everywhere in our schema ✅
-- TIMESTAMPTZ stores in UTC internally, displays in session timezone

-- Verify your session timezone is set correctly:
SHOW timezone;
-- Should return 'UTC' for consistency

-- Set it if needed:
SET timezone = 'UTC';

-- Or set it permanently in postgresql.conf:
-- timezone = 'UTC'
```

> **Defense Answer:** "TIMESTAMPTZ (timestamp with time zone) stores all values internally as UTC and converts to the session timezone on display. TIMESTAMP (without time zone) stores exactly what you insert — creating inconsistencies when team members in different timezones insert data. We enforced TIMESTAMPTZ on every date-time column to ensure all timestamps are comparable and reports are accurate."

---

## Problem 9 — Primary Key Sequence Exhaustion 🟢

### What is the problem?
`BIGINT` can hold up to 9,223,372,036,854,775,807 — about 9.2 quintillion. At 100 million applications per year, this lasts 92 billion years. Not a real problem for this project, but judges may ask.

### If we had used INT instead of BIGINT:
```sql
-- INT maximum: 2,147,483,647 (~2.1 billion)
-- At 100M applications/year: exhausted in 21 years
-- When it runs out: ERROR: integer out of range
-- Fix requires: ALTER TABLE (rewriting entire table = hours of downtime)

-- We correctly used BIGINT everywhere:
id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
-- Maximum: 9.2 quintillion. Never an issue.
```

> **Defense Answer:** "We chose BIGINT for all primary keys. At 100 million applications per year, an INT primary key would exhaust in 21 years and require a disruptive table rewrite. BIGINT supports 9.2 quintillion values — effectively unlimited for any realistic business scale. The storage cost difference is just 4 bytes per row — negligible."

---

## Problem 10 — Missing Statistics for Query Planner 🟢

### What is the problem?
PostgreSQL's query planner makes decisions based on table statistics (row counts, value distributions). When you first create tables and add data, these statistics may be stale, causing the planner to choose bad execution plans.

### The Fix — ANALYZE after bulk inserts
```sql
-- After Phase 5 seeding (1M candidates, 5M applications):
ANALYZE candidate_profile;
ANALYZE job_application;
ANALYZE application_status_history;
ANALYZE job_requirement;

-- Or analyze everything at once:
ANALYZE;

-- Check when statistics were last updated:
SELECT schemaname, tablename, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY last_analyze DESC NULLS LAST;
```

> **Defense Answer:** "PostgreSQL's query planner uses statistics like row counts, column cardinality, and value histograms to choose execution plans. After seeding 1 million candidates and 5 million applications, we run ANALYZE to refresh these statistics. Without this, the planner might choose a sequential scan over an index scan because it thinks the table has only 100 rows."

---

## Complete Optimization Checklist for Phase 1

### Run these verification queries in pgAdmin after Phase 1:

```sql
-- 1. Verify all indexes were created
SELECT indexname, tablename, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- 2. Verify all constraints are active
SELECT conname, contype, conrelid::regclass AS table_name
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
ORDER BY table_name, contype;

-- 3. Check for tables WITHOUT indexes (should have none after Phase 1)
SELECT t.table_name
FROM information_schema.tables t
LEFT JOIN pg_indexes i ON i.tablename = t.table_name
WHERE t.table_schema = 'public'
AND i.indexname IS NULL;

-- 4. Verify btree_gist extension (needed for Phase 3 gig constraints)
SELECT extname, extversion FROM pg_extension WHERE extname = 'btree_gist';

-- 5. Check all FK columns have supporting indexes
SELECT
    tc.table_name,
    kcu.column_name,
    CASE WHEN ix.indexname IS NULL THEN '❌ NO INDEX' ELSE '✅ Indexed' END AS status
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
LEFT JOIN pg_indexes ix
    ON ix.tablename = tc.table_name
    AND ix.indexdef LIKE '%' || kcu.column_name || '%'
WHERE tc.constraint_type = 'FOREIGN KEY'
AND tc.table_schema = 'public'
ORDER BY tc.table_name;
```

---

## Summary: Problems vs Fixes

| # | Problem | Severity | Fix Applied |
|---|---|---|---|
| 1 | Full table scan on soft-deleted rows | 🔴 Critical | Partial indexes WHERE deleted_at IS NULL |
| 2 | N+1 query on candidate profile | 🔴 Critical | JOIN + JSON_AGG in single query |
| 3 | Duplicate application race condition | 🔴 Critical | UNIQUE constraint + ON CONFLICT |
| 4 | Slow job search (4 filters) | 🔴 Critical | Composite index on search columns |
| 5 | NULL bypass in CHECK constraints | 🟡 Medium | Explicit IS NULL guards in all CHECKs |
| 6 | Keyword search with LIKE | 🟡 Medium | Full-text search + GIN index (Phase 5) |
| 7 | FK lock contention at 100M rows | 🟡 Medium | Indexes on all FK child columns |
| 8 | Timezone inconsistency | 🟡 Medium | TIMESTAMPTZ everywhere + UTC session |
| 9 | INT PK exhaustion | 🟢 Low | BIGINT on all PKs |
| 10 | Stale query planner statistics | 🟢 Low | ANALYZE after Phase 5 seeding |
