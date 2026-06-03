// app/src/routes/auth.js
// ─────────────────────────────────────────────────────────────
// Authentication Routes — JWT-based auth
// POST /api/auth/register
// POST /api/auth/login
// POST /api/auth/refresh
// POST /api/auth/logout
// ─────────────────────────────────────────────────────────────

const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const { body, validationResult } = require('express-validator');

const router = express.Router();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

const SALT_ROUNDS = 12;
const ACCESS_TOKEN_EXPIRY = '15m';
const REFRESH_TOKEN_EXPIRY = '7d';

// ── Token helpers ─────────────────────────────────────────────
const generateTokens = (userId, email) => {
  const payload = { userId, email };
  const accessToken = jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: ACCESS_TOKEN_EXPIRY });
  const refreshToken = jwt.sign(payload, process.env.JWT_REFRESH_SECRET, { expiresIn: REFRESH_TOKEN_EXPIRY });
  return { accessToken, refreshToken };
};

// ── POST /api/auth/register ───────────────────────────────────
router.post('/register',
  [
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
    body('name').trim().notEmpty().withMessage('Name is required'),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(422).json({ errors: errors.array() });
    }

    const { email, password, name } = req.body;

    try {
      // Check if user already exists
      const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email]);
      if (existing.rows.length > 0) {
        return res.status(409).json({ error: 'Email already registered' });
      }

      const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

      const result = await pool.query(
        'INSERT INTO users (email, password_hash, name, created_at) VALUES ($1, $2, $3, NOW()) RETURNING id, email, name',
        [email, passwordHash, name]
      );

      const user = result.rows[0];
      const tokens = generateTokens(user.id, user.email);

      res.status(201).json({
        message: 'Registration successful',
        user: { id: user.id, email: user.email, name: user.name },
        ...tokens,
      });
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/login ──────────────────────────────────────
router.post('/login',
  [
    body('email').isEmail().normalizeEmail(),
    body('password').notEmpty(),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(422).json({ errors: errors.array() });
    }

    const { email, password } = req.body;

    try {
      const result = await pool.query(
        'SELECT id, email, name, password_hash FROM users WHERE email = $1',
        [email]
      );

      const user = result.rows[0];

      // Constant-time comparison to prevent timing attacks
      const passwordMatch = user
        ? await bcrypt.compare(password, user.password_hash)
        : await bcrypt.compare(password, '$2b$12$invalidhashfortimingnormalization');

      if (!user || !passwordMatch) {
        return res.status(401).json({ error: 'Invalid credentials' });
      }

      const tokens = generateTokens(user.id, user.email);

      // Update last login
      await pool.query('UPDATE users SET last_login = NOW() WHERE id = $1', [user.id]);

      res.json({
        message: 'Login successful',
        user: { id: user.id, email: user.email, name: user.name },
        ...tokens,
      });
    } catch (err) {
      next(err);
    }
  }
);

// ── POST /api/auth/refresh ────────────────────────────────────
router.post('/refresh', async (req, res, next) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.status(401).json({ error: 'Refresh token required' });

  try {
    const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    const tokens = generateTokens(decoded.userId, decoded.email);
    res.json(tokens);
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Refresh token expired, please log in again' });
    }
    res.status(401).json({ error: 'Invalid refresh token' });
  }
});

// ── POST /api/auth/logout ─────────────────────────────────────
router.post('/logout', (req, res) => {
  // Client should discard tokens; add to blocklist if using Redis
  res.json({ message: 'Logged out successfully' });
});

module.exports = router;
