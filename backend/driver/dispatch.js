const pool = require('./db');
const { calcBaseEarning } = require('./earnings');

const OFFER_SECONDS = 30; // 30-second countdown before cascading to next online driver

function generateSecureOtp() {
  // Generates a distinct random 4-digit OTP (1000 - 9999)
  return String(Math.floor(1000 + Math.random() * 9000));
}

async function createDeliveryForOrder(info, io = null) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const base = calcBaseEarning(info.distanceKm);

    // Rameez Kitchen Davangere Coordinates (60 Feet Ring Road branch)
    const pickupLat = 14.4644;
    const pickupLng = 75.9218;

    // Generate simulated delivery coordinates within ~3-5km
    const randomOffset = () => (Math.random() - 0.5) * 0.04;
    const deliveryLat = pickupLat + randomOffset();
    const deliveryLng = pickupLng + randomOffset();

    let d = await client.query(
      `INSERT INTO driver_deliveries
        (order_id, customer_id, customer_name, customer_phone, delivery_address,
         delivery_notes, distance_km, est_minutes, base_earning, status,
         pickup_lat, pickup_lng, delivery_lat, delivery_lng)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'PENDING',$10,$11,$12,$13)
       ON CONFLICT (order_id) DO UPDATE SET
         customer_name = EXCLUDED.customer_name,
         customer_phone = EXCLUDED.customer_phone,
         delivery_address = EXCLUDED.delivery_address,
         delivery_lat = EXCLUDED.delivery_lat,
         delivery_lng = EXCLUDED.delivery_lng
       RETURNING delivery_id`,
      [info.orderId, info.customerId || null, info.customerName, info.customerPhone,
       info.deliveryAddress, info.deliveryNotes || null,
       info.distanceKm, info.estMinutes || 15, base,
       pickupLat, pickupLng, deliveryLat, deliveryLng]
    );

    let deliveryId;
    if (d.rows.length) {
      deliveryId = d.rows[0].delivery_id;
    } else {
      const fetchDel = await client.query('SELECT delivery_id FROM driver_deliveries WHERE order_id=$1', [info.orderId]);
      deliveryId = fetchDel.rows[0]?.delivery_id;
    }

    if (!deliveryId) {
      await client.query('ROLLBACK');
      return null;
    }

    // Generate distinct random 4-digit OTP per session
    const otp = generateSecureOtp();
    await client.query(
      `INSERT INTO delivery_otp (delivery_id, otp_code, verified, attempts)
       VALUES ($1, $2, FALSE, 0)
       ON CONFLICT (delivery_id) DO UPDATE SET
         otp_code = EXCLUDED.otp_code,
         verified = FALSE,
         attempts = 0`,
      [deliveryId, otp]
    );

    // Find first available online active driver who does not have an in-progress delivery
    const drivers = await client.query(
      `SELECT driver_id FROM drivers d
        WHERE status='ONLINE' AND is_active
          AND NOT EXISTS (SELECT 1 FROM driver_deliveries x
                           WHERE x.driver_id=d.driver_id
                             AND x.status NOT IN ('DELIVERED','CANCELLED'))
        ORDER BY driver_id ASC`
    );

    let assignedCount = 0;
    if (drivers.rows.length > 0) {
      // Offer to the first available driver with 30s countdown
      const firstDriver = drivers.rows[0];
      await client.query(
        `INSERT INTO delivery_offers (delivery_id, driver_id, status, expires_at)
         VALUES ($1, $2, 'PENDING', NOW() + INTERVAL '${OFFER_SECONDS} seconds')
         ON CONFLICT DO NOTHING`,
        [deliveryId, firstDriver.driver_id]
      );
      await client.query(
        `INSERT INTO driver_notifications (driver_id, type, title, body)
         VALUES ($1, 'NEW_DELIVERY', 'New Delivery', $2)`,
        [firstDriver.driver_id, `Order #ORD-${info.orderId} is ready for pickup & delivery.`]
      );
      assignedCount++;
    }

    await client.query('COMMIT');

    if (io) {
      io.emit('offers:updated', {});
    }

    // If no driver online at all, immediately notify merchant
    if (assignedCount === 0 && io) {
      io.emit('merchant:no_driver_alert', {
        orderId: info.orderId,
        orderCode: `ORD-${info.orderId}`,
        message: `⚠️ No active online drivers available for Order #ORD-${info.orderId}. Please check driver app fleet.`,
      });
    }

    return { deliveryId, otp };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

const lastAlertTimeByOrder = new Map();

async function reofferStale(io = null) {
  try {
    // 1. Mark timed-out 30s offers as EXPIRED
    await pool.query(
      `UPDATE delivery_offers SET status='EXPIRED' WHERE status='PENDING' AND expires_at < NOW()`
    );

    // Auto-cancel stale pending deliveries older than 2 hours so drivers only see real-time orders
    await pool.query(
      `UPDATE driver_deliveries SET status='CANCELLED' WHERE status='PENDING' AND created_at < NOW() - INTERVAL '2 hours'`
    );

    // 2. For any recent pending unassigned deliveries, find next available online driver
    const { rows: pending } = await pool.query(
      `SELECT dd.delivery_id, dd.order_id FROM driver_deliveries dd
        WHERE dd.status='PENDING' AND dd.driver_id IS NULL
          AND dd.created_at >= NOW() - INTERVAL '2 hours'
        ORDER BY dd.created_at DESC`
    );

    for (const r of pending) {
      // Check if there is already an active pending offer for this delivery
      const activeOffer = await pool.query(
        `SELECT offer_id FROM delivery_offers WHERE delivery_id=$1 AND status='PENDING' AND expires_at >= NOW()`,
        [r.delivery_id]
      );

      if (activeOffer.rows.length === 0) {
        // Find next online driver who hasn't been offered yet in this cycle
        let nextDriver = await pool.query(
          `SELECT d.driver_id FROM drivers d
            WHERE d.status='ONLINE' AND d.is_active
              AND NOT EXISTS (
                SELECT 1 FROM delivery_offers o
                WHERE o.delivery_id=$1 AND o.driver_id=d.driver_id AND o.status IN ('DECLINED', 'EXPIRED')
              )
              AND NOT EXISTS (
                SELECT 1 FROM driver_deliveries x
                WHERE x.driver_id=d.driver_id
                  AND x.status NOT IN ('DELIVERED','CANCELLED'))
            ORDER BY d.driver_id ASC LIMIT 1`,
          [r.delivery_id]
        );

        // If all online drivers were cycled through without an accept, reset cycle to keep trying online drivers
        if (nextDriver.rows.length === 0) {
          const anyOnline = await pool.query(
            `SELECT d.driver_id FROM drivers d
              WHERE d.status='ONLINE' AND d.is_active
                AND NOT EXISTS (
                  SELECT 1 FROM driver_deliveries x
                  WHERE x.driver_id=d.driver_id
                    AND x.status NOT IN ('DELIVERED','CANCELLED'))
              ORDER BY d.driver_id ASC LIMIT 1`
          );

          if (anyOnline.rows.length > 0) {
            // Clear previous expired offers to restart round-robin dispatch across online fleet
            await pool.query(
              `DELETE FROM delivery_offers WHERE delivery_id=$1 AND status IN ('EXPIRED', 'DECLINED')`,
              [r.delivery_id]
            );
            nextDriver = anyOnline;
          }
        }

        if (nextDriver.rows.length > 0) {
          const drvId = nextDriver.rows[0].driver_id;
          await pool.query(
            `INSERT INTO delivery_offers (delivery_id, driver_id, status, expires_at)
             VALUES ($1, $2, 'PENDING', NOW() + INTERVAL '${OFFER_SECONDS} seconds')`,
            [r.delivery_id, drvId]
          );
          await pool.query(
            `INSERT INTO driver_notifications (driver_id, type, title, body)
             VALUES ($1, 'NEW_DELIVERY', 'New Delivery (Re-assigned)', $2)`,
            [drvId, `Order #ORD-${r.order_id} transferred to you. 30s to accept.`]
          );
          if (io) {
            io.emit('offers:updated', {});
          }
        } else {
          // Literally NO online drivers in fleet! Debounce alert to merchant (max once per 60s per order)
          const now = Date.now();
          const lastAlert = lastAlertTimeByOrder.get(r.order_id) || 0;
          if (now - lastAlert > 60000 && io) {
            lastAlertTimeByOrder.set(r.order_id, now);
            io.emit('merchant:no_driver_alert', {
              orderId: r.order_id,
              orderCode: `ORD-${r.order_id}`,
              message: `⚠️ No active online drivers available for Order #ORD-${r.order_id}. All drivers offline.`,
            });
          }
        }
      }
    }
  } catch (err) {
    console.warn('[DISPATCH] reofferStale error:', err.message);
  }
}

module.exports = { createDeliveryForOrder, reofferStale, OFFER_SECONDS };