const express = require('express');
const router  = express.Router();
const authService  = require('../services/auth.service');
const validate     = require('../middleware/validate');
const authenticate = require('../middleware/auth');
const { loginLimiter } = require('../middleware/rateLimit');

/**
 * POST /auth/register
 * Create a new donor or hospital staff account
 */
router.post('/register', validate('register'), async (req, res, next) => {
  try {
    const user = await authService.register(req.body);
    res.status(201).json({
      message: 'Account created successfully',
      user
    });
  } catch (err) {
    if (err.status) {
      return res.status(err.status).json({ error: err.code, message: err.message });
    }
    next(err);
  }
});

/**
 * POST /auth/login
 * Authenticate user and return access + refresh tokens
 */
router.post('/login', loginLimiter, validate('login'), async (req, res, next) => {
  try {
    const { email, password } = req.body;
    const result = await authService.login(email, password);
    res.json(result);
  } catch (err) {
    if (err.status) {
      return res.status(err.status).json({ error: err.code, message: err.message });
    }
    next(err);
  }
});

/**
 * POST /auth/refresh
 * Issue new access token from valid refresh token
 */
router.post('/refresh', validate('refresh'), async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    const result = await authService.refresh(refreshToken);
    res.json(result);
  } catch (err) {
    if (err.status) {
      return res.status(err.status).json({ error: err.code, message: err.message });
    }
    next(err);
  }
});

/**
 * POST /auth/logout
 * Revoke refresh token — requires valid access token
 */
router.post('/logout', authenticate, async (req, res, next) => {
  try {
    await authService.logout(req.user.user_id);
    res.json({ message: 'Logged out successfully' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;