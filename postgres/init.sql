-- ============================================
-- PostgreSQL Secure Initialization Script (Unified Schema)
-- For: PropTech Application, Audit, Vault, Quartz Jobs
-- ============================================

-- ============================================
-- 1️⃣ Create Databases
-- ============================================

CREATE DATABASE proptechdb
    WITH OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

CREATE DATABASE auditdb
    WITH OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

CREATE DATABASE vaultdb
    WITH OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

CREATE DATABASE quartzdb
    WITH OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

-- ============================================
-- 2️⃣ Create Roles (shared principle: least privilege)
-- ============================================

CREATE ROLE proptech_app WITH LOGIN PASSWORD '38atgkgij98x5cat79qwgn0xl' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 10;
CREATE ROLE proptech_app_readonly WITH LOGIN PASSWORD '38atgkgij98x5cat79qwgn0xl' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 5;
CREATE ROLE audit_app WITH LOGIN PASSWORD '38atgkgij98x5cat79qwgn0xl' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 5;
CREATE ROLE vault_app WITH LOGIN PASSWORD '38atgkgij98x5cat79qwgn0xl' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 5;
CREATE ROLE quartz_app WITH LOGIN PASSWORD '38atgkgij98x5cat79qwgn0xl' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 5;

-- ============================================
-- 3️⃣ Initialize Each Database with Schema 'core'
-- ============================================

\connect proptechdb

CREATE SCHEMA IF NOT EXISTS core AUTHORIZATION proptech_app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON DATABASE proptechdb FROM PUBLIC;
ALTER DATABASE proptechdb SET search_path TO core, public;

GRANT CONNECT ON DATABASE proptechdb TO proptech_app, proptech_app_readonly;
GRANT USAGE, CREATE ON SCHEMA core TO proptech_app;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO proptech_app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT ON TABLES TO proptech_app_readonly;

-- ============================================
\connect auditdb

CREATE SCHEMA IF NOT EXISTS core AUTHORIZATION audit_app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
ALTER DATABASE auditdb SET search_path TO core, public;

GRANT CONNECT ON DATABASE auditdb TO audit_app;
GRANT USAGE, CREATE ON SCHEMA core TO audit_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO audit_app;

-- ============================================
\connect vaultdb

CREATE SCHEMA IF NOT EXISTS core AUTHORIZATION vault_app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
ALTER DATABASE vaultdb SET search_path TO core, public;

GRANT CONNECT ON DATABASE vaultdb TO vault_app;
GRANT USAGE, CREATE ON SCHEMA core TO vault_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO vault_app;

-- ============================================
\connect quartzdb

CREATE SCHEMA IF NOT EXISTS core AUTHORIZATION quartz_app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
ALTER DATABASE quartzdb SET search_path TO core, public;

GRANT CONNECT ON DATABASE quartzdb TO quartz_app;
GRANT USAGE, CREATE ON SCHEMA core TO quartz_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO quartz_app;

-- ============================================
-- 4️⃣ Global Hardening
-- ============================================

-- Disable PUBLIC access to default schemas in all DBs
REVOKE ALL ON DATABASE proptechdb FROM PUBLIC;
REVOKE ALL ON DATABASE auditdb FROM PUBLIC;
REVOKE ALL ON DATABASE vaultdb FROM PUBLIC;
REVOKE ALL ON DATABASE quartzdb FROM PUBLIC;

-- Enforce stricter role-level limits
ALTER ROLE proptech_app SET statement_timeout = '5min';
ALTER ROLE proptech_app SET idle_in_transaction_session_timeout = '5min';
ALTER ROLE proptech_app SET log_statement = 'ddl';
ALTER ROLE proptech_app SET search_path = core, public;

-- Optional: enforce password encryption
SHOW password_encryption;

\connect vaultdb
BEGIN;


CREATE TABLE vault_kv_store
(
    parent_path TEXT COLLATE "C" NOT NULL,
    path        TEXT COLLATE "C",
    key         TEXT COLLATE "C",
    value       BYTEA,
    CONSTRAINT vault_kv_store_pkey PRIMARY KEY (path, key)
);


CREATE INDEX parent_path_idx ON vault_kv_store (parent_path);


CREATE TABLE vault_ha_locks
(
    ha_key      TEXT COLLATE "C"         NOT NULL,
    ha_identity TEXT COLLATE "C"         NOT NULL,
    ha_value    TEXT COLLATE "C",
    valid_until TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT vault_ha_locks_pkey PRIMARY KEY (ha_key)
);

COMMIT;