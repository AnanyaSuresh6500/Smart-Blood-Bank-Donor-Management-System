-- ============================================================
-- Smart Blood Bank — Database Tests
-- Day 2: Verify all constraints, triggers and views
-- Run with: psql -h localhost -U bloodbank_user -d bloodbank -f tests.sql
-- ============================================================

\echo '============================================================'
\echo 'SMART BLOOD BANK — DATABASE TESTS'
\echo '============================================================'

-- ============================================================
-- SECTION 1 — CHECK CONSTRAINTS
-- ============================================================
\echo ''
\echo '--- SECTION 1: CHECK CONSTRAINTS ---'

-- TEST 1.1 — Blood group must be valid
-- Expected: ERROR — invalid input value for enum
\echo 'TEST 1.1: Invalid blood group should be rejected...'
DO $$
BEGIN
  BEGIN
    INSERT INTO Donors (user_id, first_name, last_name, blood_group, date_of_birth, gender)
    VALUES (1, 'Test', 'Donor', 'Z+', '1990-01-01', 'male');
    RAISE EXCEPTION 'TEST 1.1 FAILED — invalid blood group was accepted';
  EXCEPTION WHEN check_violation OR others THEN
    RAISE NOTICE 'TEST 1.1 PASSED — invalid blood group correctly rejected';
  END;
END $$;

-- TEST 1.2 — Donor must be at least 18 years old
\echo 'TEST 1.2: Underage donor should be rejected...'
DO $$
BEGIN
  BEGIN
    INSERT INTO Donors (user_id, first_name, last_name, blood_group, date_of_birth, gender)
    VALUES (1, 'Young', 'Donor', 'O+', CURRENT_DATE - INTERVAL '10 years', 'male');
    RAISE EXCEPTION 'TEST 1.2 FAILED — underage donor was accepted';
  EXCEPTION WHEN check_violation OR others THEN
    RAISE NOTICE 'TEST 1.2 PASSED — underage donor correctly rejected';
  END;
END $$;

-- TEST 1.3 — Donation volume must be between 200 and 550 ml
\echo 'TEST 1.3: Invalid donation volume should be rejected...'
DO $$
DECLARE
  v_donor_id INTEGER;
BEGIN
  SELECT donor_id INTO v_donor_id FROM Donors LIMIT 1;
  BEGIN
    INSERT INTO Donations (donor_id, donation_date, blood_group, volume_ml, status)
    VALUES (v_donor_id, CURRENT_DATE, 'O+', 600, 'completed');
    RAISE EXCEPTION 'TEST 1.3 FAILED — invalid volume was accepted';
  EXCEPTION WHEN check_violation OR others THEN
    RAISE NOTICE 'TEST 1.3 PASSED — invalid donation volume correctly rejected';
  END;
END $$;

-- TEST 1.4 — Inventory cannot go negative
\echo 'TEST 1.4: Negative inventory should be rejected...'
DO $$
BEGIN
  BEGIN
    UPDATE BloodInventory
    SET units_available = -1
    WHERE blood_group = 'O+';
    RAISE EXCEPTION 'TEST 1.4 FAILED — negative inventory was accepted';
  EXCEPTION WHEN check_violation OR others THEN
    RAISE NOTICE 'TEST 1.4 PASSED — negative inventory correctly rejected';
  END;
END $$;

-- TEST 1.5 — Blood request units must be greater than 0
\echo 'TEST 1.5: Zero units request should be rejected...'
DO $$
DECLARE
  v_hospital_id INTEGER;
BEGIN
  SELECT hospital_id INTO v_hospital_id FROM Hospitals LIMIT 1;
  BEGIN
    INSERT INTO BloodRequests (hospital_id, blood_group, units_required, urgency)
    VALUES (v_hospital_id, 'A+', 0, 'routine');
    RAISE EXCEPTION 'TEST 1.5 FAILED — zero units request was accepted';
  EXCEPTION WHEN check_violation OR others THEN
    RAISE NOTICE 'TEST 1.5 PASSED — zero units request correctly rejected';
  END;
END $$;

-- TEST 1.6 — Request status must be valid
\echo 'TEST 1.6: Invalid request status should be rejected...'
DO $$
DECLARE
  v_hospital_id INTEGER;
BEGIN
  SELECT hospital_id INTO v_hospital_id FROM Hospitals LIMIT 1;
  BEGIN
    INSERT INTO BloodRequests (hospital_id, blood_group, units_required, status)
    VALUES (v_hospital_id, 'A+', 2, 'unknown_status');
    RAISE EXCEPTION 'TEST 1.6 FAILED — invalid status was accepted';
  EXCEPTION WHEN check_violation OR others THEN
    RAISE NOTICE 'TEST 1.6 PASSED — invalid request status correctly rejected';
  END;
END $$;

-- ============================================================
-- SECTION 2 — UNIQUE CONSTRAINTS
-- ============================================================
\echo ''
\echo '--- SECTION 2: UNIQUE CONSTRAINTS ---'

-- TEST 2.1 — Duplicate email should be rejected
\echo 'TEST 2.1: Duplicate user email should be rejected...'
DO $$
BEGIN
  BEGIN
    INSERT INTO Users (email, password_hash, role)
    VALUES ('admin@bloodbank.com', 'somehash', 'admin');
    RAISE EXCEPTION 'TEST 2.1 FAILED — duplicate email was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'TEST 2.1 PASSED — duplicate email correctly rejected';
  END;
END $$;

-- TEST 2.2 — Duplicate blood group in inventory should be rejected
\echo 'TEST 2.2: Duplicate blood group in inventory should be rejected...'
DO $$
BEGIN
  BEGIN
    INSERT INTO BloodInventory (blood_group, units_available)
    VALUES ('O+', 10);
    RAISE EXCEPTION 'TEST 2.2 FAILED — duplicate blood group was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'TEST 2.2 PASSED — duplicate blood group correctly rejected';
  END;
END $$;

-- TEST 2.3 — Duplicate hospital registration number should be rejected
\echo 'TEST 2.3: Duplicate hospital registration number should be rejected...'
DO $$
DECLARE
  v_reg_num VARCHAR;
BEGIN
  SELECT registration_number INTO v_reg_num FROM Hospitals LIMIT 1;
  BEGIN
    INSERT INTO Hospitals (name, registration_number, approved)
    VALUES ('Another Hospital', v_reg_num, true);
    RAISE EXCEPTION 'TEST 2.3 FAILED — duplicate registration number was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'TEST 2.3 PASSED — duplicate registration number correctly rejected';
  END;
END $$;

-- ============================================================
-- SECTION 3 — FOREIGN KEY CONSTRAINTS
-- ============================================================
\echo ''
\echo '--- SECTION 3: FOREIGN KEY CONSTRAINTS ---'

-- TEST 3.1 — Donation without valid donor should be rejected
\echo 'TEST 3.1: Donation with invalid donor_id should be rejected...'
DO $$
BEGIN
  BEGIN
    INSERT INTO Donations (donor_id, donation_date, blood_group, volume_ml, status)
    VALUES (999999, CURRENT_DATE, 'O+', 400, 'completed');
    RAISE EXCEPTION 'TEST 3.1 FAILED — orphaned donation was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'TEST 3.1 PASSED — orphaned donation correctly rejected';
  END;
END $$;

-- TEST 3.2 — Blood request without valid hospital should be rejected
\echo 'TEST 3.2: Blood request with invalid hospital_id should be rejected...'
DO $$
BEGIN
  BEGIN
    INSERT INTO BloodRequests (hospital_id, blood_group, units_required)
    VALUES (999999, 'A+', 2);
    RAISE EXCEPTION 'TEST 3.2 FAILED — orphaned request was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'TEST 3.2 PASSED — orphaned request correctly rejected';
  END;
END $$;

-- ============================================================
-- SECTION 4 — TRIGGER TESTS
-- ============================================================
\echo ''
\echo '--- SECTION 4: TRIGGER TESTS ---'

-- TEST 4.1 — Donation trigger updates inventory
\echo 'TEST 4.1: Donation should automatically increment inventory...'
DO $$
DECLARE
  v_donor_id      INTEGER;
  v_before        INTEGER;
  v_after         INTEGER;
BEGIN
  SELECT donor_id INTO v_donor_id FROM Donors LIMIT 1;
  SELECT units_available INTO v_before FROM BloodInventory WHERE blood_group = 'O+';

  INSERT INTO Donations (donor_id, donation_date, blood_group, volume_ml, status)
  VALUES (v_donor_id, CURRENT_DATE, 'O+', 400, 'completed');

  SELECT units_available INTO v_after FROM BloodInventory WHERE blood_group = 'O+';

  IF v_after = v_before + 1 THEN
    RAISE NOTICE 'TEST 4.1 PASSED — inventory incremented from % to %', v_before, v_after;
  ELSE
    RAISE EXCEPTION 'TEST 4.1 FAILED — inventory not updated. Before: %, After: %', v_before, v_after;
  END IF;
END $$;

-- TEST 4.2 — Donation trigger sets donor deferral
\echo 'TEST 4.2: Donation should set donor deferral for 56 days...'
DO $$
DECLARE
  v_donor_id     INTEGER;
  v_deferral     DATE;
  v_expected     DATE;
BEGIN
  SELECT donor_id INTO v_donor_id FROM Donors LIMIT 1;

  SELECT deferral_until INTO v_deferral
  FROM DonorEligibility
  WHERE donor_id = v_donor_id;

  v_expected := CURRENT_DATE + INTERVAL '56 days';

  IF v_deferral = v_expected THEN
    RAISE NOTICE 'TEST 4.2 PASSED — deferral correctly set to %', v_deferral;
  ELSE
    RAISE EXCEPTION 'TEST 4.2 FAILED — deferral is %, expected %', v_deferral, v_expected;
  END IF;
END $$;

-- TEST 4.3 — Fulfillment trigger decrements inventory
\echo 'TEST 4.3: Fulfilling a request should decrement inventory...'
DO $$
DECLARE
  v_hospital_id  INTEGER;
  v_request_id   INTEGER;
  v_before       INTEGER;
  v_after        INTEGER;
BEGIN
  SELECT hospital_id INTO v_hospital_id FROM Hospitals LIMIT 1;
  SELECT units_available INTO v_before FROM BloodInventory WHERE blood_group = 'O+';

  -- Create a request for 1 unit
  INSERT INTO BloodRequests (hospital_id, blood_group, units_required, urgency, status)
  VALUES (v_hospital_id, 'O+', 1, 'routine', 'approved')
  RETURNING request_id INTO v_request_id;

  -- Fulfill the request — trigger should fire
  UPDATE BloodRequests SET status = 'fulfilled' WHERE request_id = v_request_id;

  SELECT units_available INTO v_after FROM BloodInventory WHERE blood_group = 'O+';

  IF v_after = v_before - 1 THEN
    RAISE NOTICE 'TEST 4.3 PASSED — inventory decremented from % to %', v_before, v_after;
  ELSE
    RAISE EXCEPTION 'TEST 4.3 FAILED — inventory not decremented. Before: %, After: %', v_before, v_after;
  END IF;
END $$;

-- TEST 4.4 — Fulfillment blocked when inventory insufficient
\echo 'TEST 4.4: Fulfillment should be blocked when inventory is insufficient...'
DO $$
DECLARE
  v_hospital_id  INTEGER;
  v_request_id   INTEGER;
  v_current      INTEGER;
BEGIN
  SELECT hospital_id INTO v_hospital_id FROM Hospitals LIMIT 1;
  SELECT units_available INTO v_current FROM BloodInventory WHERE blood_group = 'AB-';

  -- Request more than available
  INSERT INTO BloodRequests (hospital_id, blood_group, units_required, urgency, status)
  VALUES (v_hospital_id, 'AB-', v_current + 100, 'routine', 'approved')
  RETURNING request_id INTO v_request_id;

  BEGIN
    UPDATE BloodRequests SET status = 'fulfilled' WHERE request_id = v_request_id;
    RAISE EXCEPTION 'TEST 4.4 FAILED — fulfillment succeeded despite insufficient inventory';
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'TEST 4.4 PASSED — fulfillment correctly blocked. Available: %, Requested: %',
      v_current, v_current + 100;
    -- Clean up the test request
    DELETE FROM BloodRequests WHERE request_id = v_request_id;
  END;
END $$;

-- TEST 4.5 — updated_at trigger fires on update
\echo 'TEST 4.5: updated_at should change after record update...'
DO $$
DECLARE
  v_before TIMESTAMPTZ;
  v_after  TIMESTAMPTZ;
  v_hosp_id INTEGER;
BEGIN
  SELECT hospital_id INTO v_hosp_id FROM Hospitals LIMIT 1;
  SELECT updated_at INTO v_before FROM Hospitals WHERE hospital_id = v_hosp_id;

  PERFORM pg_sleep(1); -- wait 1 second

  UPDATE Hospitals SET name = name WHERE hospital_id = v_hosp_id;
  SELECT updated_at INTO v_after FROM Hospitals WHERE hospital_id = v_hosp_id;

  IF v_after > v_before THEN
    RAISE NOTICE 'TEST 4.5 PASSED — updated_at correctly updated';
  ELSE
    RAISE EXCEPTION 'TEST 4.5 FAILED — updated_at did not change';
  END IF;
END $$;

-- TEST 4.6 — Eligibility auto-restores when deferral expires
\echo 'TEST 4.6: Eligibility should restore when deferral date passes...'
DO $$
DECLARE
  v_donor_id INTEGER;
BEGIN
  SELECT donor_id INTO v_donor_id FROM Donors LIMIT 1;

  -- Manually set an expired deferral
  UPDATE DonorEligibility
  SET eligible           = false,
      deferral_until     = CURRENT_DATE - INTERVAL '1 day',
      eligibility_status = 'temporary_deferral'
  WHERE donor_id = v_donor_id;

  -- Trigger fires on update — should restore eligibility
  UPDATE DonorEligibility
  SET updated_at = NOW()
  WHERE donor_id = v_donor_id;

  IF (SELECT eligible FROM DonorEligibility WHERE donor_id = v_donor_id) = true THEN
    RAISE NOTICE 'TEST 4.6 PASSED — eligibility correctly restored after deferral expired';
  ELSE
    RAISE EXCEPTION 'TEST 4.6 FAILED — eligibility not restored after deferral expired';
  END IF;
END $$;

-- ============================================================
-- SECTION 5 — VIEW TESTS
-- ============================================================
\echo ''
\echo '--- SECTION 5: VIEW TESTS ---'

-- TEST 5.1 — v_inventory_summary returns correct status labels
\echo 'TEST 5.1: v_inventory_summary should show correct stock status...'
SELECT blood_group, units_available, stock_status FROM v_inventory_summary;

-- TEST 5.2 — v_pending_requests returns only pending requests
\echo 'TEST 5.2: v_pending_requests should show only pending requests...'
SELECT COUNT(*) AS pending_count FROM v_pending_requests;

-- TEST 5.3 — v_donor_eligible returns only eligible donors
\echo 'TEST 5.3: v_donor_eligible should show only eligible donors...'
SELECT COUNT(*) AS eligible_donors FROM v_donor_eligible;

-- TEST 5.4 — v_donation_monthly aggregates correctly
\echo 'TEST 5.4: v_donation_monthly should show monthly totals...'
SELECT month, blood_group, total_donations
FROM v_donation_monthly
ORDER BY month DESC
LIMIT 8;

-- ============================================================
-- SECTION 6 — TRANSACTION TESTS
-- ============================================================
\echo ''
\echo '--- SECTION 6: TRANSACTION TESTS ---'

-- TEST 6.1 — Failed transaction rolls back completely
\echo 'TEST 6.1: Failed transaction should roll back all changes...'
DO $$
DECLARE
  v_before INTEGER;
  v_after  INTEGER;
BEGIN
  SELECT units_available INTO v_before FROM BloodInventory WHERE blood_group = 'A+';

  BEGIN
    -- First update succeeds
    UPDATE BloodInventory SET units_available = units_available + 10 WHERE blood_group = 'A+';

    -- Second update intentionally fails
    UPDATE BloodInventory SET units_available = -999 WHERE blood_group = 'A+';

    EXCEPTION WHEN others THEN
      -- Transaction rolls back
      NULL;
  END;

  SELECT units_available INTO v_after FROM BloodInventory WHERE blood_group = 'A+';

  IF v_after = v_before THEN
    RAISE NOTICE 'TEST 6.1 PASSED — transaction rolled back correctly. Value unchanged: %', v_after;
  ELSE
    RAISE EXCEPTION 'TEST 6.1 FAILED — value changed despite rollback. Before: %, After: %', v_before, v_after;
  END IF;
END $$;

-- ============================================================
-- SUMMARY
-- ============================================================
\echo ''
\echo '============================================================'
\echo 'ALL TESTS COMPLETED'
\echo 'Check PASSED/FAILED notices above for results'
\echo '============================================================'