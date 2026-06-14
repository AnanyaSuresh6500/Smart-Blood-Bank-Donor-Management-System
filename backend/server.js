require('dotenv').config(); // Loads .env file first before anything else
const express = require('express');
const cors    = require('cors');
const helmet  = require('helmet');

// Importing db.js runs the connection pool setup immediately
require('./config/db');

const app = express();

// Adds security headers to every response automatically
app.use(helmet());

// Only allows requests from the React frontend URL
app.use(cors({ origin: process.env.CLIENT_URL }));

// Allows the server to read JSON request bodies
app.use(express.json());

// Health check route — used to verify the server is running
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'Smart Blood Bank API' });
});

// Catch-all for any route that doesn't exist
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Global error handler — catches any unhandled errors in routes
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`🚀 Backend running on port ${PORT}`));