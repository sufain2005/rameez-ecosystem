const { createDeliveryForOrder } = require('./driver/dispatch');

(async () => {
  const id = Math.floor(100000 + Math.random() * 900000);
  const r = await createDeliveryForOrder({
    orderId: id,
    customerName: 'Test Customer',
    customerPhone: '9000000000',
    deliveryAddress: '12, Green Park Road',
    deliveryNotes: 'Call at the gate',
    distanceKm: 3.5,
    estMinutes: 15,
  });
  console.log('Created ORD-' + id, ' | Customer OTP:', r && r.otp);
  process.exit(0);
})().catch(e => { console.error(e.message); process.exit(1); });