const Joi = require('joi');

// Validation schemas for each auth endpoint
const schemas = {

  // Register — donor or hospital staff
  register: Joi.object({
    email:       Joi.string().email().required(),
    password:    Joi.string().min(8).required(),
    role:        Joi.string().valid('donor', 'hospital_staff').required(),
    first_name:  Joi.string().when('role', { is: 'donor', then: Joi.required() }),
    last_name:   Joi.string().when('role', { is: 'donor', then: Joi.required() }),
    blood_group: Joi.string().valid('A+','A-','B+','B-','AB+','AB-','O+','O-')
                   .when('role', { is: 'donor', then: Joi.required() }),
    date_of_birth: Joi.date().max('now').when('role', { is: 'donor', then: Joi.required() }),
    gender:      Joi.string().valid('male','female','other')
                   .when('role', { is: 'donor', then: Joi.required() }),
    contact_phone: Joi.string().optional(),
    address:     Joi.string().optional(),
    hospital_id: Joi.number().when('role', { is: 'hospital_staff', then: Joi.required() }),
  }),

  // Login
  login: Joi.object({
    email:    Joi.string().email().required(),
    password: Joi.string().required(),
  }),

  // Refresh token
  refresh: Joi.object({
    refreshToken: Joi.string().required(),
  }),

};

// Middleware factory — pass the schema name to validate against
const validate = (schemaName) => (req, res, next) => {
  const schema = schemas[schemaName];
  if (!schema) return next();

  const { error } = schema.validate(req.body, { abortEarly: false });

  if (error) {
    return res.status(400).json({
      error: 'VALIDATION_ERROR',
      message: 'Invalid request data',
      // Return all validation errors at once, not just the first one
      details: error.details.map(d => d.message)
    });
  }

  next();
};

module.exports = validate;