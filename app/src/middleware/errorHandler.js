// app/src/middleware/errorHandler.js
// ─────────────────────────────────────────────────────────────
// Global error handler — catches all next(err) calls
// ─────────────────────────────────────────────────────────────

const errorHandler = (err, req, res, next) => {
  const status = err.status || err.statusCode || 500;
  const isDev = process.env.NODE_ENV === 'development';

  console.error(`[ERROR] ${req.method} ${req.path} — ${err.message}`);
  if (isDev) console.error(err.stack);

  // Don't expose internal errors in production
  res.status(status).json({
    error: status >= 500 && !isDev ? 'Internal server error' : err.message,
    ...(isDev && { stack: err.stack }),
  });
};

module.exports = { errorHandler };
