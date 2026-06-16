const pool = require('../config/db');

/**
 * Check if a donor is currently eligible to donate
 * Returns eligibility status and reason if not eligible
 */
const checkEligibility = async (donorId) => {
  const result = await pool.query(
    `SELECT
      e.eligible,
      e.eligibility_status,
      e.deferral_reason,
      e.deferral_until,
      e.last_donation_date,
      d.date_of_birth,
      d.blood_group
    FROM DonorEligibility e
    JOIN Donors d ON e.donor_id = d.donor_id
    WHERE e.donor_id = $1`,
    [donorId]
  );

  if (result.rows.length === 0) {
    return { eligible: false, reason: 'Donor not found' };
  }

  const e = result.rows[0];

  // Check if temporary deferral has expired
  if (e.eligibility_status === 'temporary_deferral' && e.deferral_until) {
    const today = new Date();
    const deferralEnd = new Date(e.deferral_until);

    if (today >= deferralEnd) {
      // Deferral expired — update eligibility
      await pool.query(
        `UPDATE DonorEligibility
         SET eligible = true, eligibility_status = 'eligible',
             deferral_reason = NULL, deferral_until = NULL,
             updated_at = NOW()
         WHERE donor_id = $1`,
        [donorId]
      );
      return { eligible: true, reason: null };
    }

    const daysRemaining = Math.ceil((deferralEnd - today) / (1000 * 60 * 60 * 24));
    return {
      eligible: false,
      reason: `Temporary deferral — eligible again in ${daysRemaining} days`,
      deferral_until: e.deferral_until,
      days_remaining: daysRemaining
    };
  }

  if (e.eligibility_status === 'permanent_deferral') {
    return {
      eligible: false,
      reason: `Permanent deferral: ${e.deferral_reason || 'Medical condition'}`
    };
  }

  return { eligible: true, reason: null };
};

/**
 * Get full eligibility details for display on donor dashboard
 */
const getEligibilityDetails = async (donorId) => {
  const result = await pool.query(
    `SELECT
      e.*,
      d.blood_group,
      d.first_name,
      d.last_name
    FROM DonorEligibility e
    JOIN Donors d ON e.donor_id = d.donor_id
    WHERE e.donor_id = $1`,
    [donorId]
  );

  return result.rows[0] || null;
};

module.exports = { checkEligibility, getEligibilityDetails };