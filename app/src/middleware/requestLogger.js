// app/src/middleware/requestLogger.js
// Structured request logging middleware

const requestLogger = (req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    const log = {
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip,
      userAgent: req.get('user-agent'),
      ...(req.user && { userId: req.user.userId }),
    };
    if (res.statusCode >= 400) {
      console.error('[REQUEST]', JSON.stringify(log));
    } else if (process.env.NODE_ENV !== 'test') {
      console.log('[REQUEST]', JSON.stringify(log));
    }
  });
  next();
};

module.exports = { requestLogger };
