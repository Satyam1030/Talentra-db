-- ============================================================
-- MILESTONE 1.4: CANDIDATE PROFILE CORE
-- 4 Tables: candidate_profile, candidate_skill, candidate_experience, candidate_education
-- ============================================================

-- 1. CANDIDATE PROFILE
CREATE TABLE candidate_profile (
    id                              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id                     BIGINT          NOT NULL,
    first_name                      VARCHAR(75)     NOT NULL,
    last_name                       VARCHAR(75)     NOT NULL,
    headline                        VARCHAR(150)    NULL,
    city_id                         BIGINT          NOT NULL,
    total_experience_months         INT             NOT NULL DEFAULT 0
                                    CHECK (total_experience_months >= 0),
    current_salary                  DECIMAL(12,2)   NULL,
    expected_salary                 DECIMAL(12,2)   NULL,
    salary_currency                 CHAR(3)         NOT NULL DEFAULT 'USD',
    notice_period_days              INT             NOT NULL DEFAULT 30
                                    CHECK (notice_period_days >= 0),
    profile_summary                 TEXT            NULL,
    profile_completion_percentage   INT             NOT NULL DEFAULT 0
                                    CHECK (profile_completion_percentage BETWEEN 0 AND 100),
    is_open_to_work                 BOOLEAN         NOT NULL DEFAULT TRUE,
    is_gig_worker                   BOOLEAN         NOT NULL DEFAULT FALSE,
    is_blocked_from_search          BOOLEAN         NOT NULL DEFAULT FALSE,
    deleted_at                      TIMESTAMPTZ     NULL,

    -- Audit columns
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_by      BIGINT          NOT NULL,
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_by      BIGINT          NOT NULL,

    -- Constraints
    CONSTRAINT uq_candidate_app_user UNIQUE (app_user_id),
    CONSTRAINT fk_candidate_user FOREIGN KEY (app_user_id)
        REFERENCES app_user (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_candidate_city FOREIGN KEY (city_id)
        REFERENCES city (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_salary_range
        CHECK (
            expected_salary IS NULL OR
            current_salary IS NULL OR
            expected_salary >= current_salary
        )
);

CREATE INDEX idx_candidate_profile_city         ON candidate_profile (city_id);
CREATE INDEX idx_candidate_profile_open_work    ON candidate_profile (is_open_to_work);
CREATE INDEX idx_candidate_profile_experience   ON candidate_profile (total_experience_months);
CREATE INDEX idx_candidate_profile_deleted      ON candidate_profile (deleted_at)
    WHERE deleted_at IS NULL;

-- 2. CANDIDATE SKILL
CREATE TABLE candidate_skill (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id    BIGINT          NOT NULL,
    skill_id                BIGINT          NOT NULL,
    experience_months       INT             NOT NULL DEFAULT 0
                            CHECK (experience_months >= 0),
    proficiency_level       VARCHAR(20)     NOT NULL
                            CHECK (proficiency_level IN (
                                'BEGINNER','INTERMEDIATE','ADVANCED','EXPERT'
                            )),
    is_primary              BOOLEAN         NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_cs_candidate FOREIGN KEY (candidate_profile_id)
        REFERENCES candidate_profile (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_cs_skill FOREIGN KEY (skill_id)
        REFERENCES skill (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_candidate_skill UNIQUE (candidate_profile_id, skill_id)
);

CREATE INDEX idx_candidate_skill_profile    ON candidate_skill (candidate_profile_id);
CREATE INDEX idx_candidate_skill_skill_id   ON candidate_skill (skill_id);

-- 3. CANDIDATE EXPERIENCE
CREATE TABLE candidate_experience (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id    BIGINT          NOT NULL,
    company_name            VARCHAR(150)    NOT NULL,
    designation             VARCHAR(100)    NOT NULL,
    city_id                 BIGINT          NULL,
    employment_type         VARCHAR(20)     NOT NULL
                            CHECK (employment_type IN (
                                'FULL_TIME','PART_TIME','FREELANCE','INTERNSHIP','CONTRACT'
                            )),
    start_date              DATE            NOT NULL,
    end_date                DATE            NULL,
    is_current              BOOLEAN         NOT NULL DEFAULT FALSE,
    description             TEXT            NULL,

    CONSTRAINT fk_exp_candidate FOREIGN KEY (candidate_profile_id)
        REFERENCES candidate_profile (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_exp_city FOREIGN KEY (city_id)
        REFERENCES city (id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_exp_dates
        CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT chk_current_no_end_date
        CHECK (
            (is_current = TRUE AND end_date IS NULL) OR
            (is_current = FALSE)
        )
);

CREATE INDEX idx_candidate_experience_profile ON candidate_experience (candidate_profile_id);

-- 4. CANDIDATE EDUCATION
CREATE TABLE candidate_education (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id    BIGINT          NOT NULL,
    institution_name        VARCHAR(150)    NOT NULL,
    degree_name             VARCHAR(100)    NOT NULL,
    field_of_study          VARCHAR(100)    NOT NULL,
    graduation_year         INT             NOT NULL
                            CHECK (graduation_year BETWEEN 1950 AND 2035),
    grade_or_gpa            VARCHAR(20)     NULL,
    is_verified             BOOLEAN         NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_edu_candidate FOREIGN KEY (candidate_profile_id)
        REFERENCES candidate_profile (id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX idx_candidate_education_profile ON candidate_education (candidate_profile_id);
