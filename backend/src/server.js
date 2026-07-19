const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Database connection pool
const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'grades_db',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || 'password',
});

// Wait for the database to be ready
async function waitForDatabase(retries = 10, delay = 3000) {
  for (let i = 1; i <= retries; i++) {
    try {
      await pool.query('SELECT 1');
      console.log('Database connection established');
      return;
    } catch (err) {
      console.log(`Database not ready (attempt ${i}/${retries}) — retrying in ${delay / 1000}s`);
      await new Promise(r => setTimeout(r, delay));
    }
  }
  console.error('Could not connect to the database after multiple attempts');
  process.exit(1);
}

// ── Health check ────────────────────────────────────────────
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'OK', database: 'connected', timestamp: new Date() });
  } catch (err) {
    res.status(503).json({ status: 'ERROR', database: 'disconnected' });
  }
});

// ── Students ─────────────────────────────────────────────────

// GET /api/students — list all students
app.get('/api/students', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM students ORDER BY name ASC'
    );
    res.json(result.rows);
  } catch (err) {
    console.error('GET /api/students error:', err.message);
    res.status(500).json({ error: 'Failed to retrieve students' });
  }
});

// POST /api/students — create a new student
app.post('/api/students', async (req, res) => {
  const { name, email } = req.body;
  if (!name || !email) {
    return res.status(400).json({ error: 'name and email are required' });
  }
  try {
    const result = await pool.query(
      'INSERT INTO students (name, email) VALUES ($1, $2) RETURNING *',
      [name, email]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'A student with that email already exists' });
    }
    console.error('POST /api/students error:', err.message);
    res.status(500).json({ error: 'Failed to create student' });
  }
});

// ── Grades ────────────────────────────────────────────────────

// GET /api/grades — list all grades with student names
app.get('/api/grades', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        g.id,
        s.name  AS student_name,
        g.subject,
        g.score,
        g.created_at
      FROM grades g
      JOIN students s ON s.id = g.student_id
      ORDER BY g.created_at DESC
    `);
    res.json(result.rows);
  } catch (err) {
    console.error('GET /api/grades error:', err.message);
    res.status(500).json({ error: 'Failed to retrieve grades' });
  }
});

// POST /api/grades — record a new grade
app.post('/api/grades', async (req, res) => {
  const { student_id, subject, score } = req.body;
  if (!student_id || !subject || score === undefined) {
    return res.status(400).json({ error: 'student_id, subject, and score are required' });
  }
  if (score < 0 || score > 100) {
    return res.status(400).json({ error: 'score must be between 0 and 100' });
  }
  try {
    const result = await pool.query(
      'INSERT INTO grades (student_id, subject, score) VALUES ($1, $2, $3) RETURNING *',
      [student_id, subject, score]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('POST /api/grades error:', err.message);
    res.status(500).json({ error: 'Failed to record grade' });
  }
});

// ── Start server ──────────────────────────────────────────────
waitForDatabase().then(() => {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Grade Tracker API running on port ${PORT}`);
  });
});
