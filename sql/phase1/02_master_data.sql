-- ============================================================
-- MILESTONE 1.2: MASTER DATA & ALL LOOKUP TABLES
-- 9 Tables + Initial Reference Seeds
-- ============================================================

-- 1. COUNTRY
CREATE TABLE country (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso2_code           CHAR(2)         NOT NULL,
    iso3_code           CHAR(3)         NOT NULL,
    country_name        VARCHAR(100)    NOT NULL,
    phone_country_code  VARCHAR(10)     NOT NULL,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_country_iso2 UNIQUE (iso2_code),
    CONSTRAINT uq_country_iso3 UNIQUE (iso3_code)
);

-- 2. STATE / PROVINCE
CREATE TABLE state_province (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_id      BIGINT          NOT NULL,
    state_name      VARCHAR(100)    NOT NULL,
    state_code      VARCHAR(10)     NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_state_country FOREIGN KEY (country_id)
        REFERENCES country (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_state_code_per_country UNIQUE (country_id, state_code)
);

-- 3. CITY
CREATE TABLE city (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    state_province_id   BIGINT          NOT NULL,
    city_name           VARCHAR(100)    NOT NULL,
    latitude            DECIMAL(9,6)    NULL,
    longitude           DECIMAL(9,6)    NULL,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_city_state FOREIGN KEY (state_province_id)
        REFERENCES state_province (id) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- 4. INDUSTRY LOOKUP
CREATE TABLE industry_lookup (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    industry_code   VARCHAR(50)     NOT NULL,
    display_name    VARCHAR(100)    NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_industry_code UNIQUE (industry_code)
);

-- 5. SKILL
CREATE TABLE skill (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    skill_code      VARCHAR(50)     NOT NULL,
    skill_name      VARCHAR(100)    NOT NULL,
    skill_category  VARCHAR(50)     NOT NULL
                    CHECK (skill_category IN ('TECHNICAL','SOFT','DOMAIN','CERTIFICATION')),
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_skill_code UNIQUE (skill_code)
);

-- 6. LANGUAGE LOOKUP
CREATE TABLE language_lookup (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso_code        VARCHAR(10)     NOT NULL,
    language_name   VARCHAR(100)    NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_language_iso_code UNIQUE (iso_code)
);

-- 7. JOB TYPE LOOKUP
CREATE TABLE job_type_lookup (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_code       VARCHAR(30)     NOT NULL,
    display_name    VARCHAR(50)     NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_job_type_code UNIQUE (type_code)
);

-- 8. APPLICATION STATUS LOOKUP
CREATE TABLE application_status_lookup (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status_code     VARCHAR(30)     NOT NULL,
    display_name    VARCHAR(50)     NOT NULL,
    sort_order      INT             NOT NULL,
    is_terminal     BOOLEAN         NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_app_status_code UNIQUE (status_code)
);

-- 9. UI TRANSLATION TABLE (Multilingual — Rule Group 7)
CREATE TABLE ui_translation (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    translation_key     VARCHAR(150)    NOT NULL,
    language_lookup_id  BIGINT          NOT NULL,
    translated_text     TEXT            NOT NULL,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_translation_language FOREIGN KEY (language_lookup_id)
        REFERENCES language_lookup (id) ON DELETE RESTRICT,
    CONSTRAINT uq_translation_key_lang UNIQUE (translation_key, language_lookup_id)
);

-- Initial Reference Data Seeds
INSERT INTO country (iso2_code, iso3_code, country_name, phone_country_code) VALUES
('IN', 'IND', 'India',          '+91'),
('US', 'USA', 'United States',  '+1'),
('GB', 'GBR', 'United Kingdom', '+44'),
('AE', 'ARE', 'UAE',            '+971'),
('SG', 'SGP', 'Singapore',      '+65')
ON CONFLICT (iso2_code) DO NOTHING;

INSERT INTO industry_lookup (industry_code, display_name) VALUES
('IT_SOFTWARE',     'IT & Software'),
('BANKING_FINANCE', 'Banking & Finance'),
('HEALTHCARE',      'Healthcare'),
('ECOMMERCE',       'E-Commerce & Retail'),
('MANUFACTURING',   'Manufacturing'),
('EDUCATION',       'Education'),
('CONSULTING',      'Consulting'),
('MEDIA',           'Media & Entertainment')
ON CONFLICT (industry_code) DO NOTHING;

INSERT INTO skill (skill_code, skill_name, skill_category) VALUES
('PYTHON',      'Python',            'TECHNICAL'),
('JAVA',        'Java',              'TECHNICAL'),
('POSTGRESQL',  'PostgreSQL',        'TECHNICAL'),
('REACT',       'React.js',          'TECHNICAL'),
('NODE_JS',     'Node.js',           'TECHNICAL'),
('LEADERSHIP',  'Leadership',        'SOFT'),
('COMM',        'Communication',     'SOFT'),
('DATA_ANALYST','Data Analysis',     'DOMAIN'),
('PROJ_MGMT',   'Project Management','DOMAIN')
ON CONFLICT (skill_code) DO NOTHING;

INSERT INTO language_lookup (iso_code, language_name) VALUES
('en',    'English'),
('hi',    'Hindi'),
('ta',    'Tamil'),
('te',    'Telugu'),
('fr',    'French'),
('ar',    'Arabic')
ON CONFLICT (iso_code) DO NOTHING;

INSERT INTO job_type_lookup (type_code, display_name) VALUES
('FULL_TIME',           'Full Time'),
('PART_TIME',           'Part Time'),
('CONTRACT_IT',         'Contract - IT'),
('GENERAL_STAFFING',    'General Staffing'),
('APPRENTICE',          'Apprenticeship'),
('CAMPUS',              'Campus Hiring'),
('GIG',                 'Gig / Freelance')
ON CONFLICT (type_code) DO NOTHING;

INSERT INTO application_status_lookup (status_code, display_name, sort_order, is_terminal) VALUES
('APPLIED',         'Applied',          1, FALSE),
('SHORTLISTED',     'Shortlisted',      2, FALSE),
('INTERVIEWED',     'Interviewed',      3, FALSE),
('OFFERED',         'Offer Extended',   4, FALSE),
('JOINED',          'Joined',           5, TRUE),
('REJECTED',        'Rejected',         6, TRUE),
('WITHDRAWN',       'Withdrawn',        7, TRUE)
ON CONFLICT (status_code) DO NOTHING;
