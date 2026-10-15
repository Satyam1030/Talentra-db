-- ============================================================
-- TALENTRA — ALL-IN-ONE PHASE 1 INITIALIZATION
-- Run this single file to build the entire 23-table foundation!
-- ============================================================

\ir 01_setup_database.sql
\ir 02_master_data.sql
\ir 03_identity_and_sessions.sql
\ir 04_candidate_profile.sql
\ir 05_organizations_and_jobs.sql
\ir 06_application_pipeline.sql

-- Verify Table Count (Must be 23)
SELECT count(*) AS total_phase1_tables 
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
