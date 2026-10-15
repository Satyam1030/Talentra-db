-- ============================================================
-- MILESTONE 1.6: JOB APPLICATION & STATUS HISTORY PIPELINE
-- 2 Tables: job_application, application_status_history
-- ============================================================

-- 1. JOB APPLICATION
CREATE TABLE job_application (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id      BIGINT          NOT NULL,
    candidate_profile_id    BIGINT          NOT NULL,
    candidate_resume_id     BIGINT          NULL,
    current_status_id       BIGINT          NOT NULL,
    source_type             VARCHAR(30)     NOT NULL DEFAULT 'ORGANIC'
                            CHECK (source_type IN (
                                'ORGANIC','RECRUITER_SOURCED',
                                'CONSULTANT_REFERRAL','CAMPUS','REFERRAL'
                            )),
    sourced_by_user_id      BIGINT          NULL,
    submitted_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT fk_ja_job FOREIGN KEY (job_requirement_id)
        REFERENCES job_requirement (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ja_candidate FOREIGN KEY (candidate_profile_id)
        REFERENCES candidate_profile (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ja_status FOREIGN KEY (current_status_id)
        REFERENCES application_status_lookup (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ja_sourced_by FOREIGN KEY (sourced_by_user_id)
        REFERENCES app_user (id) ON DELETE SET NULL,
    CONSTRAINT uq_candidate_job_application
        UNIQUE (job_requirement_id, candidate_profile_id),
    CONSTRAINT chk_sourced_by
        CHECK (
            source_type = 'ORGANIC' OR
            sourced_by_user_id IS NOT NULL
        )
);

CREATE INDEX idx_ja_job_requirement     ON job_application (job_requirement_id);
CREATE INDEX idx_ja_candidate           ON job_application (candidate_profile_id);
CREATE INDEX idx_ja_current_status      ON job_application (current_status_id);
CREATE INDEX idx_ja_submitted_at        ON job_application (submitted_at DESC);
CREATE INDEX idx_ja_source_type         ON job_application (source_type);
CREATE INDEX idx_ja_job_submitted       ON job_application (job_requirement_id, submitted_at DESC);
CREATE INDEX idx_ja_candidate_submitted ON job_application (candidate_profile_id, submitted_at DESC);

-- 2. APPLICATION STATUS HISTORY (Append-Only)
CREATE TABLE application_status_history (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_application_id      BIGINT          NOT NULL,
    status_lookup_id        BIGINT          NOT NULL,
    actor_user_id           BIGINT          NOT NULL,
    comment                 TEXT            NULL,
    transitioned_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_ash_application FOREIGN KEY (job_application_id)
        REFERENCES job_application (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ash_status FOREIGN KEY (status_lookup_id)
        REFERENCES application_status_lookup (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ash_actor FOREIGN KEY (actor_user_id)
        REFERENCES app_user (id) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX idx_ash_application_id     ON application_status_history (job_application_id);
CREATE INDEX idx_ash_status_id          ON application_status_history (status_lookup_id);
CREATE INDEX idx_ash_transitioned_at    ON application_status_history (transitioned_at DESC);
CREATE INDEX idx_ash_app_timeline       ON application_status_history (job_application_id, transitioned_at ASC);
