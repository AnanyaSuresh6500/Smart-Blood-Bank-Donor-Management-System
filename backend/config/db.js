const { Pool } = require('pg');
require('dotenv').config();

// Pool creates a reusable set of database connections
// instead of opening a new connection for every request
const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// Fires every time a new connection is made to ShaktiDB
pool.on('connect', () => console.log('Connected to ShaktiDB'));

// Fires if the database connection unexpectedly drops
pool.on('error', (err) => console.error('ShaktiDB error:', err));

// Temporary connection test — confirms credentials work
// We will remove this after verifying the connection
pool.query('SELECT current_database(), current_user')
  .then(res => console.log('ShaktiDB connected:', res.rows[0]))
  .catch(err => console.error('Connection failed:', err.message));

module.exports = pool;