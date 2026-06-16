// Factory function — pass one or more allowed roles
// Example: requireRole('admin') or requireRole('admin', 'donor')
const requireRole = (...roles) => (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({
      error: 'UNAUTHORIZED',
      message: 'Authentication required'
    });
  }

  if (!roles.includes(req.user.role)) {
    return res.status(403).json({
      error: 'FORBIDDEN',
      message: `Access denied. Required role: ${roles.join(' or ')}`
    });
  }

  next();
};

module.exports = requireRole;