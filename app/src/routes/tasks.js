// app/src/routes/tasks.js
// ─────────────────────────────────────────────────────────────
// Task CRUD API Routes
// All routes require JWT authentication
// GET    /api/tasks
// POST   /api/tasks
// PUT    /api/tasks/:id
// DELETE /api/tasks/:id
// ─────────────────────────────────────────────────────────────

const express = require('express');
const { Pool } = require('pg');
const { body, param, validationResult } = require('express-validator');
const { authenticate } = require('../middleware/auth');

const router = express.Router();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// All task routes require authentication
router.use(authenticate);

// ── GET /api/tasks ────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  const { status, page = 1, limit = 20 } = req.query;
  const offset = (page - 1) * limit;

  try {
    let query = 'SELECT * FROM tasks WHERE user_id = $1';
    const params = [req.user.userId];

    if (status) {
      query += ' AND status = $2 ORDER BY created_at DESC LIMIT $3 OFFSET $4';
      params.push(status, limit, offset);
    } else {
      query += ' ORDER BY created_at DESC LIMIT $2 OFFSET $3';
      params.push(limit, offset);
    }

    const result = await pool.query(query, params);
    const countResult = await pool.query(
      'SELECT COUNT(*) FROM tasks WHERE user_id = $1',
      [req.user.userId]
    );

    res.json({
      tasks: result.rows,
      pagination: {
        total: parseInt(countResult.rows[0].count),
        page: parseInt(page),
        limit: parseInt(limit),
      },
    });
  } catch (err) {
    next(err);
  }
});

// ── POST /api/tasks ───────────────────────────────────────────
router.post('/',
  [
    body('title').trim().notEmpty().isLength({ max: 255 }),
    body('description').optional().trim(),
    body('status').optional().isIn(['todo', 'in_progress', 'done']),
    body('priority').optional().isIn(['low', 'medium', 'high']),
    body('due_date').optional().isISO8601(),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

    const { title, description, status = 'todo', priority = 'medium', due_date } = req.body;

    try {
      const result = await pool.query(
        `INSERT INTO tasks (user_id, title, description, status, priority, due_date, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW()) RETURNING *`,
        [req.user.userId, title, description, status, priority, due_date || null]
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

// ── PUT /api/tasks/:id ────────────────────────────────────────
router.put('/:id',
  [
    param('id').isInt(),
    body('title').optional().trim().notEmpty().isLength({ max: 255 }),
    body('description').optional().trim(),
    body('status').optional().isIn(['todo', 'in_progress', 'done']),
    body('priority').optional().isIn(['low', 'medium', 'high']),
    body('due_date').optional().isISO8601(),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

    const { id } = req.params;
    const updates = req.body;

    try {
      // Verify ownership
      const existing = await pool.query(
        'SELECT id FROM tasks WHERE id = $1 AND user_id = $2',
        [id, req.user.userId]
      );
      if (!existing.rows.length) return res.status(404).json({ error: 'Task not found' });

      const fields = Object.keys(updates).map((k, i) => `${k} = $${i + 3}`).join(', ');
      const values = Object.values(updates);

      const result = await pool.query(
        `UPDATE tasks SET ${fields}, updated_at = NOW() WHERE id = $1 AND user_id = $2 RETURNING *`,
        [id, req.user.userId, ...values]
      );

      res.json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

// ── DELETE /api/tasks/:id ─────────────────────────────────────
router.delete('/:id',
  [param('id').isInt()],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

    try {
      const result = await pool.query(
        'DELETE FROM tasks WHERE id = $1 AND user_id = $2 RETURNING id',
        [req.params.id, req.user.userId]
      );

      if (!result.rows.length) return res.status(404).json({ error: 'Task not found' });
      res.json({ message: 'Task deleted', id: result.rows[0].id });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
