-- ============================================================
-- Smart Blood Bank & Donation Management System
-- Database Schema — ShaktiDB (PostgreSQL 17.7)
-- ============================================================

-- Enable UUID extension (useful for future API keys)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- CLEANUP — Drop tables if re-running schema
-- ============================================================
DROP TABLE IF EXISTS AuditLog CASCADE;
DROP TABLE IF EXISTS RequestApprovals CASCADE;
DROP TABLE IF EXISTS BloodRequests CASCADE;
DROP TABLE IF EXISTS BloodInventory CASCADE;
DROP TABLE IF EXISTS Donations CASCADE;
DROP TABLE IF EXISTS DonorEligibility CASCADE;
DROP TABLE IF EXISTS Hospitals CASCADE;
DROP TABLE IF EXISTS Donors CASCADE;
DROP TABLE IF EXISTS Users CASCADE;

-- ============================================================
-- TABLE 1 — Users
-- Stores login credentials for all roles
-- ============================================================
CREATE TABLE Users (
  user_id        SERIAL PRIMARY KEY,
  email          VARCHAR(255) NOT NULL UNIQUE,
  password_hash  VARCHAR(255) NOT NULL,
  role           VARCHAR(20)  NOT NULL CHECK (role IN ('admin', 'donor', 'hospital_staff')),
  hospital_id    INTEGER,                        -- only set for hospital_staff
  active         BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast login lookup by email
CREATE INDEX idx_users_email ON Users(email);
CREATE INDEX idx_users_role  ON Users(role);

-- ============================================================
-- TABLE 2 — Donors
-- Personal details for each blood donor
-- ============================================================
CREATE TABLE Donors (
  donor_id       SERIAL PRIMARY KEY,
  user_id        INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
  first_name     VARCHAR(100) NOT NULL,
  last_name      VARCHAR(100) NOT NULL,
  blood_group    VARCHAR(5)   NOT NULL CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  date_of_birth  DATE         NOT NULL,
  gender         VARCHAR(10)  NOT NULL CHECK (gender IN ('male', 'female', 'other')),
  contact_phone  VARCHAR(20),
  address        TEXT,
  active         BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Donor must be at least 18 years old
  CONSTRAINT chk_donor_age CHECK (
    date_of_birth <= CURRENT_DATE - INTERVAL '18 years'
  )
);

CREATE INDEX idx_donors_blood_group ON Donors(blood_group);
CREATE INDEX idx_donors_user_id     ON Donors(user_id);

-- ============================================================
-- TABLE 3 — DonorEligibility
-- Tracks whether a donor is eligible to donate
-- Updated automatically by trigger after each donation
-- ============================================================
CREATE TABLE DonorEligibility (
  eligibility_id    SERIAL PRIMARY KEY,
  donor_id          INTEGER NOT NULL UNIQUE REFERENCES Donors(donor_id) ON DELETE CASCADE,
  eligible          BOOLEAN NOT NULL DEFAULT true,
  last_donation_date DATE,
  deferral_reason   VARCHAR(100),
  deferral_until    DATE,                        -- NULL means permanent deferral
  eligibility_status VARCHAR(30) NOT NULL DEFAULT 'eligible'
    CHECK (eligibility_status IN ('eligible', 'temporary_deferral', 'permanent_deferral')),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_eligibility_donor_id ON DonorEligibility(donor_id);
CREATE INDEX idx_eligibility_status   ON DonorEligibility(eligibility_status);

-- ============================================================
-- TABLE 4 — Hospitals
-- Registered hospitals that can request blood
-- ============================================================
CREATE TABLE Hospitals (
  hospital_id          SERIAL PRIMARY KEY,
  name                 VARCHAR(255) NOT NULL,
  registration_number  VARCHAR(100) NOT NULL UNIQUE,
  contact_email        VARCHAR(255),
  contact_phone        VARCHAR(20),
  address              TEXT,
  approved             BOOLEAN NOT NULL DEFAULT false,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_hospitals_approved ON Hospitals(approved);

-- Add foreign key from Users to Hospitals
-- (done after Hospitals table exists)
ALTER TABLE Users
  ADD CONSTRAINT fk_users_hospital
  FOREIGN KEY (hospital_id) REFERENCES Hospitals(hospital_id) ON DELETE SET NULL;

-- ============================================================
-- TABLE 5 — Donations
-- Records each blood donation event
-- ============================================================
CREATE TABLE Donations (
  donation_id      SERIAL PRIMARY KEY,
  donor_id         INTEGER NOT NULL REFERENCES Donors(donor_id) ON DELETE RESTRICT,
  donation_date    DATE    NOT NULL,
  blood_group      VARCHAR(5) NOT NULL CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  volume_ml        INTEGER NOT NULL CHECK (volume_ml BETWEEN 200 AND 550),
  donation_centre  VARCHAR(255),
  status           VARCHAR(20) NOT NULL DEFAULT 'completed'
    CHECK (status IN ('completed', 'pending', 'rejected')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_donations_donor_id     ON Donations(donor_id);
CREATE INDEX idx_donations_blood_group  ON Donations(blood_group);
CREATE INDEX idx_donations_date         ON Donations(donation_date);

-- ============================================================
-- TABLE 6 — BloodInventory
-- Current stock of each blood group
-- ============================================================
CREATE TABLE BloodInventory (
  inventory_id    SERIAL PRIMARY KEY,
  blood_group     VARCHAR(5) NOT NULL UNIQUE
    CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  units_available INTEGER NOT NULL DEFAULT 0,
  last_updated    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Critical constraint — inventory can never go negative
  CONSTRAINT chk_inventory_positive CHECK (units_available >= 0)
);

-- ============================================================
-- TABLE 7 — BloodRequests
-- Blood requests submitted by hospitals
-- ============================================================
CREATE TABLE BloodRequests (
  request_id      SERIAL PRIMARY KEY,
  hospital_id     INTEGER NOT NULL REFERENCES Hospitals(hospital_id) ON DELETE RESTRICT,
  blood_group     VARCHAR(5) NOT NULL CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  units_required  INTEGER NOT NULL CHECK (units_required > 0),
  urgency         VARCHAR(20) NOT NULL DEFAULT 'routine'
    CHECK (urgency IN ('routine', 'urgent', 'critical')),
  status          VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'fulfilled', 'cancelled')),
  notes           TEXT,
  requested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fulfilled_at    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_requests_hospital_id  ON BloodRequests(hospital_id);
CREATE INDEX idx_requests_blood_group  ON BloodRequests(blood_group);
CREATE INDEX idx_requests_status       ON BloodRequests(status);
CREATE INDEX idx_requests_requested_at ON BloodRequests(requested_at);

-- ============================================================
-- TABLE 8 — RequestApprovals
-- Records admin decisions on blood requests
-- ============================================================
CREATE TABLE RequestApprovals (
  approval_id    SERIAL PRIMARY KEY,
  request_id     INTEGER NOT NULL UNIQUE REFERENCES BloodRequests(request_id) ON DELETE CASCADE,
  admin_user_id  INTEGER NOT NULL REFERENCES Users(user_id) ON DELETE RESTRICT,
  decision       VARCHAR(20) NOT NULL CHECK (decision IN ('approved', 'rejected')),
  notes          TEXT,
  decision_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_approvals_request_id ON RequestApprovals(request_id);

-- ============================================================
-- TABLE 9 — AuditLog
-- Append-only log of all changes to core tables
-- ============================================================
CREATE TABLE AuditLog (
  log_id       SERIAL PRIMARY KEY,
  table_name   VARCHAR(50)  NOT NULL,
  record_id    INTEGER      NOT NULL,
  action       VARCHAR(10)  NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  changed_by   INTEGER REFERENCES Users(user_id) ON DELETE SET NULL,
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  old_values   JSONB,
  new_values   JSONB
);

CREATE INDEX idx_audit_table_name  ON AuditLog(table_name);
CREATE INDEX idx_audit_changed_at  ON AuditLog(changed_at);
CREATE INDEX idx_audit_record_id   ON AuditLog(record_id);

-- ============================================================
-- VIEWS
-- ============================================================

-- Inventory summary with traffic light status
CREATE OR REPLACE VIEW v_inventory_summary AS
SELECT
  blood_group,
  units_available,
  last_updated,
  CASE
    WHEN units_available < 5  THEN 'critical'
    WHEN units_available < 20 THEN 'low'
    ELSE 'adequate'
  END AS stock_status
FROM BloodInventory
ORDER BY blood_group;

-- Eligible donors ready to donate
CREATE OR REPLACE VIEW v_donor_eligible AS
SELECT
  d.donor_id,
  d.first_name,
  d.last_name,
  d.blood_group,
  d.contact_phone,
  e.last_donation_date,
  e.deferral_until
FROM Donors d
JOIN DonorEligibility e ON d.donor_id = e.donor_id
WHERE e.eligible = true
  AND e.eligibility_status = 'eligible'
  AND d.active = true;

-- Pending blood requests with hospital name
CREATE OR REPLACE VIEW v_pending_requests AS
SELECT
  r.request_id,
  h.name AS hospital_name,
  r.blood_group,
  r.units_required,
  r.urgency,
  r.requested_at,
  EXTRACT(EPOCH FROM (NOW() - r.requested_at))/3600 AS hours_waiting
FROM BloodRequests r
JOIN Hospitals h ON r.hospital_id = h.hospital_id
WHERE r.status = 'pending'
ORDER BY
  CASE r.urgency
    WHEN 'critical' THEN 1
    WHEN 'urgent'   THEN 2
    ELSE 3
  END,
  r.requested_at ASC;

-- Monthly donation summary for ML training
CREATE OR REPLACE VIEW v_donation_monthly AS
SELECT
  DATE_TRUNC('month', donation_date) AS month,
  blood_group,
  COUNT(*)                           AS total_donations,
  SUM(volume_ml)                     AS total_volume_ml
FROM Donations
WHERE status = 'completed'
GROUP BY DATE_TRUNC('month', donation_date), blood_group
ORDER BY month, blood_group;

-- ============================================================
-- TRIGGERS
-- ============================================================

-- TRIGGER 1 — After donation: update inventory and eligibility
CREATE OR REPLACE FUNCTION fn_after_donation()
RETURNS TRIGGER AS $$
BEGIN
  -- Increment inventory for the donated blood group
  UPDATE BloodInventory
  SET units_available = units_available + 1,
      last_updated    = NOW()
  WHERE blood_group = NEW.blood_group;

  -- Update donor eligibility — defer for 56 days
  UPDATE DonorEligibility
  SET eligible           = false,
      last_donation_date = NEW.donation_date,
      deferral_reason    = 'recent_donation',
      deferral_until     = NEW.donation_date + INTERVAL '56 days',
      eligibility_status = 'temporary_deferral',
      updated_at         = NOW()
  WHERE donor_id = NEW.donor_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_after_donation
  AFTER INSERT ON Donations
  FOR EACH ROW
  EXECUTE FUNCTION fn_after_donation();

-- TRIGGER 2 — After request fulfilled: decrement inventory
CREATE OR REPLACE FUNCTION fn_after_request_fulfilled()
RETURNS TRIGGER AS $$
BEGIN
  -- Only fire when status changes TO fulfilled
  IF NEW.status = 'fulfilled' AND OLD.status != 'fulfilled' THEN

    -- Check inventory is sufficient before decrementing
    IF (SELECT units_available FROM BloodInventory
        WHERE blood_group = NEW.blood_group) < NEW.units_required THEN
      RAISE EXCEPTION 'Insufficient inventory for blood group %. Available: %, Required: %',
        NEW.blood_group,
        (SELECT units_available FROM BloodInventory WHERE blood_group = NEW.blood_group),
        NEW.units_required;
    END IF;

    -- Decrement inventory
    UPDATE BloodInventory
    SET units_available = units_available - NEW.units_required,
        last_updated    = NOW()
    WHERE blood_group = NEW.blood_group;

    -- Set fulfilled timestamp
    UPDATE BloodRequests
    SET fulfilled_at = NOW()
    WHERE request_id = NEW.request_id;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_after_request_fulfilled
  AFTER UPDATE ON BloodRequests
  FOR EACH ROW
  EXECUTE FUNCTION fn_after_request_fulfilled();

-- TRIGGER 3 — Auto update updated_at timestamp
CREATE OR REPLACE FUNCTION fn_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON Users
  FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_donors_updated_at
  BEFORE UPDATE ON Donors
  FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_hospitals_updated_at
  BEFORE UPDATE ON Hospitals
  FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_requests_updated_at
  BEFORE UPDATE ON BloodRequests
  FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

-- TRIGGER 4 — Eligibility auto-restore when deferral expires
CREATE OR REPLACE FUNCTION fn_check_eligibility_expiry()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.deferral_until IS NOT NULL AND NEW.deferral_until <= CURRENT_DATE THEN
    NEW.eligible           = true;
    NEW.eligibility_status = 'eligible';
    NEW.deferral_reason    = NULL;
    NEW.deferral_until     = NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_eligibility_expiry
  BEFORE UPDATE ON DonorEligibility
  FOR EACH ROW EXECUTE FUNCTION fn_check_eligibility_expiry();

-- ============================================================
-- INITIAL INVENTORY ROWS
-- One row per blood group — updated by triggers
-- ============================================================
INSERT INTO BloodInventory (blood_group, units_available) VALUES
  ('A+',  0), ('A-',  0), ('B+',  0), ('B-',  0),
  ('AB+', 0), ('AB-', 0), ('O+',  0), ('O-',  0);

-- ============================================================
-- SCHEMA COMPLETE
-- ============================================================
SELECT 'Schema created successfully' AS status;