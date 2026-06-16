const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('../config/db');

// Generate a short-lived access token (15 minutes)
const generateAccessToken = (user) => {
  return jwt.sign(
    { user_id: user.user_id, role: user.role, email: user.email },
    process.env.JWT_SECRET,
    { expiresIn: '15m' }
  );
};

// Generate a long-lived refresh token (7 days)
const generateRefreshToken = (user) => {
  return jwt.sign(
    { user_id: user.user_id },
    process.env.JWT_REFRESH_SECRET,
    { expiresIn: '7d' }
  );
};

/**
 * REGISTER
 * Creates a new user account and donor/hospital profile
 */
const register = async (data) => {
  const {
    email, password, role,
    first_name, last_name, blood_group,
    date_of_birth, gender, contact_phone,
    address, hospital_id
  } = data;

  // Check if email already exists
  const existing = await pool.query(
    'SELECT user_id FROM Users WHERE email = $1', [email]
  );
  if (existing.rows.length > 0) {
    throw { status: 409, code: 'CONFLICT', message: 'Email already registered' };
  }

  // Hash password
  const password_hash = await bcrypt.hash(password, 12);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Create user account
    const userResult = await client.query(
      `INSERT INTO Users (email, password_hash, role, hospital_id, active)
       VALUES ($1, $2, $3, $4, true)
       RETURNING user_id, email, role`,
      [email, password_hash, role, hospital_id || null]
    );

    const user = userResult.rows[0];

    // If donor — create donor profile and eligibility record
    if (role === 'donor') {
      const donorResult = await client.query(
        `INSERT INTO Donors
           (user_id, first_name, last_name, blood_group,
            date_of_birth, gender, contact_phone, address)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING donor_id`,
        [user.user_id, first_name, last_name, blood_group,
         date_of_birth, gender, contact_phone || null, address || null]
      );

      // Create initial eligibility record
      await client.query(
        `INSERT INTO DonorEligibility
           (donor_id, eligible, eligibility_status)
         VALUES ($1, true, 'eligible')`,
        [donorResult.rows[0].donor_id]
      );
    }

    await client.query('COMMIT');
    return { user_id: user.user_id, email: user.email, role: user.role };

  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

/**
 * LOGIN
 * Verify credentials and return tokens
 */
const login = async (email, password) => {
  // Find user by email
  const result = await pool.query(
    `SELECT u.user_id, u.email, u.password_hash, u.role,
            u.hospital_id, u.active,
            d.donor_id
     FROM Users u
     LEFT JOIN Donors d ON u.user_id = d.user_id
     WHERE u.email = $1`,
    [email]
  );

  if (result.rows.length === 0) {
    throw { status: 401, code: 'UNAUTHORIZED', message: 'Invalid email or password' };
  }

  const user = result.rows[0];

  if (!user.active) {
    throw { status: 403, code: 'FORBIDDEN', message: 'Account is deactivated' };
  }

  // Compare password with hash
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) {
    throw { status: 401, code: 'UNAUTHORIZED', message: 'Invalid email or password' };
  }

  // Generate tokens
  const accessToken  = generateAccessToken(user);
  const refreshToken = generateRefreshToken(user);

  // Store hashed refresh token in database
  const refreshHash = await bcrypt.hash(refreshToken, 10);
  await pool.query(
    'UPDATE Users SET refresh_token_hash = $1 WHERE user_id = $2',
    [refreshHash, user.user_id]
  );

  return {
    accessToken,
    refreshToken,
    user: {
      user_id:     user.user_id,
      email:       user.email,
      role:        user.role,
      donor_id:    user.donor_id || null,
      hospital_id: user.hospital_id || null,
    }
  };
};

/**
 * REFRESH
 * Issue new access token from valid refresh token
 */
const refresh = async (refreshToken) => {
  try {
    const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);

    const result = await pool.query(
      'SELECT user_id, email, role, refresh_token_hash, active FROM Users WHERE user_id = $1',
      [decoded.user_id]
    );

    if (result.rows.length === 0) {
      throw { status: 401, code: 'UNAUTHORIZED', message: 'User not found' };
    }

    const user = result.rows[0];

    if (!user.active) {
      throw { status: 403, code: 'FORBIDDEN', message: 'Account deactivated' };
    }

    // Verify the refresh token matches what's stored
    if (!user.refresh_token_hash) {
      throw { status: 401, code: 'UNAUTHORIZED', message: 'No active session' };
    }

    const valid = await bcrypt.compare(refreshToken, user.refresh_token_hash);
    if (!valid) {
      throw { status: 401, code: 'UNAUTHORIZED', message: 'Invalid refresh token' };
    }

    // Issue new access token
    const accessToken = generateAccessToken(user);
    return { accessToken };

  } catch (err) {
    if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
      throw { status: 401, code: 'UNAUTHORIZED', message: 'Invalid or expired refresh token' };
    }
    throw err;
  }
};

/**
 * LOGOUT
 * Revoke refresh token by deleting it from database
 */
const logout = async (userId) => {
  await pool.query(
    'UPDATE Users SET refresh_token_hash = NULL WHERE user_id = $1',
    [userId]
  );
};

module.exports = { register, login, refresh, logout };