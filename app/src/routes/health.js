// app/src/routes/health.js
// ─────────────────────────────────────────────────────────────
// Health Check Endpoints
// Used by Docker, Nginx, load balancers, and monitoring tools
// ─────────────────────────────────────────────────────────────

const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');

const router = express.Router();

let redisClient;

// Lazy Redis connection
const getRedis = async () => {
  if (!redisClient) {
    redisClient = redis.createClient({ url: process.env.REDIS_URL });
    await redisClient.connect();
  }
  return redisClient;
};

// ── GET /health — Simple liveness probe ──────────────────────
router.get('/', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// ── GET /health/ready — Full readiness probe ─────────────────
router.get('/ready', async (req, res) => {
  const checks = {};
  let allHealthy = true;

  // Check PostgreSQL
  try {
    const pool = new Pool({ connectionString: process.env.DATABASE_URL });
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    await pool.end();
    checks.postgres = { status: 'healthy' };
  } catch (err) {
    checks.postgres = { status: 'unhealthy', error: err.message };
    allHealthy = false;
  }

  // Check Redis
  try {
    const client = await getRedis();
    await client.ping();
    checks.redis = { status: 'healthy' };
  } catch (err) {
    checks.redis = { status: 'unhealthy', error: err.message };
    allHealthy = false;
  }

  // System info
  const memUsage = process.memoryUsage();
  checks.memory = {
    heapUsed: `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`,
    heapTotal: `${Math.round(memUsage.heapTotal / 1024 / 1024)}MB`,
    rss: `${Math.round(memUsage.rss / 1024 / 1024)}MB`,
  };

  const statusCode = allHealthy ? 200 : 503;
  res.status(statusCode).json({
    status: allHealthy ? 'ready' : 'degraded',
    timestamp: new Date().toISOString(),
    version: process.env.APP_VERSION || '1.0.0',
    checks,
  });
});

module.exports = router;
