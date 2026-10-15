-- ============================================================
-- MILESTONE 1.3: IDENTITY, USERS & SESSION CONTROL
-- 4 Tables: role_lookup, app_user, user_role_mapping, user_session
-- ============================================================

-- 1. ROLE LOOKUP
CREATE TABLE role_lookup (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_code       VARCHAR(50)     NOT NULL,
    description     VARCHAR(255)    NOT NULL,

    CONSTRAINT uq_role_code UNIQUE (role_code)
);

-- 2. APP USER
CREATE TABLE app_user (
    id                              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email                           VARCHAR(254)    NOT NULL,
    password_hash                   VARCHAR(255)    NOT NULL,
    user_type                       VARCHAR(30)     NOT NULL
                                    CHECK (user_type IN (
                                        'CANDIDATE','RECRUITER',
                                        'CONSULTANT','ADMIN','TPO'
                                    )),
    phone_number                    VARCHAR(20)     NOT NULL,
    phone_country_code              VARCHAR(10)     NOT NULL,
    country_id                      BIGINT          NOT NULL,
    preferred_language_id           BIGINT          NULL,
    is_verified                     BOOLEAN         NOT NULL DEFAULT FALSE,
    identity_verification_status    VARCHAR(20)     NOT NULL DEFAULT 'UNVERIFIED'
                                    CHECK (identity_verification_status IN (
                                        'UNVERIFIED','PENDING','PASSED','FAILED'
                                    )),
    identity_verification_token     VARCHAR(255)    NULL,
    is_active                       BOOLEAN         NOT NULL DEFAULT TRUE,
    deleted_at                      TIMESTAMPTZ     NULL,

    -- Audit columns (Rule Group 4)
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_by      BIGINT          NULL,   -- NULL for self-registration
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_by      BIGINT          NULL,

    -- Constraints
    CONSTRAINT uq_app_user_email UNIQUE (email),
    CONSTRAINT fk_user_country FOREIGN KEY (country_id)
        REFERENCES country (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_user_language FOREIGN KEY (preferred_language_id)
        REFERENCES language_lookup (id) ON DELETE SET NULL
);

CREATE INDEX idx_app_user_email        ON app_user (email);
CREATE INDEX idx_app_user_user_type    ON app_user (user_type);
CREATE INDEX idx_app_user_is_active    ON app_user (is_active);

-- 3. USER ROLE MAPPING
CREATE TABLE user_role_mapping (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id     BIGINT          NOT NULL,
    role_lookup_id  BIGINT          NOT NULL,
    assigned_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    assigned_by     BIGINT          NOT NULL,

    CONSTRAINT fk_urm_user FOREIGN KEY (app_user_id)
        REFERENCES app_user (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_urm_role FOREIGN KEY (role_lookup_id)
        REFERENCES role_lookup (id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uq_user_role UNIQUE (app_user_id, role_lookup_id)
);

CREATE INDEX idx_user_role_mapping_user_id ON user_role_mapping (app_user_id);

-- 4. USER SESSION
CREATE TABLE user_session (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    app_user_id         BIGINT          NOT NULL,
    device_identifier   VARCHAR(128)    NOT NULL,
    device_type         VARCHAR(20)     NULL
                        CHECK (device_type IN ('WEB','ANDROID','IOS','DESKTOP')),
    ip_address          VARCHAR(45)     NOT NULL,
    user_agent          VARCHAR(500)    NOT NULL,
    session_token_hash  VARCHAR(255)    NOT NULL,
    session_start       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    last_activity       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    session_end         TIMESTAMPTZ     NULL,
    is_revoked          BOOLEAN         NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_session_user FOREIGN KEY (app_user_id)
        REFERENCES app_user (id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_active_device_session UNIQUE (app_user_id, device_identifier)
);

CREATE INDEX idx_user_session_user_id     ON user_session (app_user_id);
CREATE INDEX idx_user_session_is_revoked  ON user_session (is_revoked);

-- Seed initial system roles
INSERT INTO role_lookup (role_code, description) VALUES
('SUPER_ADMIN',     'Full platform access. Manages all organizations and users.'),
('ACCOUNT_ADMIN',   'Manages users and settings within their own organization.'),
('RECRUITER',       'Posts jobs, views candidates, manages applications.'),
('CONSULTANT',      'External recruiter who sources candidates for client jobs.'),
('TPO',             'Training & Placement Officer for campus hiring.'),
('CANDIDATE',       'Job seeker with a profile on the platform.')
ON CONFLICT (role_code) DO NOTHING;
