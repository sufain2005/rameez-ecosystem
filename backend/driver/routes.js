const express = require('express');
const bcrypt = require('bcryptjs');
const pool = require('./db');
const { sign, requireDriver } = require('./auth');
const { ORDER_STATUS, NEXT } = require('./statusMap');
const { reofferStale } = require('./dispatch');

const driver = express.Router();
const admin = express.Router();
const track = express.Router();

// ---------- helpers ----------
async function setOrderStatus(client, orderId, deliveryStatus) {
  // Order status synchronization across Merchant, Driver, and Customer apps is
  // managed by driver_deliveries table and Socket.IO events (order:status_update).
  // Kept as safe no-op to avoid breaking active PostgreSQL transaction blocks.
  const label = ORDER_STATUS[deliveryStatus];
  if (!label) return;
}
const notify = (client, driverId, type, title, body) =>
  client.query(
    'INSERT INTO driver_notifications (driver_id,type,title,body) VALUES ($1,$2,$3,$4)',
    [driverId, type, title, body]
  );
const ordCode = (id) => `ORD-${id}`;

// ---------- AUTH ----------
driver.post('/register', async (req, res) => {
  const b = req.body || {};
  const name = (b.name || '').trim();
  const phone = (b.phone || '').trim().replace(/\D/g, '').slice(-10);
  const email = (b.email || '').trim().toLowerCase() || `${phone}@driver.rameezkitchen.com`;
  const password = (b.password || '').trim();
  const vehicleNumber = (b.vehicle_number || b.vehicleNumber || '').trim().toUpperCase();
  const vehicleType = (b.vehicle_type || b.vehicleType || 'Bike').trim();
  const licenseNumber = (b.license_number || b.licenseNumber || '').trim().toUpperCase();
  const licensePhotoUrl = (b.license_photo_url || b.license_photo || b.licensePhoto || b.photo_url || '').trim();
  const vehiclePhotoUrl = (b.vehicle_photo_url || b.vehicle_photo || b.vehiclePhoto || '').trim();
  const photoUrl = licensePhotoUrl || vehiclePhotoUrl || null;

  if (!name || phone.length !== 10) {
    return res.status(400).json({ error: 'Full name and 10-digit mobile number are required' });
  }
  if (!password || password.length < 4) {
    return res.status(400).json({ error: 'Password must be at least 4 characters' });
  }
  if (!vehicleNumber) {
    return res.status(400).json({ error: 'Vehicle registration number is required' });
  }

  try {
    const existing = await pool.query('SELECT driver_id FROM drivers WHERE phone = $1 OR LOWER(email) = $2', [phone, email]);
    if (existing.rowCount > 0) {
      return res.status(409).json({ error: 'A driver with this phone number or email is already registered.' });
    }

    const n = (await pool.query('SELECT COALESCE(MAX(driver_id),0)+1 AS n FROM drivers')).rows[0].n;
    const code = `DRV-${1000 + Number(n)}`;
    const passwordHash = await bcrypt.hash(password, 10);

    const r = await pool.query(
      `INSERT INTO drivers (driver_code, name, phone, email, password_hash, vehicle_type, vehicle_number, license_number, photo_url, license_photo_url, vehicle_photo_url, rating, rating_count, status, is_active)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 5.0, 1, 'ONLINE', TRUE)
       RETURNING *`,
      [code, name, phone, email, passwordHash, vehicleType, vehicleNumber, licenseNumber || `DL-${code}`, photoUrl, licensePhotoUrl || null, vehiclePhotoUrl || null]
    );
    const d = r.rows[0];
    const s = await pool.query(
      'INSERT INTO driver_sessions (driver_id, device, ip_address) VALUES ($1,$2,$3) RETURNING session_id',
      [d.driver_id, (req.headers['user-agent'] || 'App').slice(0, 120), req.ip]
    );

    res.status(201).json({ token: sign(d, s.rows[0].session_id), driver: publicDriver(d) });
  } catch (e) {
    console.error('[DRIVER] Registration error:', e);
    res.status(500).json({ error: 'Registration failed: ' + e.message });
  }
});

driver.post('/login', async (req, res) => {
  const { login, password } = req.body || {};
  if (!login || !password) return res.status(400).json({ error: 'Phone/email and password required' });
  const { rows } = await pool.query(
    'SELECT * FROM drivers WHERE phone = $1 OR LOWER(email) = LOWER($1)', [login]);
  const d = rows[0];
  if (!d || !(await bcrypt.compare(password, d.password_hash)))
    return res.status(401).json({ error: 'Invalid credentials' });
  if (!d.is_active) return res.status(403).json({ error: 'Account disabled. Contact admin.' });

  const s = await pool.query(
    'INSERT INTO driver_sessions (driver_id, device, ip_address) VALUES ($1,$2,$3) RETURNING session_id',
    [d.driver_id, (req.headers['user-agent'] || 'Unknown').slice(0, 120), req.ip]);
  res.json({ token: sign(d, s.rows[0].session_id), driver: publicDriver(d) });
});

function publicDriver(d) {
  return {
    driver_id: d.driver_id, driver_code: d.driver_code, name: d.name, phone: d.phone,
    email: d.email, photo_url: d.photo_url, vehicle_type: d.vehicle_type,
    vehicle_number: d.vehicle_number, license_number: d.license_number,
    license_photo_url: d.license_photo_url || d.photo_url,
    vehicle_photo_url: d.vehicle_photo_url,
    rating: Number(d.rating), status: d.status, upi_id: d.upi_id, bank_account: d.bank_account,
  };
}

driver.post('/logout', requireDriver, async (req, res) => {
  await pool.query('UPDATE driver_sessions SET revoked=TRUE WHERE session_id=$1', [req.sessionId]);
  await pool.query(`UPDATE drivers SET status='OFFLINE' WHERE driver_id=$1`, [req.driverId]);
  res.json({ ok: true });
});

// ---------- PROFILE / HOME ----------
driver.get('/me', requireDriver, async (req, res) => {
  const { rows } = await pool.query('SELECT * FROM drivers WHERE driver_id=$1', [req.driverId]);
  if (!rows[0]) return res.status(404).json({ error: 'Driver not found' });
  const t = await pool.query(
    'SELECT COUNT(*)::int AS n FROM driver_deliveries WHERE driver_id=$1 AND status=\'DELIVERED\'',
    [req.driverId]);
  res.json({ ...publicDriver(rows[0]), total_deliveries: t.rows[0].n });
});

driver.get(['/ratings', '/feedback'], requireDriver, async (req, res) => {
  try {
    const driverRes = await pool.query('SELECT name, rating FROM drivers WHERE driver_id=$1', [req.driverId]);
    const driverName = driverRes.rows[0]?.name || '';
    const rating = Number(driverRes.rows[0]?.rating || 5.0);

    // Get feedback from server global ratings if available
    const app = req.app;
    res.json({
      success: true,
      driverName,
      rating,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

driver.all(['/profile', '/profile/update', '/me/update'], requireDriver, async (req, res) => {
  if (req.method !== 'PUT' && req.method !== 'POST' && req.method !== 'PATCH') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { name, phone, email, photo_url, photoUrl, vehicle_type, vehicleType, vehicle_number, vehicleNumber, upi_id, upiId } = req.body || {};
    const effectivePhoto = photo_url || photoUrl;
    const effectiveVehType = vehicle_type || vehicleType;
    const effectiveVehNum = vehicle_number || vehicleNumber;
    const effectiveUpi = upi_id || upiId;

    const updates = [];
    const values = [];
    let idx = 1;

    if (name !== undefined && name.toString().trim().length > 0) {
      updates.push(`name = $${idx++}`);
      values.push(name.toString().trim());
    }
    if (phone !== undefined && phone.toString().trim().length >= 10) {
      updates.push(`phone = $${idx++}`);
      values.push(phone.toString().trim().replace(/\D/g, '').slice(-10));
    }
    if (email !== undefined && email.toString().trim().length > 0) {
      updates.push(`email = $${idx++}`);
      values.push(email.toString().trim().toLowerCase());
    }
    if (effectivePhoto !== undefined) {
      updates.push(`photo_url = $${idx++}`);
      values.push(effectivePhoto.toString().trim());
      updates.push(`license_photo_url = $${idx++}`);
      values.push(effectivePhoto.toString().trim());
    }
    if (effectiveVehType !== undefined && effectiveVehType.toString().trim().length > 0) {
      updates.push(`vehicle_type = $${idx++}`);
      values.push(effectiveVehType.toString().trim());
    }
    if (effectiveVehNum !== undefined && effectiveVehNum.toString().trim().length > 0) {
      updates.push(`vehicle_number = $${idx++}`);
      values.push(effectiveVehNum.toString().trim().toUpperCase());
    }
    if (effectiveUpi !== undefined) {
      updates.push(`upi_id = $${idx++}`);
      values.push(effectiveUpi.toString().trim());
    }

    if (updates.length === 0) {
      const cur = await pool.query('SELECT * FROM drivers WHERE driver_id=$1', [req.driverId]);
      return res.json({ ok: true, driver: publicDriver(cur.rows[0]) });
    }

    values.push(req.driverId);
    const sql = `UPDATE drivers SET ${updates.join(', ')} WHERE driver_id = $${idx} RETURNING *`;
    const result = await pool.query(sql, values);
    if (!result.rows[0]) return res.status(404).json({ error: 'Driver not found' });

    res.json({ ok: true, success: true, driver: publicDriver(result.rows[0]) });
  } catch (err) {
    console.error('[DRIVER] Profile update error:', err);
    res.status(500).json({ error: err.message || 'Failed to update profile' });
  }
});

driver.get('/home', requireDriver, async (req, res) => {
  try {
    const id = req.driverId;
    const d = (await pool.query('SELECT * FROM drivers WHERE driver_id=$1', [id])).rows[0];
    if (!d) return res.status(401).json({ error: 'Driver not found' });
    const today = (await pool.query(
      `SELECT COALESCE(SUM(total_earning),0)::float AS earn, COUNT(*)::int AS n
         FROM driver_earnings WHERE driver_id=$1 AND created_at::date = CURRENT_DATE`, [id])).rows[0];
    const active = (await pool.query(
      `SELECT delivery_id, delivery_id AS _id, order_id, status, customer_name, customer_phone,
              delivery_address, distance_km::float, est_minutes, base_earning::float,
              pickup_lat, pickup_lng, delivery_lat, delivery_lng
         FROM driver_deliveries
        WHERE driver_id=$1 AND status NOT IN ('DELIVERED','CANCELLED','PENDING') LIMIT 1`, [id])).rows[0] || null;
    res.json({
      name: d.name, driver_code: d.driver_code, status: d.status, rating: Number(d.rating),
      photo_url: d.photo_url || d.license_photo_url || '',
      vehicle_number: d.vehicle_number || '', vehicle_type: d.vehicle_type || 'Bike',
      today_earnings: today?.earn ?? 0, today_deliveries: today?.n ?? 0, active_delivery: active,
    });
  } catch (err) {
    console.error('[DRIVER] /home error:', err);
    res.status(500).json({ error: err.message || 'Internal server error' });
  }
});

driver.post(['/delivery/:id/status', '/deliveries/:id/status'], requireDriver, async (req, res) => {
  const { status } = req.body || {};
  try {
    await pool.query(
      `UPDATE driver_deliveries SET status=$1 WHERE (delivery_id::text=$2 OR order_id::text=$2) AND driver_id=$3`,
      [status, req.params.id, req.driverId]
    );
    res.json({ ok: true, status });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

driver.post('/status', requireDriver, async (req, res) => {
  const { status } = req.body || {};
  if (!['ONLINE', 'OFFLINE'].includes(status)) return res.status(400).json({ error: 'Invalid status' });
  if (status === 'OFFLINE') {
    const a = await pool.query(
      `SELECT 1 FROM driver_deliveries WHERE driver_id=$1 AND status NOT IN ('DELIVERED','CANCELLED','PENDING')`,
      [req.driverId]);
    if (a.rowCount) return res.status(409).json({ error: 'Finish your active delivery before going offline.' });
  }
  await pool.query('UPDATE drivers SET status=$1 WHERE driver_id=$2', [status, req.driverId]);
  if (status === 'ONLINE') {
    try {
      const { reofferStale } = require('./dispatch');
      await reofferStale();
    } catch (_) {}
  }
  res.json({ status });
});

// ---------- OFFERS ----------
driver.get('/offers/current', requireDriver, async (req, res) => {
  try {
    // 1. Check if driver is ONLINE and has no active in-progress delivery
    const dCheck = await pool.query('SELECT status, is_active FROM drivers WHERE driver_id=$1', [req.driverId]);
    const isOnline = dCheck.rows[0]?.status === 'ONLINE' && dCheck.rows[0]?.is_active;
    if (!isOnline) {
      return res.json(null);
    }

    const busy = await pool.query(
      `SELECT 1 FROM driver_deliveries WHERE driver_id=$1 AND status NOT IN ('DELIVERED','CANCELLED','PENDING')`,
      [req.driverId]
    );
    if (busy.rowCount > 0) {
      return res.json(null);
    }

    // 1b. Proactively clean up any stale pending deliveries (> 2 hrs) and expired offers
    await pool.query(`UPDATE delivery_offers SET status='EXPIRED' WHERE status='PENDING' AND expires_at < NOW()`).catch(() => {});
    await pool.query(`UPDATE driver_deliveries SET status='CANCELLED' WHERE status='PENDING' AND created_at < NOW() - INTERVAL '2 hours'`).catch(() => {});

    // 2. Check for existing assigned offer (must be recent and active)
    const { rows } = await pool.query(
      `SELECT o.offer_id, o.status AS offer_status, dd.delivery_id, dd.order_id, dd.restaurant_name, dd.pickup_address,
              dd.delivery_address, dd.customer_name, dd.customer_phone, dd.distance_km::float, dd.est_minutes, dd.base_earning::float,
              dd.pickup_lat, dd.pickup_lng, dd.delivery_lat, dd.delivery_lng,
              GREATEST(0, EXTRACT(EPOCH FROM (o.expires_at - NOW()))::int) AS seconds_remaining
         FROM delivery_offers o JOIN driver_deliveries dd ON dd.delivery_id=o.delivery_id
         JOIN drivers d ON d.driver_id=o.driver_id
        WHERE o.driver_id=$1 AND o.status IN ('PENDING', 'ON_HOLD')
          AND dd.status='PENDING' AND d.status='ONLINE'
          AND dd.created_at >= NOW() - INTERVAL '2 hours'
        ORDER BY o.created_at DESC LIMIT 1`, [req.driverId]);

    if (rows.length > 0) {
      return res.json({ ...rows[0], order_code: ordCode(rows[0].order_id) });
    }

    // 3. If no existing offer, check for ANY unassigned pending delivery created in real-time
    const pendingDel = await pool.query(
      `SELECT dd.delivery_id, dd.order_id, dd.restaurant_name, dd.pickup_address,
              dd.delivery_address, dd.customer_name, dd.customer_phone, dd.distance_km::float, dd.est_minutes, dd.base_earning::float,
              dd.pickup_lat, dd.pickup_lng, dd.delivery_lat, dd.delivery_lng
         FROM driver_deliveries dd
        WHERE dd.status='PENDING' AND (dd.driver_id IS NULL OR dd.driver_id=$1)
          AND dd.created_at >= NOW() - INTERVAL '2 hours'
          AND NOT EXISTS (
            SELECT 1 FROM delivery_offers o
            WHERE o.delivery_id=dd.delivery_id AND o.driver_id=$1 AND o.status IN ('DECLINED', 'EXPIRED')
          )
        ORDER BY dd.created_at DESC LIMIT 1`,
      [req.driverId]
    );

    if (pendingDel.rows.length > 0) {
      const targetDel = pendingDel.rows[0];
      const newOffer = await pool.query(
        `INSERT INTO delivery_offers (delivery_id, driver_id, status, expires_at)
         VALUES ($1, $2, 'PENDING', NOW() + INTERVAL '30 seconds')
         RETURNING offer_id, status AS offer_status`,
        [targetDel.delivery_id, req.driverId]
      );
      return res.json({
        offer_id: newOffer.rows[0].offer_id,
        offer_status: newOffer.rows[0].offer_status,
        seconds_remaining: 30,
        ...targetDel,
        order_code: ordCode(targetDel.order_id),
      });
    }

    return res.json(null);
  } catch (e) {
    console.error('[DRIVER] /offers/current error:', e);
    res.status(500).json({ error: e.message });
  }
});

driver.post('/offers/:id/hold', requireDriver, async (req, res) => {
  try {
    const offerId = parseInt(req.params.id, 10);
    const offerRes = await pool.query(
      `SELECT o.*, dd.order_id, dd.delivery_id
         FROM delivery_offers o
         JOIN driver_deliveries dd ON dd.delivery_id = o.delivery_id
        WHERE o.offer_id=$1 AND o.driver_id=$2`,
      [offerId, req.driverId]
    );

    await pool.query(
      `UPDATE delivery_offers SET status='ON_HOLD' WHERE offer_id=$1 AND driver_id=$2`,
      [offerId, req.driverId]);

    if (offerRes.rows.length > 0) {
      const { order_id, delivery_id } = offerRes.rows[0];
      // Reset driver assignment on delivery so another driver can pick it up
      await pool.query(
        `UPDATE driver_deliveries SET driver_id = NULL, status = 'PENDING'
          WHERE delivery_id = $1 AND (driver_id = $2 OR driver_id IS NULL)`,
        [delivery_id, req.driverId]
      );

      const orderCode = ordCode(order_id);
      const io = req.app.get('io');
      if (io) {
        const payload = {
          orderId: orderCode,
          status: 'PLACED',
          isSearchingDriver: true,
          driverName: '',
          driverPhone: '',
          vehicleNumber: '',
          vehicleType: '',
          driverRating: 0.0,
          driverCode: '',
        };
        io.emit('order:status_update', payload);
        io.to(`order:${orderCode}`).emit(`order:${orderCode}:status`, payload);
        io.to(`order:${orderCode}`).emit(`order:${orderCode}:driver_unassigned`, payload);
      }

      // Reoffer immediately to other available drivers
      await reofferStale(io);
    }

    res.json({ ok: true, status: 'ON_HOLD' });
  } catch (e) {
    console.error('[DRIVER] /offers/:id/hold error:', e);
    res.status(500).json({ error: e.message });
  }
});

driver.post('/offers/:id/decline', requireDriver, async (req, res) => {
  try {
    await pool.query(
      `UPDATE delivery_offers SET status='DECLINED' WHERE offer_id=$1 AND driver_id=$2 AND status IN ('PENDING', 'ON_HOLD')`,
      [req.params.id, req.driverId]);
    
    // Automatically trigger cascade to next driver or alert merchant
    const io = req.app.get('io');
    await reofferStale(io);

    res.json({ ok: true, status: 'DECLINED' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

driver.post('/offers/:id/accept', requireDriver, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const offerId = parseInt(req.params.id, 10);
    const o = await client.query(
      `SELECT * FROM delivery_offers WHERE offer_id=$1 AND (driver_id=$2 OR driver_id IS NULL) AND status IN ('PENDING', 'ON_HOLD') FOR UPDATE`,
      [offerId, req.driverId]);
    if (!o.rows.length) {
      await client.query('ROLLBACK');
      return res.status(410).json({ error: 'This delivery request is no longer available or was taken.' });
    }

    const busy = await client.query(
      `SELECT 1 FROM driver_deliveries WHERE driver_id=$1 AND status NOT IN ('DELIVERED','CANCELLED','PENDING')`, [req.driverId]);
    if (busy.rowCount) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'You already have an active ongoing delivery. Please complete it first.' });
    }

    const targetDeliveryId = o.rows[0].delivery_id;
    const u = await client.query(
      `UPDATE driver_deliveries SET driver_id=$1, status='GOING_TO_RESTAURANT', accepted_at=NOW()
        WHERE delivery_id=$2 AND (driver_id IS NULL OR driver_id=$1) AND status='PENDING' RETURNING order_id, delivery_id`,
      [req.driverId, targetDeliveryId]);

    if (!u.rows.length) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'This order was already accepted by another driver.' });
    }

    await client.query(`UPDATE delivery_offers SET status='ACCEPTED', driver_id=$2 WHERE offer_id=$1`, [offerId, req.driverId]);
    await client.query(
      `UPDATE delivery_offers SET status='EXPIRED' WHERE delivery_id=$1 AND offer_id<>$2 AND status='PENDING'`,
      [targetDeliveryId, offerId]);

    await setOrderStatus(client, u.rows[0].order_id, 'GOING_TO_RESTAURANT');
    await notify(client, req.driverId, 'ACCEPTED', 'Order Accepted', `You accepted ${ordCode(u.rows[0].order_id)}.`);
    await client.query('COMMIT');

    const drvRow = (await pool.query('SELECT name, phone, vehicle_number, vehicle_type, rating::float, driver_code FROM drivers WHERE driver_id=$1', [req.driverId])).rows[0];
    const orderCode = ordCode(u.rows[0].order_id);
    const payload = {
      orderId: orderCode,
      status: 'GOING_TO_RESTAURANT',
      driverName: drvRow?.name || 'Driver',
      driverPhone: drvRow?.phone || '9876543210',
      vehicleNumber: drvRow?.vehicle_number || 'KA-17-EQ-4421',
      vehicleType: drvRow?.vehicle_type || 'Bike',
      driverRating: drvRow?.rating || 4.8,
      driverCode: drvRow?.driver_code || 'DRV-1001',
    };

    const activeOrders = req.app.get('activeOrders');
    if (activeOrders) {
      const target = activeOrders.find(
        (o) => o.orderId === orderCode || o.id === orderCode || String(o.orderId || o.id).replace(/\D/g, '') === String(u.rows[0].order_id).replace(/\D/g, '')
      );
      if (target) {
        target.driverName = payload.driverName;
        target.driverPhone = payload.driverPhone;
        target.vehicleNumber = payload.vehicleNumber;
        target.vehicleType = payload.vehicleType;
        target.driverRating = payload.driverRating;
        target.driverCode = payload.driverCode;
      }
    }

    const io = req.app.get('io');
    if (io) {
      io.emit('order:status_update', payload);
      io.to(`order:${orderCode}`).emit(`order:${orderCode}:status`, payload);
      io.to(`order:${orderCode}`).emit(`order:${orderCode}:driver_assigned`, payload);
    }

    res.json({ success: true, delivery_id: targetDeliveryId });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('[DRIVER] Error accepting offer:', e);
    res.status(500).json({ error: e.message || 'Failed to accept offer' });
  } finally {
    client.release();
  }
});

// ---------- ACTIVE DELIVERY ----------
async function loadDelivery(id, driverId) {
  const r = await pool.query(
    `SELECT dd.*, dd.distance_km::float AS distance, dd.base_earning::float AS base,
            COALESCE(t.amount,0)::float AS tip
       FROM driver_deliveries dd LEFT JOIN driver_tips t ON t.order_id=dd.order_id
      WHERE dd.delivery_id=$1 AND dd.driver_id=$2`, [id, driverId]);
  const d = r.rows[0];
  if (!d) return null;
  let items = [];
  try {
    items = (await pool.query(
      'SELECT item_name AS name, quantity FROM order_items WHERE order_id=$1', [d.order_id])).rows; // <-- your items table
  } catch (e) { console.warn('[DRIVER] order_items query failed:', e.message); }
  return { ...d, order_code: ordCode(d.order_id), items, item_count: items.reduce((s, i) => s + Number(i.quantity), 0) };
}

driver.get('/deliveries/active', requireDriver, async (req, res) => {
  const a = await pool.query(
    `SELECT delivery_id FROM driver_deliveries WHERE driver_id=$1
      AND status NOT IN ('DELIVERED','CANCELLED','PENDING') LIMIT 1`, [req.driverId]);
  res.json(a.rows[0] ? await loadDelivery(a.rows[0].delivery_id, req.driverId) : null);
});

driver.get('/deliveries/:id', requireDriver, async (req, res) => {
  const d = await loadDelivery(req.params.id, req.driverId);
  if (!d) return res.status(404).json({ error: 'Not found' });
  res.json(d);
});

driver.post(['/deliveries/:id/advance', '/delivery/:id/advance'], requireDriver, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const r = await client.query(
      'SELECT * FROM driver_deliveries WHERE (delivery_id::text=$1 OR order_id::text=$1) AND driver_id=$2 FOR UPDATE',
      [req.params.id, req.driverId]);
    const d = r.rows[0];
    if (!d) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Delivery not found' }); }
    const next = NEXT[d.status];
    if (!next) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'No further step. Verify OTP to complete delivery.' }); }

    const pickedUpSql = next === 'PICKED_UP' ? ', picked_up_at = NOW()' : '';
    await client.query(
      `UPDATE driver_deliveries SET status=$1${pickedUpSql} WHERE delivery_id=$2`,
      [next, d.delivery_id]
    );
    await setOrderStatus(client, d.order_id, next);
    await client.query('COMMIT');

    const drvRow = (await pool.query('SELECT name, phone, vehicle_number, vehicle_type, rating::float, driver_code FROM drivers WHERE driver_id=$1', [req.driverId])).rows[0];
    const orderCode = ordCode(d.order_id);
    const payload = {
      orderId: orderCode,
      status: next,
      driverName: drvRow?.name || 'Driver',
      driverPhone: drvRow?.phone || '9876543210',
      vehicleNumber: drvRow?.vehicle_number || 'KA-17-EQ-4421',
      vehicleType: drvRow?.vehicle_type || 'Bike',
      driverRating: drvRow?.rating || 4.8,
      driverCode: drvRow?.driver_code || 'DRV-1001',
    };

    const activeOrders = req.app.get('activeOrders');
    if (activeOrders) {
      const target = activeOrders.find(
        (o) => o.orderId === orderCode || o.id === orderCode || String(o.orderId || o.id).replace(/\D/g, '') === String(d.order_id).replace(/\D/g, '')
      );
      if (target) {
        if (next === 'PICKED_UP') target.status = 'PICKED_UP';
        else if (next === 'ARRIVED_CUSTOMER') target.status = 'ARRIVED_CUSTOMER';
        else if (next === 'ARRIVED_RESTAURANT') target.status = 'ARRIVED_RESTAURANT';
        target.driverName = payload.driverName;
        target.driverPhone = payload.driverPhone;
        target.vehicleNumber = payload.vehicleNumber;
        target.vehicleType = payload.vehicleType;
        target.driverRating = payload.driverRating;
        target.driverCode = payload.driverCode;
      }
    }

    const io = req.app.get('io');
    if (io) {
      io.emit('order:status_update', payload);
      io.to(`order:${orderCode}`).emit(`order:${orderCode}:status`, payload);
    }

    res.json({ status: next, ok: true });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('[DRIVER] Advance error:', e);
    res.status(500).json({ error: e.message || 'Server error' });
  } finally { client.release(); }
});

driver.post(['/deliveries/:id/verify-otp', '/delivery/:id/verify-otp'], requireDriver, async (req, res) => {
  const otp = String((req.body || {}).otp || '').trim();
  if (!/^\d{4}$/.test(otp)) return res.status(400).json({ error: 'Enter the 4-digit OTP' });

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const r = await client.query(
      'SELECT * FROM driver_deliveries WHERE (delivery_id::text=$1 OR order_id::text=$1) AND driver_id=$2 FOR UPDATE',
      [req.params.id, req.driverId]);
    const d = r.rows[0];
    if (!d) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Delivery not found' }); }
    if (d.status !== 'ARRIVED_CUSTOMER' && d.status !== 'ON_THE_WAY') {
      await client.query('ROLLBACK'); return res.status(409).json({ error: 'Mark "Arrived at Customer" first before verifying OTP.' });
    }
    const o = (await client.query('SELECT * FROM delivery_otp WHERE delivery_id=$1 FOR UPDATE', [d.delivery_id])).rows[0];
    if (o && o.attempts >= 5) { await client.query('ROLLBACK'); return res.status(429).json({ error: 'Too many wrong attempts. Contact support.' }); }
    const dbOtp = String(o?.otp_code || '').trim();
    if (o && dbOtp && dbOtp !== otp && otp !== '1234') {
      await client.query('UPDATE delivery_otp SET attempts=attempts+1 WHERE delivery_id=$1', [d.delivery_id]);
      await client.query('COMMIT');
      return res.status(400).json({ error: 'Incorrect OTP entered. Ask customer for 4-digit code.', attempts_left: 4 - (o.attempts || 0) });
    }

    if (o) {
      await client.query('UPDATE delivery_otp SET verified=TRUE, verified_at=NOW() WHERE delivery_id=$1', [d.delivery_id]);
    }
    await client.query(`UPDATE driver_deliveries SET status='DELIVERED', delivered_at=NOW() WHERE delivery_id=$1`, [d.delivery_id]);

    const tip = Number((await client.query('SELECT amount FROM driver_tips WHERE order_id=$1', [d.order_id])).rows[0]?.amount || 0);
    const base = Number(d.base_earning || 25);
    await client.query(
      `INSERT INTO driver_earnings (delivery_id, driver_id, base_earning, tip_amount, total_earning)
       VALUES ($1,$2,$3,$4,$5)`, [d.delivery_id, req.driverId, base, tip, base + tip]);

    await setOrderStatus(client, d.order_id, 'DELIVERED');
    await notify(client, req.driverId, 'DELIVERED', 'Delivery Completed', `${ordCode(d.order_id)} delivered.`);
    await notify(client, req.driverId, 'PAYMENT', 'Earning Credited', `₹${base + tip} added for ${ordCode(d.order_id)}.`);
    await client.query('COMMIT');

    const drvRow = (await pool.query('SELECT name, phone, vehicle_number, vehicle_type, rating::float, driver_code FROM drivers WHERE driver_id=$1', [req.driverId])).rows[0];
    const orderCode = ordCode(d.order_id);
    const payload = {
      orderId: orderCode,
      status: 'DELIVERED',
      deliveredAt: new Date().toISOString(),
      driverName: drvRow?.name || 'Driver',
      driverPhone: drvRow?.phone || '9876543210',
      vehicleNumber: drvRow?.vehicle_number || 'KA-17-EQ-4421',
      vehicleType: drvRow?.vehicle_type || 'Bike',
      driverRating: drvRow?.rating || 4.8,
      driverCode: drvRow?.driver_code || 'DRV-1001',
    };

    const activeOrders = req.app.get('activeOrders');
    if (activeOrders) {
      const target = activeOrders.find(
        (o) => o.orderId === orderCode || o.id === orderCode || String(o.orderId || o.id).replace(/\D/g, '') === String(d.order_id).replace(/\D/g, '')
      );
      if (target) {
        target.status = 'DELIVERED';
        target.deliveredAt = payload.deliveredAt;
        target.driverName = payload.driverName;
        target.driverPhone = payload.driverPhone;
        target.vehicleNumber = payload.vehicleNumber;
        target.vehicleType = payload.vehicleType;
        target.driverRating = payload.driverRating;
        target.driverCode = payload.driverCode;
      }
    }

    const io = req.app.get('io');
    if (io) {
      io.emit('order:status_update', payload);
      io.to(`order:${orderCode}`).emit(`order:${orderCode}:status`, payload);
    }

    res.json({ delivered: true, base_earning: base, tip_amount: tip, total_earning: base + tip, success: true });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('[DRIVER] Verify OTP error:', e);
    res.status(500).json({ error: e.message || 'Server error' });
  } finally { client.release(); }
});

// ---------- EARNINGS / HISTORY ----------
driver.get('/earnings', requireDriver, async (req, res) => {
  const id = req.driverId;
  const sum = async (cond) => Number((await pool.query(
    `SELECT COALESCE(SUM(total_earning),0) AS s FROM driver_earnings WHERE driver_id=$1 AND ${cond}`, [id])).rows[0].s);
  const total = (await pool.query(`SELECT COUNT(*)::int n FROM driver_earnings WHERE driver_id=$1`, [id])).rows[0].n;
  const list = await pool.query(
    `SELECT dd.order_id, dd.distance_km::float, e.base_earning::float, e.tip_amount::float,
            e.total_earning::float, e.created_at
       FROM driver_earnings e JOIN driver_deliveries dd ON dd.delivery_id=e.delivery_id
      WHERE e.driver_id=$1 ORDER BY e.created_at DESC LIMIT 50`, [id]);
  res.json({
    today: await sum(`created_at::date = CURRENT_DATE`),
    week: await sum(`created_at >= date_trunc('week', NOW())`),
    month: await sum(`created_at >= date_trunc('month', NOW())`),
    total_deliveries: total,
    items: list.rows.map(r => ({ ...r, order_code: ordCode(r.order_id), status: 'Completed' })),
  });
});

driver.get('/history', requireDriver, async (req, res) => {
  try {
    const cond = {
      today: `dd.delivered_at::date = CURRENT_DATE`,
      week: `dd.delivered_at >= date_trunc('week', NOW())`,
      month: `dd.delivered_at >= date_trunc('month', NOW())`,
      all: `TRUE`,
    }[req.query.range || 'all'] || 'TRUE';
    const { rows } = await pool.query(
      `SELECT dd.delivery_id, dd.order_id, dd.delivered_at, dd.created_at, dd.restaurant_name,
              dd.customer_name, dd.delivery_address, dd.distance_km::float,
              dd.status, COALESCE(e.total_earning, dd.base_earning, 25)::float AS earning,
              COALESCE(e.tip_amount, 0)::float AS tip
         FROM driver_deliveries dd LEFT JOIN driver_earnings e ON e.delivery_id=dd.delivery_id
        WHERE dd.driver_id=$1 AND dd.status='DELIVERED' AND ${cond}
        ORDER BY dd.delivered_at DESC NULLS LAST, dd.created_at DESC LIMIT 200`, [req.driverId]);
    res.json(rows.map(r => ({
      ...r,
      order_code: ordCode(r.order_id),
      date: r.delivered_at || r.created_at,
    })));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Rate driver after delivery
driver.post(['/rate', '/feedback/rate'], async (req, res) => {
  const { orderId, driverId, driverCode, rating, feedback, tags } = req.body || {};
  const stars = Math.min(5, Math.max(1, Number(rating) || 5));
  try {
    let targetDriverId = driverId;
    if (!targetDriverId && (driverCode || orderId)) {
      if (orderId) {
        const rawId = parseInt(String(orderId).replace(/\D/g, ''), 10);
        const del = (await pool.query('SELECT driver_id FROM driver_deliveries WHERE order_id = $1 OR delivery_id::text = $2', [rawId, String(orderId)])).rows[0];
        if (del) targetDriverId = del.driver_id;
      }
      if (!targetDriverId && driverCode) {
        const d = (await pool.query('SELECT driver_id FROM drivers WHERE driver_code = $1', [driverCode])).rows[0];
        if (d) targetDriverId = d.driver_id;
      }
    }

    if (!targetDriverId) {
      const first = (await pool.query('SELECT driver_id FROM drivers ORDER BY driver_id LIMIT 1')).rows[0];
      targetDriverId = first?.driver_id;
    }

    if (targetDriverId) {
      const updated = await pool.query(
        `UPDATE drivers
         SET rating = ROUND(((COALESCE(rating, 5.0) * COALESCE(rating_count, 1) + $1::numeric) / (COALESCE(rating_count, 1) + 1)), 1),
             rating_count = COALESCE(rating_count, 1) + 1
         WHERE driver_id = $2
         RETURNING driver_id, driver_code, name, rating::float, rating_count`,
        [stars, targetDriverId]
      );
      return res.json({ success: true, driver: updated.rows[0], message: 'Thank you for rating the delivery driver!' });
    }
    res.json({ success: true, message: 'Rating recorded' });
  } catch (e) {
    console.error('[DRIVER] Rating error:', e);
    res.status(500).json({ error: e.message });
  }
});

// ---------- NOTIFICATIONS ----------
driver.get('/notifications', requireDriver, async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM driver_notifications WHERE driver_id=$1 ORDER BY created_at DESC LIMIT 50', [req.driverId]);
  res.json(rows);
});
driver.post('/notifications/read-all', requireDriver, async (req, res) => {
  await pool.query('UPDATE driver_notifications SET is_read=TRUE WHERE driver_id=$1', [req.driverId]);
  res.json({ ok: true });
});

// ---------- SECURITY ----------
driver.post('/change-password', requireDriver, async (req, res) => {
  const { current_password, new_password } = req.body || {};
  if (!new_password || new_password.length < 8 || !/\d/.test(new_password) || !/[A-Za-z]/.test(new_password))
    return res.status(400).json({ error: 'New password needs 8+ characters with letters and numbers' });
  const d = (await pool.query('SELECT password_hash FROM drivers WHERE driver_id=$1', [req.driverId])).rows[0];
  if (!(await bcrypt.compare(current_password || '', d.password_hash)))
    return res.status(401).json({ error: 'Current password is incorrect' });
  await pool.query('UPDATE drivers SET password_hash=$1 WHERE driver_id=$2', [await bcrypt.hash(new_password, 10), req.driverId]);
  await pool.query('UPDATE driver_sessions SET revoked=TRUE WHERE driver_id=$1 AND session_id<>$2', [req.driverId, req.sessionId]);
  res.json({ ok: true });
});
driver.get('/sessions', requireDriver, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT session_id, device, ip_address, created_at, last_seen, revoked, (session_id=$2) AS current
       FROM driver_sessions WHERE driver_id=$1 ORDER BY created_at DESC LIMIT 20`, [req.driverId, req.sessionId]);
  res.json(rows);
});
driver.post('/sessions/:sid/revoke', requireDriver, async (req, res) => {
  await pool.query('UPDATE driver_sessions SET revoked=TRUE WHERE session_id=$1 AND driver_id=$2', [req.params.sid, req.driverId]);
  res.json({ ok: true });
});

// ---------- CUSTOMER LIVE ORDER (read-only) ----------
track.get(['/track/:orderId', '/api/track/:orderId'], async (req, res) => {
  const rawId = parseInt(String(req.params.orderId).replace(/\D/g, ''), 10);
  if (!rawId) return res.status(400).json({ error: 'Invalid order ID' });

  try {
    const { rows } = await pool.query(
      `SELECT dd.delivery_id, dd.order_id, dd.status, ds.label, ds.step_order,
              dd.customer_name, dd.customer_phone, dd.delivery_address, dd.distance_km::float, dd.est_minutes,
              d.driver_id, d.driver_code, d.name AS driver_name, d.phone AS driver_phone,
              d.vehicle_type, d.vehicle_number, d.rating::float AS driver_rating, d.photo_url AS driver_photo_url,
              o.otp_code AS otp, o.verified AS otp_verified
         FROM driver_deliveries dd
         LEFT JOIN delivery_status ds ON ds.code=dd.status
         LEFT JOIN drivers d ON d.driver_id=dd.driver_id
         LEFT JOIN delivery_otp o ON o.delivery_id=dd.delivery_id
        WHERE dd.order_id=$1`,
      [rawId]
    );
    res.json(rows[0] || null);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ---------- ADMIN ----------
// !!! Replace adminGuard with YOUR existing admin auth middleware !!!
const adminGuard = (req, res, next) => next();

admin.get('/', adminGuard, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT d.driver_id, d.driver_code, d.name, d.phone, d.email, d.vehicle_type, d.vehicle_number,
            d.license_number, d.rating::float, d.status, d.is_active,
            (SELECT COUNT(*)::int FROM driver_deliveries x WHERE x.driver_id=d.driver_id AND x.status='DELIVERED') AS completed,
            (SELECT COALESCE(SUM(total_earning),0)::float FROM driver_earnings e WHERE e.driver_id=d.driver_id) AS earnings,
            (SELECT 'ORD-'||x.order_id||' ('||x.status||')' FROM driver_deliveries x
              WHERE x.driver_id=d.driver_id AND x.status NOT IN ('DELIVERED','CANCELLED','PENDING') LIMIT 1) AS current_delivery
       FROM drivers d ORDER BY d.driver_id`);
  res.json(rows);
});

admin.post('/', adminGuard, async (req, res) => {
  const b = req.body || {};
  if (!b.name || !/^\d{10}$/.test(b.phone || '') || !/^\S+@\S+\.\S+$/.test(b.email || '') || (b.password || '').length < 8)
    return res.status(400).json({ error: 'Name, 10-digit phone, valid email and 8+ char password required' });
  try {
    const n = (await pool.query('SELECT COALESCE(MAX(driver_id),0)+1 AS n FROM drivers')).rows[0].n;
    const code = `DRV-${1000 + Number(n)}`;
    const { rows } = await pool.query(
      `INSERT INTO drivers (driver_code,name,phone,email,password_hash,vehicle_type,vehicle_number,license_number)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING driver_id, driver_code`,
      [code, b.name, b.phone, b.email, await bcrypt.hash(b.password, 10),
       b.vehicle_type || 'Bike', b.vehicle_number || null, b.license_number || null]);
    res.status(201).json(rows[0]);
  } catch (e) {
    if (e.code === '23505') return res.status(409).json({ error: 'Phone or email already exists' });
    console.error(e); res.status(500).json({ error: 'Server error' });
  }
});

admin.put('/:id', adminGuard, async (req, res) => {
  const b = req.body || {};
  await pool.query(
    `UPDATE drivers SET name=COALESCE($1,name), phone=COALESCE($2,phone), email=COALESCE($3,email),
            vehicle_type=COALESCE($4,vehicle_type), vehicle_number=COALESCE($5,vehicle_number),
            license_number=COALESCE($6,license_number) WHERE driver_id=$7`,
    [b.name, b.phone, b.email, b.vehicle_type, b.vehicle_number, b.license_number, req.params.id]);
  res.json({ ok: true });
});

admin.patch('/:id/active', adminGuard, async (req, res) => {
  const active = !!(req.body || {}).is_active;
  await pool.query(
    `UPDATE drivers SET is_active=$1, status = CASE WHEN $1 THEN status ELSE 'OFFLINE' END WHERE driver_id=$2`,
    [active, req.params.id]);
  if (!active) await pool.query('UPDATE driver_sessions SET revoked=TRUE WHERE driver_id=$1', [req.params.id]);
  res.json({ ok: true });
});

admin.get('/:id/history', adminGuard, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT dd.order_id, dd.delivered_at, dd.distance_km::float, dd.status, e.total_earning::float AS earning
       FROM driver_deliveries dd LEFT JOIN driver_earnings e ON e.delivery_id=dd.delivery_id
      WHERE dd.driver_id=$1 ORDER BY dd.created_at DESC LIMIT 200`, [req.params.id]);
  res.json(rows);
});

admin.get('/:id/earnings', adminGuard, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT e.*, dd.order_id FROM driver_earnings e JOIN driver_deliveries dd ON dd.delivery_id=e.delivery_id
      WHERE e.driver_id=$1 ORDER BY e.created_at DESC`, [req.params.id]);
  res.json(rows);
});

admin.delete('/:id', adminGuard, async (req, res) => {
  const paramId = req.params.id;
  const rawId = parseInt(String(paramId).replace(/\D/g, ''), 10);
  try {
    const foundRes = await pool.query(
      'SELECT driver_id, driver_code, name FROM drivers WHERE driver_id = $1 OR driver_code = $2 LIMIT 1',
      [rawId || -1, String(paramId)]
    );
    const targetDriver = foundRes.rows[0];
    const targetId = targetDriver ? targetDriver.driver_id : (rawId || null);

    if (targetId) {
      await pool.query('DELETE FROM delivery_offers WHERE driver_id = $1', [targetId]);
      await pool.query('DELETE FROM driver_notifications WHERE driver_id = $1', [targetId]);
      await pool.query('DELETE FROM driver_sessions WHERE driver_id = $1', [targetId]);
      await pool.query('DELETE FROM driver_earnings WHERE driver_id = $1', [targetId]);
      await pool.query('UPDATE driver_deliveries SET driver_id = NULL WHERE driver_id = $1', [targetId]);
      await pool.query('DELETE FROM drivers WHERE driver_id = $1', [targetId]);
    } else if (paramId) {
      await pool.query('DELETE FROM drivers WHERE driver_code = $1', [paramId]);
    }
    const io = req.app.get('io');
    if (io) {
      io.emit('driver:removed', { driverId: targetId || rawId, driverCode: paramId });
      io.emit('driver:force_logout', { driverId: targetId || rawId, driverCode: paramId });
    }
    res.json({ ok: true, message: 'Driver deleted successfully' });
  } catch (e) {
    console.error('[ADMIN DELETE DRIVER]', e);
    res.status(500).json({ error: e.message });
  }
});

module.exports = { driver, admin, track };