const path = require('path');
const { Pool } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const poolConfig = process.env.DATABASE_URL
  ? {
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DATABASE_URL.includes('localhost') || process.env.DATABASE_URL.includes('127.0.0.1')
        ? false
        : { rejectUnauthorized: false },
    }
  : {
      user: process.env.DB_USER || 'postgres',
      password: String(process.env.DB_PASSWORD || 'sufi123'),
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT, 10) || 5432,
      database: process.env.DB_NAME || 'rameez_kitchen_db',
      ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
    };

const pool = new Pool(poolConfig);

async function initSchema() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS drivers (
        driver_id SERIAL PRIMARY KEY,
        driver_code VARCHAR(30) UNIQUE,
        name VARCHAR(100) NOT NULL,
        phone VARCHAR(20) UNIQUE NOT NULL,
        email VARCHAR(120),
        password_hash VARCHAR(255) NOT NULL,
        photo_url TEXT,
        vehicle_type VARCHAR(50) DEFAULT 'Bike',
        vehicle_number VARCHAR(50) NOT NULL,
        license_number VARCHAR(80),
        rating NUMERIC(3,2) DEFAULT 5.0,
        rating_count INTEGER DEFAULT 1,
        status VARCHAR(20) DEFAULT 'ONLINE',
        is_active BOOLEAN DEFAULT TRUE,
        bank_account VARCHAR(50),
        upi_id VARCHAR(80),
        license_photo_url TEXT,
        vehicle_photo_url TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS delivery_status (
        code VARCHAR(30) PRIMARY KEY,
        label VARCHAR(40) NOT NULL,
        step_order INT NOT NULL,
        order_status_label VARCHAR(30)
      );

      INSERT INTO delivery_status (code, label, step_order, order_status_label) VALUES
        ('PENDING', 'Pending', 0, NULL),
        ('ACCEPTED', 'Order Accepted', 1, 'Driver Assigned'),
        ('GOING_TO_RESTAURANT', 'Going to Restaurant', 2, 'Driver Assigned'),
        ('ARRIVED_RESTAURANT', 'Arrived at Restaurant', 3, 'Driver Assigned'),
        ('PICKED_UP', 'Order Picked Up', 4, 'Picked Up'),
        ('ON_THE_WAY', 'On the Way', 5, 'Out for Delivery'),
        ('ARRIVED_CUSTOMER', 'Arrived at Customer', 6, 'Out for Delivery'),
        ('OTP_VERIFIED', 'OTP Verified', 7, 'Out for Delivery'),
        ('DELIVERED', 'Delivered', 8, 'Delivered'),
        ('CANCELLED', 'Cancelled', 99, NULL)
      ON CONFLICT (code) DO NOTHING;

      CREATE TABLE IF NOT EXISTS driver_deliveries (
        delivery_id SERIAL PRIMARY KEY,
        order_id VARCHAR(50) UNIQUE NOT NULL,
        driver_id INTEGER REFERENCES drivers(driver_id),
        restaurant_id INTEGER DEFAULT 1,
        customer_id VARCHAR(50),
        restaurant_name VARCHAR(100) DEFAULT 'Rameez Kitchen',
        restaurant_phone VARCHAR(20) DEFAULT '+919876543210',
        pickup_address TEXT DEFAULT '60 Feet Ring Road',
        delivery_address TEXT NOT NULL,
        customer_name VARCHAR(100),
        customer_phone VARCHAR(20),
        delivery_notes TEXT,
        distance_km NUMERIC(5,2) DEFAULT 3.5,
        est_minutes INTEGER DEFAULT 15,
        base_earning NUMERIC(8,2) DEFAULT 25.0,
        status VARCHAR(30) DEFAULT 'PENDING',
        pickup_lat DOUBLE PRECISION DEFAULT 14.4644,
        pickup_lng DOUBLE PRECISION DEFAULT 75.9218,
        delivery_lat DOUBLE PRECISION DEFAULT 14.4690,
        delivery_lng DOUBLE PRECISION DEFAULT 75.9280,
        accepted_at TIMESTAMP WITH TIME ZONE,
        picked_up_at TIMESTAMP WITH TIME ZONE,
        delivered_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS delivery_offers (
        offer_id SERIAL PRIMARY KEY,
        delivery_id INT NOT NULL REFERENCES driver_deliveries(delivery_id) ON DELETE CASCADE,
        driver_id INT NOT NULL REFERENCES drivers(driver_id),
        status VARCHAR(10) NOT NULL DEFAULT 'PENDING',
        expires_at TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS driver_tips (
        tip_id SERIAL PRIMARY KEY,
        order_id INT NOT NULL UNIQUE,
        amount NUMERIC(8,2) NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS driver_earnings (
        earning_id SERIAL PRIMARY KEY,
        delivery_id INT NOT NULL UNIQUE REFERENCES driver_deliveries(delivery_id),
        driver_id INT NOT NULL REFERENCES drivers(driver_id),
        base_earning NUMERIC(8,2) NOT NULL DEFAULT 25.0,
        tip_amount NUMERIC(8,2) NOT NULL DEFAULT 0,
        total_earning NUMERIC(8,2) NOT NULL DEFAULT 25.0,
        payment_status VARCHAR(10) NOT NULL DEFAULT 'PENDING',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS delivery_otp (
        otp_id SERIAL PRIMARY KEY,
        delivery_id INT NOT NULL UNIQUE REFERENCES driver_deliveries(delivery_id) ON DELETE CASCADE,
        otp_code CHAR(4) NOT NULL,
        verified BOOLEAN NOT NULL DEFAULT FALSE,
        attempts INT NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        verified_at TIMESTAMPTZ
      );

      CREATE TABLE IF NOT EXISTS driver_notifications (
        notification_id SERIAL PRIMARY KEY,
        driver_id INT NOT NULL REFERENCES drivers(driver_id),
        type VARCHAR(30) NOT NULL,
        title VARCHAR(100) NOT NULL,
        body TEXT NOT NULL,
        is_read BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS driver_sessions (
        session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        driver_id INT NOT NULL REFERENCES drivers(driver_id),
        device VARCHAR(120),
        ip_address VARCHAR(50),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        revoked BOOLEAN NOT NULL DEFAULT FALSE
      );

      ALTER TABLE driver_deliveries ADD COLUMN IF NOT EXISTS pickup_lat DOUBLE PRECISION DEFAULT 14.4644;
      ALTER TABLE driver_deliveries ADD COLUMN IF NOT EXISTS pickup_lng DOUBLE PRECISION DEFAULT 75.9218;
      ALTER TABLE driver_deliveries ADD COLUMN IF NOT EXISTS delivery_lat DOUBLE PRECISION DEFAULT 14.4690;
      ALTER TABLE driver_deliveries ADD COLUMN IF NOT EXISTS delivery_lng DOUBLE PRECISION DEFAULT 75.9280;
      ALTER TABLE driver_deliveries ADD COLUMN IF NOT EXISTS restaurant_name VARCHAR(100) DEFAULT 'Rameez Kitchen';
      ALTER TABLE driver_deliveries ADD COLUMN IF NOT EXISTS restaurant_phone VARCHAR(20) DEFAULT '+919876543210';
      ALTER TABLE driver_deliveries ADD COLUMN IF NOT EXISTS pickup_address TEXT DEFAULT '60 Feet Ring Road';

      ALTER TABLE drivers ADD COLUMN IF NOT EXISTS rating_count INTEGER DEFAULT 1;
      ALTER TABLE drivers ADD COLUMN IF NOT EXISTS upi_id VARCHAR(80);
      ALTER TABLE drivers ADD COLUMN IF NOT EXISTS bank_account VARCHAR(50);
      ALTER TABLE drivers ADD COLUMN IF NOT EXISTS license_photo_url TEXT;
      ALTER TABLE drivers ADD COLUMN IF NOT EXISTS vehicle_photo_url TEXT;
    `);
    console.log('✓ PostgreSQL schema verified & auto-migrated');
  } catch (err) {
    console.error('Database migration error:', err.message);
  }
}

pool.connect()
  .then(async () => {
    console.log('✓ PostgreSQL connected');
    await initSchema();
  })
  .catch((err) => console.error('Database connection error:', err.message));

module.exports = pool;