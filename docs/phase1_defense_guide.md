# Talentra — Phase 1 Complete Defense Guide

## Phase 1 Progress Summary

| Milestone | What Was Built | Tables | Status |
|---|---|---|---|
| 1.1 | DB Engine Selection + Setup | 0 | ✅ Done |
| 1.2 | Master Data & Lookups | 9 | ✅ Done |
| 1.3 | Identity & Users | 4 | ✅ Done |
| 1.4 | Candidate Profile Core | 4 | ✅ Done |
| 1.5 | Organisations & Jobs | 4 | ✅ Done |
| 1.6 | Application Pipeline | 2 | ✅ Done |
| **Total** | | **23 tables** | ✅ **Phase 1 Complete** |

---

## Section 1 — Why PostgreSQL?

### What we chose
**PostgreSQL 18.4** — Open source, ACID-compliant, SQL-standard relational database.

### Why not MySQL?

| Feature Needed | PostgreSQL | MySQL |
|---|---|---|
| Non-overlapping date constraints | ✅ EXCLUDE USING gist | ❌ Not available |
| Declarative table partitioning | ✅ Full native support | ⚠️ Limited |
| JSONB with GIN indexing | ✅ Native JSONB | ❌ No GIN indexes |
| Multi-column CHECK constraints | ✅ Full support | ⚠️ Ignored pre-8.0 |
| GENERATED ALWAYS AS IDENTITY | ✅ SQL Standard | ❌ Proprietary AUTO_INCREMENT |
| EXPLAIN ANALYZE with buffer stats | ✅ Detailed output | ⚠️ Basic output |

### Defense Answer
> "We chose PostgreSQL because the docket requires enforcing non-overlapping subscription periods and gig worker availability windows at the database level. PostgreSQL's exclusion constraints using btree_gist enforce this in a single ALTER TABLE statement. MySQL has no equivalent feature. Additionally, PostgreSQL's declarative partitioning, JSONB support, and rich EXPLAIN ANALYZE output directly address Rule Groups 8 and 10."

---

## Section 2 — Milestone 1.2: Master Data & Lookup Tables

### Tables: country, state_province, city, skill, language_lookup, industry_lookup, job_type_lookup, application_status_lookup, ui_translation

### Why lookup tables instead of ENUMs or VARCHAR?

Rule Group 3 of the docket explicitly states: **"Enums MUST be lookup tables, never free text."**

**Wrong approach:**
```sql
-- Using VARCHAR with no constraint — data corruption risk
status VARCHAR(50)  -- "applied", "Applied", "APPLIED" all allowed

-- Using PostgreSQL ENUM — changing requires full table lock in production
CREATE TYPE app_status AS ENUM ('applied', 'shortlisted');
```

**Correct approach (what we did):**
```sql
CREATE TABLE application_status_lookup (
    id           BIGINT PRIMARY KEY,
    status_code  VARCHAR(30) UNIQUE NOT NULL,  -- 'APPLIED' always consistent
    display_name VARCHAR(50) NOT NULL,          -- 'Applied' for UI
    sort_order   INT NOT NULL,
    is_terminal  BOOLEAN NOT NULL DEFAULT FALSE
);
-- Adding a new status = INSERT one row. Zero downtime. Zero migration.
```

**Benefits:**
1. Add new values without touching schema — just INSERT a row
2. Multilingual display names — status_code stays English, display_name can be translated
3. Sort order control — pipeline stages shown in correct UI order
4. is_terminal flag — marks JOINED/REJECTED/WITHDRAWN as final states

### Why 3-level geography (country → state → city)?
- Candidates and jobs need city-level location for job search
- Organizations need country-level for compliance and tax
- State/province needed for regional reporting and tax rules
- latitude/longitude on city enables future distance-based job search

### Defense Questions — Lookup Tables

**Q: Why not just store 'India' as a string in the candidate table?**
> "String duplication at 10 million rows wastes storage and makes updates impossible. If 'United States' needs to change to 'USA', you'd UPDATE 2 million rows. With a foreign key to country, you change one row and all references update instantly."

**Q: What is ui_translation for?**
> "Rule Group 7 requires full multilingual support. UI labels are stored as key-value pairs against a language. The key label.apply_now maps to 'Apply Now' in English and 'अभी आवेदन करें' in Hindi. This keeps translations out of application code and in the database where they can be managed without a deployment."

---

## Section 3 — Milestone 1.3: Identity & Users

### Tables: role_lookup, app_user, user_role_mapping, user_session

### The app_user table design

```
app_user (one row per person)
    ├── email                           → Unique login identifier
    ├── password_hash                   → Argon2id hash. NEVER plaintext.
    ├── user_type                       → CHECK: CANDIDATE, RECRUITER, CONSULTANT, ADMIN, TPO
    ├── is_verified                     → Email verification flag
    ├── identity_verification_token     → From external ID provider (NOT raw Aadhaar/passport)
    ├── deleted_at                      → Soft delete (Rule Group 4)
    └── created_at/updated_at/created_by/updated_by → Audit columns
```

### Why soft delete (deleted_at) instead of hard delete?

Hard deleting a candidate breaks foreign keys in job_application, application_status_history, and audit_trail. Their application history must be preserved for legal and compliance reasons.

- deleted_at IS NULL = active user
- deleted_at IS NOT NULL = deactivated user (data preserved)
- Partial index WHERE deleted_at IS NULL ensures deleted users never appear in searches

### Why separate user_role_mapping table?

A user can hold multiple roles simultaneously:
- A person can be both RECRUITER and ACCOUNT_ADMIN
- A CONSULTANT might be upgraded to RECRUITER for one client

If roles were stored as a column on app_user, multiple roles would require comma-separated strings or arrays — both violate First Normal Form (1NF).

### Device Session Control (Rule Group 9)

```sql
-- Unique constraint prevents same device having two active sessions
CONSTRAINT uq_active_device_session UNIQUE (app_user_id, device_identifier)
```

Before creating a new session, application checks:
```sql
SELECT COUNT(*) FROM user_session
WHERE app_user_id = $1
AND is_revoked = FALSE AND session_end IS NULL;
-- If count >= max_devices_per_user from license → REJECT login
```

### Defense Questions — Identity

**Q: Why store password_hash and not the password?**
> "Storing plaintext passwords is a critical security vulnerability. We store an Argon2id hash — a memory-hard hashing algorithm recommended by OWASP. Even if the database is fully compromised, no password can be recovered."

**Q: Why not store the national ID number for identity verification?**
> "Rule Group 6 classifies national IDs as SENSITIVE data. The docket integration boundary says we store only the verification token and pass/fail result from the external identity provider — never the raw ID number. This limits liability under GDPR and India's DPDP Act."

**Q: What happens if a user tries to log in from a 4th device when their license allows only 3?**
> "The application queries user_session to count active non-revoked sessions. If the count equals max_devices_per_user from the license table, the login is rejected. This check is done inside a database transaction to prevent race conditions."

---

## Section 4 — Milestone 1.4: Candidate Profile Core

### Tables: candidate_profile, candidate_skill, candidate_experience, candidate_education

### Entity Relationship

```
app_user (1) ────── (1) candidate_profile
                          │
               ┌──────────┼──────────────┐
               │          │              │
        candidate_skill  candidate_   candidate_
        (many)           experience   education
                         (many)       (many)
```

### Key Constraints Explained

**1. Salary range validation:**
```sql
CONSTRAINT chk_salary_range
    CHECK (
        expected_salary IS NULL OR
        current_salary IS NULL OR
        expected_salary >= current_salary
    )
```
> "A candidate cannot expect less than what they currently earn. If either value is NULL (fresher or privacy preference), the check is skipped — fires only when both values are present."

**2. Current job with no end date:**
```sql
CONSTRAINT chk_current_no_end_date
    CHECK (
        (is_current = TRUE AND end_date IS NULL) OR
        (is_current = FALSE)
    )
```
> "If a candidate marks a job as current, they cannot also provide an end date. Prevents contradictory data like 'currently working here, ended in 2020'."

**3. Partial index on deleted candidates:**
```sql
CREATE INDEX idx_candidate_profile_deleted ON candidate_profile (deleted_at)
    WHERE deleted_at IS NULL;
```
> "At 10 million candidates, 200,000 may be deactivated. Without a partial index, every search scans all 10 million rows. With this index, the planner only scans 9.8 million active profiles — direct performance gain."

### Defense Questions — Candidate Profile

**Q: What is profile_completion_percentage and why store it?**
> "It is a cached computed value (0-100) showing how complete the profile is. Storing it avoids recalculating across 10 million candidates on every page load. This is a deliberate, documented denormalization for read performance."

**Q: Why does candidate_skill have a UNIQUE constraint on (candidate_profile_id, skill_id)?**
> "A candidate cannot list Python twice with different proficiency levels — that is contradictory data. The unique constraint makes this physically impossible at the database level."

**Q: Why is profile_summary TEXT with no length limit?**
> "Rule Group 3 of the docket explicitly permits unbounded TEXT for resume content and profile summaries. An arbitrary VARCHAR limit would truncate legitimate long-form career summaries."

---

## Section 5 — Milestone 1.5: Organisations & Jobs

### Tables: organization, recruiter_organization_mapping, job_requirement, job_requirement_skill

### Organization Verification Flow

```
Registration → PENDING → (Admin reviews) → VERIFIED
                                        → REJECTED
                         (Violation)    → SUSPENDED
```

```sql
-- verified_at must exist when status is VERIFIED
CONSTRAINT chk_verified_at
    CHECK (
        verification_status != 'VERIFIED' OR
        verified_at IS NOT NULL
    )
```

### Job Requirement Key Design Decisions

| Column | Decision | Reason |
|---|---|---|
| min_salary / max_salary nullable | Some employers hide salary | Legal in most markets |
| is_salary_disclosed boolean | Explicit flag for UI | Avoids NULL ambiguity |
| is_consultant_open | Allows external consultants to source | Core business rule |
| publish_state with CHECK | DRAFT→PUBLISHED→CLOSED pipeline | Prevents invalid states |
| closes_at nullable | Some jobs are open-ended | Nullable with justification |

### Defense Questions — Jobs

**Q: Why is job_description stored as TEXT in the database instead of a file?**
> "Job descriptions are queried, searched, and indexed. Storing in object storage would require a network call for every listing. TEXT in PostgreSQL supports full-text search with tsvector which we add as a GIN index in Phase 5."

**Q: Why ON DELETE RESTRICT on job_requirement instead of CASCADE?**
> "If an organization is deleted, we do not want to silently delete all their job postings and the 50,000 candidate applications attached to them. RESTRICT forces the application to explicitly handle this — archive jobs first, then delete the org. This prevents accidental mass data loss."

---

## Section 6 — Milestone 1.6: Application Pipeline

### Tables: job_application, application_status_history

### The Pipeline Flow

```
APPLIED → SHORTLISTED → INTERVIEWED → OFFERED → JOINED    (terminal ✅)
                                             → REJECTED   (terminal ✅)
       → REJECTED (terminal ✅)
       → WITHDRAWN (terminal ✅)  ← candidate withdraws themselves
```

Every transition creates ONE new row in application_status_history. This table is append-only — no UPDATE or DELETE ever.

### Why Two Tables Instead of One?

**Wrong approach:**
```sql
-- Storing only current status — you lose ALL history
job_application (current_status VARCHAR)
-- Cannot answer: "How many days was candidate in SHORTLISTED stage?"
-- Cannot answer: "Who moved this candidate from OFFERED to REJECTED?"
-- Cannot answer: "What is our average time-to-hire?"
```

**Correct approach (what we did):**
```sql
job_application              → current snapshot (fast reads)
application_status_history   → full audit log (analytics + compliance)
```

### Why So Many Indexes on job_application?

```sql
idx_ja_job_requirement     → "Show all applicants for Job #1234"         (recruiter view)
idx_ja_candidate           → "Show all jobs I applied to"                (candidate view)
idx_ja_current_status      → "Show all SHORTLISTED candidates"           (pipeline filter)
idx_ja_submitted_at        → "Show newest applications first"            (dashboard sort)
idx_ja_job_submitted       → Composite: recruiter dashboard (job + date)
idx_ja_candidate_submitted → Composite: candidate dashboard (their apps by date)
```

> "At 100 million application rows, a full table scan takes minutes. Each index is justified by a real query pattern. Phase 5 will show EXPLAIN ANALYZE output proving each index is used and its impact."

### Defense Questions — Application Pipeline

**Q: What if a candidate's status needs to be corrected?**
> "We never UPDATE or DELETE from application_status_history. If a status was entered incorrectly, a compensating row is inserted with the correct status and a comment explaining the correction. This maintains a complete, tamper-evident audit trail — the same principle as a double-entry accounting ledger."

**Q: How do you calculate time-to-hire?**
> "We query application_status_history for the APPLIED timestamp and the JOINED timestamp, then compute the difference:
```sql
SELECT ja.id,
    MAX(CASE WHEN asl.status_code = 'JOINED'  THEN ash.transitioned_at END) -
    MIN(CASE WHEN asl.status_code = 'APPLIED' THEN ash.transitioned_at END)
    AS time_to_hire
FROM job_application ja
JOIN application_status_history ash ON ash.job_application_id = ja.id
JOIN application_status_lookup asl  ON asl.id = ash.status_lookup_id
GROUP BY ja.id;
```"

**Q: A candidate applied to the same job twice — why was it rejected?**
> "The UNIQUE constraint on (job_requirement_id, candidate_profile_id) makes duplicate applications physically impossible at the database level. The INSERT fails with a unique violation before any application code runs."

---

## Section 7 — Overall Architecture Questions

**Q: Explain your normalization strategy.**
> "The schema is in Third Normal Form (3NF). Every non-key column depends only on the primary key. We deliberately denormalized profile_completion_percentage on candidate_profile and balance_after on wallet_ledger_entry for read performance — both are documented deviations with justification."

**Q: How do all 10 mandatory data standards map to your schema?**

| Rule Group | How We Comply |
|---|---|
| 1. Naming | snake_case, singular nouns, id PKs, _id FKs, idx_ indexes, uq_ unique, fk_ FKs, chk_ checks |
| 2. Keys | BIGINT GENERATED ALWAYS AS IDENTITY on all tables, natural keys as UNIQUE constraints |
| 3. Domains | DECIMAL(12,2) for money, CHAR(3) for currency, TEXT only for descriptions |
| 4. Audit | created_at, created_by, updated_at, updated_by on all operational tables |
| 5. Nullability | Every nullable column has written justification |
| 6. Classification | All columns tagged: Public, Internal, Personal, Sensitive |
| 7. Multilingual | ui_translation table, language_lookup with BCP 47 codes |
| 8. Physical objects | Views v_, materialized views mv_, star schema dim_/fact_ in Phase 4 |
| 9. Licensing | license + license_seat_allocation + user_session unique constraint |
| 10. Money | wallet_ledger_entry append-only, balance_after snapshot, reversal_of_entry_id |

**Q: How will this scale to 10M candidates and 100M applications?**
> "Three strategies: (1) Partial indexes on deleted_at IS NULL reduce scan sizes, (2) Composite indexes eliminate sort operations on common multi-column queries, (3) Table partitioning on job_application and notification_delivery by date range splits 100M rows into monthly partitions. Phase 5 will demonstrate with EXPLAIN ANALYZE at 1M rows and extrapolate to 100M."

---

## Quick Reference: Phase 1 Table Map

```
MASTER DATA                    IDENTITY                     CANDIDATE
───────────                    ────────                     ─────────
country                        app_user ─────────────────► candidate_profile
  └─ state_province            role_lookup                     ├─ candidate_skill
       └─ city ◄───────────    user_role_mapping               ├─ candidate_experience
skill                          user_session                    └─ candidate_education
language_lookup
industry_lookup                ORGANISATION                 JOBS & PIPELINE
job_type_lookup                ────────────                 ───────────────
application_status_lookup      organization                 job_requirement
ui_translation                 recruiter_org_mapping            └─ job_requirement_skill
                                                            job_application
                                                                └─ application_status_history
```
