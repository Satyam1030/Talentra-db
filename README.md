# Talentra: High-Scale Job Search & Demand Management Platform

[![Database](https://img.shields.io/badge/PostgreSQL-18.4-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Status](https://img.shields.io/badge/Phase%201-100%25%20Completed-success)]()
[![Target Scale](https://img.shields.io/badge/Target%20Scale-10M%20Profiles%20%7C%20100M%20Applications-blue)]()

Enterprise database architecture designed for **Northbridge Workforce Systems' Talentra Platform Hackathon**. Engineered to handle high-throughput transactional recruiting workflows and large-scale analytical reporting across 10 million candidates and 100 million applications.

---

## 🏗️ Repository Architecture

```text
talentra-db/
├── diagrams/                           # Interactive DBML schemas for dbdiagram.io
│   ├── talentra_phase1_dbml.dbml       # 23-Table Phase 1 visual schema
│   └── talentra_complete_dbml.dbml     # Full 50-Table production vision schema
├── docs/                               # Panel defense documentation & benchmarks
│   ├── phase1_defense_guide.md         # Comprehensive Q&A defense document
│   └── phase1_problems_optimizations.md# Anticipated scale bottlenecks & fixes
├── sql/
│   └── phase1/                         # Phase 1 DDL Migration Scripts
│       ├── 00_init_all_phase1.sql      # Master runner script
│       ├── 01_setup_database.sql       # DB setup & btree_gist extension
│       ├── 02_master_data.sql          # 9 Lookup & Master Data tables
│       ├── 03_identity_and_sessions.sql# Identity, RBAC & multi-device sessions
│       ├── 04_candidate_profile.sql    # Candidate profiles, skills & experience
│       ├── 05_organizations_and_jobs.sql # Employer accounts & job postings
│       └── 06_application_pipeline.sql # Applications & append-only audit trail
└── README.md
```

---

## 📊 Phase 1 Architecture Metrics

| Metric | Metric Count | Technical Specification |
|---|:---:|---|
| **Base Tables** | **23** | Compliant with Rule Group 1 (singular nouns, snake_case) |
| **Columns** | **~195** | Fully typed, strict ranges, no ambiguous sentinel values |
| **Primary Keys** | **23** | `BIGINT GENERATED ALWAYS AS IDENTITY` (9.2 quintillion capacity) |
| **Foreign Keys** | **24** | Explicit constraints with defined CASCADE / RESTRICT rules |
| **Unique Constraints** | **16** | Natural keys protected (emails, tax IDs, duplicate applications) |
| **Domain Checks** | **15+** | Database-level business logic (dates, salary bounds, ranges) |
| **Target Scale** | **10M / 100M** | Partition-ready, partial-indexed for soft-deletes |

---

## 🚀 Quickstart: Reproducing the Database Locally

### 1. Prerequisites
- **PostgreSQL 16+** (PostgreSQL 18.x recommended)
- **psql** or **pgAdmin 4**

### 2. Execution
Run the master initialization script against your local database:

```bash
psql -U postgres -d talentra_db -f sql/phase1/00_init_all_phase1.sql
```

Alternatively, open `pgAdmin 4`, connect to `talentra_db`, and execute the files in order:
`01_setup_database.sql` $\rightarrow$ `02_master_data.sql` $\rightarrow$ `03_identity_and_sessions.sql` $\rightarrow$ `04_candidate_profile.sql` $\rightarrow$ `05_organizations_and_jobs.sql` $\rightarrow$ `06_application_pipeline.sql`.

---

## 🌟 Key Technical Highlights (Why Our Design Wins)

1. **Database-Level Invariant Enforcement:** Critical business rules (e.g. preventing candidates from submitting duplicate applications, or validating that max salary is greater than min salary) are enforced **inside the database engine** using constraints, rather than relying solely on fragile application code.
2. **Partial Indexing for Scale:** To eliminate query bloat caused by soft-deleted records (`deleted_at`), partial indexes (`WHERE deleted_at IS NULL`) are deployed across all search tables, keeping index trees compact in RAM.
3. **Audit Trail & State Transitions:** Status changes in the hiring funnel are recorded in an **append-only ledger** (`application_status_history`), allowing instant calculation of Time-to-Hire and conversion metrics without losing historical fidelity.
4. **ANSI SQL Standard Identities:** Standardized on `BIGINT GENERATED ALWAYS AS IDENTITY`, avoiding legacy sequence gaps and preventing ID exhaustion under massive volume.

---

## 🗺️ Project Delivery Roadmap

- [x] **Phase 1: Foundation (Whole Team)** — Master Data, Core Profiles, Jobs, Applications (23 Tables)
- [ ] **Phase 2: Modular Tracks (Specialized)** — Admin RBAC, Organization Accounts, Dedicated Gig Marketplace
- [ ] **Phase 3: Deep Differentiators** — Licensing & Device Concurrency, Custom Screening Questionnaires, Append-Only Wallets
- [ ] **Phase 4: Analytics & Notifications** — Star Schema (Dimensional Marts) & Partitioned Notification Pipelines
- [ ] **Phase 5: Seeding, Benchmarks & Defense** — 1M Candidate / 5M Application Load, `EXPLAIN ANALYZE` Latency Profiling

---

## 👥 Authors & Team
- Prepared for **Northbridge Workforce Systems Hackathon**
- Engine: PostgreSQL 18.4
