const bcrypt = require('bcryptjs');
const pool = require('./driver/db');

(async () => {
  const hash = await bcrypt.hash('Driver@123', 10);
  await pool.query(
    `INSERT INTO drivers (driver_code,name,phone,email,password_hash,vehicle_type,vehicle_number,license_number,rating,rating_count)
     VALUES ('DRV-1001','Arjun Kumar','9876543210','arjun@rameezkitchen.com',$1,'Bike','KA01AB1234','DL-0420110149646',4.8,52),
            ('DRV-1002','Imran Khan','9876500011','imran@rameezkitchen.com',$1,'Scooter','KA05CD5678','DL-0520120234567',4.6,31)
     ON CONFLICT (driver_code) DO UPDATE
       SET password_hash = EXCLUDED.password_hash, is_active = TRUE`,
    [hash]
  );
  const r = await pool.query('SELECT driver_code, name, phone, is_active FROM drivers ORDER BY driver_id');
  console.table(r.rows);
  process.exit(0);
})().catch(e => { console.error(e.message); process.exit(1); });