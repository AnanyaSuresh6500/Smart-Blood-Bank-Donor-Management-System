const jwt = require('jsonwebtoken');
const pool = require('../config/db');

const authenticate = async (req, res, next) => {
  try {
    // Get token from Authorization header
    // Format: "Bearer eyJhbGciOiJIUzI1NiIs..."
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        error: 'UNAUTHORIZED',
        message: 'No token provided'
      });
    }

    const token = authHeader.split(' ')[1];

    // Verify token signature and expiry
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // Check user still exists and is active
    const result = await pool.query(
      'SELECT user_id, email, role, hospital_id, active FROM Users WHERE user_id = $1',
      [decoded.user_id]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({
        error: 'UNAUTHORIZED',
        message: 'User not found'
      });
    }

    const user = result.rows[0];

    if (!user.active) {
      return res.status(403).json({
        error: 'FORBIDDEN',
        message: 'Account is deactivated'
      });
    }

    // Attach user info to request object
    // Now any route handler can access req.user
    req.user = user;
    next();

  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'UNAUTHORIZED',
        message: 'Token expired'
      });
    }
    if (err.name === 'JsonWebTokenError') {
      return res.status(401).json({
        error: 'UNAUTHORIZED',
        message: 'Invalid token'
      });
    }
    next(err);
  }
};

module.exports = authenticate;