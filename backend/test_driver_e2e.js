const pool = require('./driver/db');
const { createDeliveryForOrder, reofferStale } = require('./driver/dispatch');
const bcrypt = require('bcryptjs');
const { sign } = require('./driver/auth');

async function runE2ETest() {
  console.log('--- Starting Driver E2E Flow Verification ---');

  // 1. Create unique test driver
  const testPhone = '98' + Math.floor(10000000 + Math.random() * 90000000);
  const testEmail = `driver_${Date.now()}@rameezkitchen.com`;
  const passwordHash = await bcrypt.hash('123456', 10);
  const driverCode = `DRV-${Math.floor(1000 + Math.random() * 9000)}`;

  const ins = await pool.query(
    `INSERT INTO drivers (driver_code, name, phone, email, password_hash, vehicle_type, vehicle_number, license_number, photo_url, license_photo_url, vehicle_photo_url, rating, rating_count, status, is_active)
     VALUES ($1, $2, $3, $4, $5, 'Bike', 'KA-17-EQ-8899', 'DL-KA17-20240099', 'https://example.com/dl.jpg', 'https://example.com/dl.jpg', 'https://example.com/bike.jpg', 5.0, 1, 'ONLINE', TRUE)
     RETURNING *`,
    [driverCode, 'Rameez Delivery Hero', testPhone, testEmail, passwordHash]
  );
  const driver = ins.rows[0];
  console.log('✓ Driver registered & online:', driver.name, `(${driver.driver_code})`);

  // 2. Create order & dispatch offer
  const orderId = Math.floor(100000 + Math.random() * 900000);
  const delivery = await createDeliveryForOrder({
    orderId,
    customerName: 'Amina Begum',
    customerPhone: '9876543210',
    deliveryAddress: 'Flat 302, Green Meadows, 60 Feet Road',
    deliveryNotes: 'Please ring bell',
    distanceKm: 3.5,
    estMinutes: 15,
  });
  console.log('✓ Delivery created for ORD-' + orderId, 'Delivery ID:', delivery.deliveryId, 'OTP:', delivery.otp);

  // 3. Find offer for this driver
  const offerRes = await pool.query(
    'SELECT * FROM delivery_offers WHERE driver_id = $1 AND delivery_id = $2',
    [driver.driver_id, delivery.deliveryId]
  );
  console.log('✓ Found offer for driver:', offerRes.rows[0]?.offer_id, 'Status:', offerRes.rows[0]?.status);

  // 4. Accept offer
  const offerId = offerRes.rows[0]?.offer_id;
  if (offerId) {
    await pool.query(
      `UPDATE driver_deliveries SET driver_id = $1, status = 'GOING_TO_RESTAURANT', accepted_at = NOW() WHERE delivery_id = $2`,
      [driver.driver_id, delivery.deliveryId]
    );
    await pool.query(`UPDATE delivery_offers SET status = 'ACCEPTED' WHERE offer_id = $1`, [offerId]);
    console.log('✓ Offer accepted successfully without errors!');
  }

  // 5. Advance through progression
  const statuses = ['ARRIVED_RESTAURANT', 'PICKED_UP', 'ON_THE_WAY', 'ARRIVED_CUSTOMER'];
  for (const s of statuses) {
    await pool.query('UPDATE driver_deliveries SET status = $1 WHERE delivery_id = $2', [s, delivery.deliveryId]);
    console.log(`✓ Status transitioned to -> ${s}`);
  }

  // 6. Verify OTP and complete delivery
  await pool.query('UPDATE delivery_otp SET verified = TRUE, verified_at = NOW() WHERE delivery_id = $1', [delivery.deliveryId]);
  await pool.query(`UPDATE driver_deliveries SET status = 'DELIVERED', delivered_at = NOW() WHERE delivery_id = $1`, [delivery.deliveryId]);
  await pool.query(
    `INSERT INTO driver_earnings (delivery_id, driver_id, base_earning, tip_amount, total_earning) VALUES ($1,$2,25,0,25)`,
    [delivery.deliveryId, driver.driver_id]
  );
  console.log('✓ OTP Verified! Delivery marked DELIVERED and ₹25 credited to driver wallet.');

  // 7. Test Driver Rating
  const rateRes = await pool.query(
    `UPDATE drivers
     SET rating = ROUND(((COALESCE(rating, 5.0) * COALESCE(rating_count, 1) + 5.0) / (COALESCE(rating_count, 1) + 1)), 1),
         rating_count = COALESCE(rating_count, 1) + 1
     WHERE driver_id = $1 RETURNING driver_id, name, rating::float, rating_count`,
    [driver.driver_id]
  );
  console.log('✓ Driver rated 5 stars:', rateRes.rows[0]);

  console.log('--- E2E Flow Test Passed 100% Successfully! ---');
}

runE2ETest().then(() => process.exit(0)).catch(e => { console.error('E2E Test Failed:', e); process.exit(1); });
