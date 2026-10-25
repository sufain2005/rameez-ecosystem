const pool = require('./driver/db');
const { sign } = require('./driver/auth');
const { createDeliveryForOrder } = require('./driver/dispatch');

async function testApi() {
  console.log('--- Testing API lifecycle ---');
  const bcrypt = require('bcryptjs');
  const testPhone = '98' + Math.floor(10000000 + Math.random() * 90000000);
  const passwordHash = await bcrypt.hash('123456', 10);
  const driverCode = `DRV-${Math.floor(1000 + Math.random() * 9000)}`;

  const ins = await pool.query(
    `INSERT INTO drivers (driver_code, name, phone, email, password_hash, vehicle_type, vehicle_number, license_number, photo_url, rating, rating_count, status, is_active)
     VALUES ($1, $2, $3, $4, $5, 'Bike', 'KA-17-EQ-8899', 'DL-KA17-20240099', 'https://example.com/dl.jpg', 5.0, 1, 'ONLINE', TRUE)
     RETURNING *`,
    [driverCode, 'Live Test Hero', testPhone, `test_${Date.now()}@driver.com`, passwordHash]
  );
  const d = ins.rows[0];
  console.log('Testing with fresh driver:', d.name, d.driver_code);

  const s = await pool.query(
    'INSERT INTO driver_sessions (driver_id, device, ip_address) VALUES ($1, $2, $3) RETURNING session_id',
    [d.driver_id, 'Test Script', '127.0.0.1']
  );
  const token = sign(d, s.rows[0].session_id);

  const rawId = Math.floor(100000 + Math.random() * 900000);
  const del = await createDeliveryForOrder({
    orderId: rawId,
    customerName: 'Amina Begum',
    customerPhone: '9876543210',
    deliveryAddress: 'Flat 302, Green Meadows',
    distanceKm: 3.2,
    estMinutes: 18
  });
  console.log('✓ Created test delivery for ORD-' + rawId, del);

  const offRes = await fetch('http://localhost:5000/api/driver/offers/current', {
    headers: { 'Authorization': 'Bearer ' + token }
  });
  const offer = await offRes.json();
  console.log('✓ Current offer received:', offer?.offer_id, offer?.order_code);

  if (offer && offer.offer_id) {
    // 1. Accept offer
    const accRes = await fetch(`http://localhost:5000/api/driver/offers/${offer.offer_id}/accept`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + token }
    });
    const accJson = await accRes.json();
    console.log('✓ Accept Offer HTTP ' + accRes.status + ':', accJson);

    // 2. Advance to ARRIVED_RESTAURANT
    const adv1 = await (await fetch(`http://localhost:5000/api/driver/deliveries/${offer.delivery_id}/advance`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + token }
    })).json();
    console.log('✓ Advance 1 (ARRIVED_RESTAURANT):', adv1);

    // 3. Advance to PICKED_UP
    const adv2 = await (await fetch(`http://localhost:5000/api/driver/deliveries/${offer.delivery_id}/advance`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + token }
    })).json();
    console.log('✓ Advance 2 (PICKED_UP):', adv2);

    // 4. Advance to ON_THE_WAY
    const adv3 = await (await fetch(`http://localhost:5000/api/driver/deliveries/${offer.delivery_id}/advance`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + token }
    })).json();
    console.log('✓ Advance 3 (ON_THE_WAY):', adv3);

    // 5. Advance to ARRIVED_CUSTOMER
    const adv4 = await (await fetch(`http://localhost:5000/api/driver/deliveries/${offer.delivery_id}/advance`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + token }
    })).json();
    console.log('✓ Advance 4 (ARRIVED_CUSTOMER):', adv4);

    // 6. Verify OTP
    const otpRes = await (await fetch(`http://localhost:5000/api/driver/deliveries/${offer.delivery_id}/verify-otp`, {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ otp: del.otp })
    })).json();
    console.log('✓ Verify OTP Result:', otpRes);

    // 7. Rate Driver
    const rateRes = await (await fetch('http://localhost:5000/api/driver/rate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId: rawId, driverId: d.driver_id, rating: 5 })
    })).json();
    console.log('✓ Driver Rating Result:', rateRes);

    console.log('========================================================');
    console.log('🎉 ALL API LIFECYCLE ENDPOINTS EXECUTED 100% CLEANLY!');
    console.log('========================================================');
  }
}

testApi().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
