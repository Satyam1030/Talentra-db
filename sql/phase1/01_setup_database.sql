-- ============================================================
-- MILESTONE 1.1: DATABASE INITIALIZATION & EXTENSIONS
-- Engine: PostgreSQL 18.x
-- ============================================================

-- Ensure the btree_gist extension is enabled for exclusion constraints
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Verify database settings
SELECT current_database(), current_user, version();
