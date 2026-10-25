const jwt = require('jsonwebtoken');
const pool = require('./db');

const SECRET = process.env.DRIVER_JWT_SECRET || 'change-me-in-env';

function sign(driver, sessionId) {
  return jwt.sign({ driverId: driver.driver_id, sid: sessionId }, SECRET, { expiresIn: '7d' });
}

async function requireDriver(req, res, next) {
  try {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'Not authenticated' });

    const payload = jwt.verify(token, SECRET);
    const { rows } = await pool.query(
      `SELECT d.driver_id, d.is_active, s.revoked
         FROM drivers d JOIN driver_sessions s ON s.driver_id = d.driver_id
        WHERE d.driver_id = $1 AND s.session_id = $2`,
      [payload.driverId, payload.sid]
    );
    if (!rows.length || rows[0].revoked)
      return res.status(401).json({ error: 'Session expired' });
    if (!rows[0].is_active)
      return res.status(403).json({ error: 'Account disabled. Contact admin.' });

    pool.query('UPDATE driver_sessions SET last_seen = NOW() WHERE session_id = $1', [payload.sid]);
    req.driverId = payload.driverId;
    req.sessionId = payload.sid;
    next();
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
}

module.exports = { sign, requireDriver };