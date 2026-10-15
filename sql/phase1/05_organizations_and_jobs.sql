-- ============================================================
-- MILESTONE 1.5: ORGANISATIONS & JOB REQUIREMENTS
-- 4 Tables: organization, recruiter_organization_mapping, job_requirement, job_requirement_skill
-- ============================================================

-- 1. ORGANIZATION
CREATE TABLE organization (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    legal_name              VARCHAR(150)    NOT NULL,
    trade_name              VARCHAR(150)    NULL,
    tax_identifier          VARCHAR(50)     NOT NULL,
    industry_lookup_id      BIGINT          NOT NULL,
    country_id              BIGINT          NOT NULL,
    city_id                 BIGINT          NOT NULL,
    website_url             VARCHAR(255)    NULL,
    employee_count_range    VARCHAR(20)     NULL
                            CHECK (employee_count_range IN (
                                '1-10','11-50','51-200',
                                '201-500','501-1000','1000+'
                            )),
    logo_object_reference   VARCHAR(500)    NULL,
    verification_status     VARCHAR(20)     NOT NULL DEFAULT 'PENDING'
                            CHECK (verification_status IN (
                                'PENDING','VERIFIED','REJECTED','SUSPENDED'
                            )),
    verified_at             TIMESTAMPTZ     NULL,
    verified_by             BIGINT          NULL,
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    deleted_at              TIMESTAMPTZ     NULL,

    -- Audit columns
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_by      BIGINT          NOT NULL,
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_by      BIGINT          NOT NULL,

    -- Constraints
    CONSTRAINT uq_organization_tax_id UNIQUE (tax_identifier),
    CONSTRAINT fk_org_industry FOREIGN KEY (industry_lookup_id)
        REFERENCES industry_lookup (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_org_country FOREIGN KEY (country_id)
        REFERENCES country (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_org_city FOREIGN KEY (city_id)
        REFERENCES city (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_org_verified_by FOREIGN KEY (verified_by)
        REFERENCES app_user (id) ON DELETE SET NULL,
    CONSTRAINT chk_verified_at
        CHECK (
            verification_status != 'VERIFIED' OR
            verified_at IS NOT NULL
        )
);

CREATE INDEX idx_organization_industry     ON organization (industry_lookup_id);
CREATE INDEX idx_organization_country      ON organization (country_id);
CREATE INDEX idx_organization_city         ON organization (city_id);
CREATE INDEX idx_organization_status       ON organization (verification_status);
CREATE INDEX idx_organization_deleted      ON organization (deleted_at)
    WHERE deleted_at IS NULL;

-- 2. RECRUITER ORGANIZATION MAPPING
CREATE TABLE recruiter_organization_mapping (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id     BIGINT          NOT NULL,
    app_user_id         BIGINT          NOT NULL,
    is_account_admin    BOOLEAN         NOT NULL DEFAULT FALSE,
    effective_from      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    effective_to        TIMESTAMPTZ     NULL,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_by          BIGINT          NOT NULL,

    CONSTRAINT fk_rom_org FOREIGN KEY (organization_id)
        REFERENCES organization (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_rom_user FOREIGN KEY (app_user_id)
        REFERENCES app_user (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_recruiter_org UNIQUE (organization_id, app_user_id),
    CONSTRAINT chk_rom_dates
        CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_rom_org_id     ON recruiter_organization_mapping (organization_id);
CREATE INDEX idx_rom_user_id    ON recruiter_organization_mapping (app_user_id);

-- 3. JOB REQUIREMENT
CREATE TABLE job_requirement (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id         BIGINT          NOT NULL,
    created_by_user_id      BIGINT          NOT NULL,
    title                   VARCHAR(150)    NOT NULL,
    job_type_lookup_id      BIGINT          NOT NULL,
    city_id                 BIGINT          NOT NULL,
    is_remote               BOOLEAN         NOT NULL DEFAULT FALSE,
    vacancies               INT             NOT NULL DEFAULT 1
                            CHECK (vacancies > 0),
    min_experience_months   INT             NOT NULL DEFAULT 0
                            CHECK (min_experience_months >= 0),
    max_experience_months   INT             NOT NULL
                            CHECK (max_experience_months >= 0),
    min_salary              DECIMAL(12,2)   NULL,
    max_salary              DECIMAL(12,2)   NULL,
    salary_currency         CHAR(3)         NOT NULL DEFAULT 'USD',
    is_salary_disclosed     BOOLEAN         NOT NULL DEFAULT FALSE,
    is_consultant_open      BOOLEAN         NOT NULL DEFAULT FALSE,
    publish_state           VARCHAR(20)     NOT NULL DEFAULT 'DRAFT'
                            CHECK (publish_state IN (
                                'DRAFT','PUBLISHED','PAUSED','CLOSED','EXPIRED'
                            )),
    published_at            TIMESTAMPTZ     NULL,
    closes_at               TIMESTAMPTZ     NULL,
    job_description         TEXT            NOT NULL,
    deleted_at              TIMESTAMPTZ     NULL,

    -- Audit columns
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_by      BIGINT          NOT NULL,
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_by      BIGINT          NOT NULL,

    -- Constraints
    CONSTRAINT fk_jr_organization FOREIGN KEY (organization_id)
        REFERENCES organization (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_jr_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES app_user (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_jr_job_type FOREIGN KEY (job_type_lookup_id)
        REFERENCES job_type_lookup (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_jr_city FOREIGN KEY (city_id)
        REFERENCES city (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_experience_range
        CHECK (max_experience_months >= min_experience_months),
    CONSTRAINT chk_salary_range
        CHECK (
            min_salary IS NULL OR
            max_salary IS NULL OR
            max_salary >= min_salary
        ),
    CONSTRAINT chk_published_at
        CHECK (
            publish_state != 'PUBLISHED' OR
            published_at IS NOT NULL
        )
);

CREATE INDEX idx_jr_organization        ON job_requirement (organization_id);
CREATE INDEX idx_jr_city                ON job_requirement (city_id);
CREATE INDEX idx_jr_publish_state       ON job_requirement (publish_state);
CREATE INDEX idx_jr_job_type            ON job_requirement (job_type_lookup_id);
CREATE INDEX idx_jr_experience          ON job_requirement (min_experience_months, max_experience_months);
CREATE INDEX idx_jr_deleted             ON job_requirement (deleted_at)
    WHERE deleted_at IS NULL;

-- 4. JOB REQUIREMENT SKILL
CREATE TABLE job_requirement_skill (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_requirement_id      BIGINT          NOT NULL,
    skill_id                BIGINT          NOT NULL,
    is_mandatory            BOOLEAN         NOT NULL DEFAULT TRUE,
    min_experience_months   INT             NOT NULL DEFAULT 0
                            CHECK (min_experience_months >= 0),

    CONSTRAINT fk_jrs_job FOREIGN KEY (job_requirement_id)
        REFERENCES job_requirement (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_jrs_skill FOREIGN KEY (skill_id)
        REFERENCES skill (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_job_skill UNIQUE (job_requirement_id, skill_id)
);

CREATE INDEX idx_jrs_job_id     ON job_requirement_skill (job_requirement_id);
CREATE INDEX idx_jrs_skill_id   ON job_requirement_skill (skill_id);
