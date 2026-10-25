-- ============ DRIVERS ============
CREATE TABLE IF NOT EXISTS drivers (
  driver_id       SERIAL PRIMARY KEY,
  driver_code     VARCHAR(20) UNIQUE NOT NULL,
  name            VARCHAR(100) NOT NULL,
  phone           VARCHAR(15)  UNIQUE NOT NULL,
  email           VARCHAR(120) UNIQUE NOT NULL,
  password_hash   TEXT NOT NULL,
  photo_url       TEXT,
  vehicle_type    VARCHAR(30) NOT NULL DEFAULT 'Bike',
  vehicle_number  VARCHAR(20),
  license_number  VARCHAR(30),
  rating          NUMERIC(2,1) NOT NULL DEFAULT 5.0,
  rating_count    INT NOT NULL DEFAULT 0,
  status          VARCHAR(10) NOT NULL DEFAULT 'OFFLINE'
                  CHECK (status IN ('ONLINE','OFFLINE')),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  bank_account    VARCHAR(40),
  upi_id          VARCHAR(60),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============ STATUS LOOKUP ============
CREATE TABLE IF NOT EXISTS delivery_status (
  code        VARCHAR(30) PRIMARY KEY,
  label       VARCHAR(40) NOT NULL,
  step_order  INT NOT NULL,
  order_status_label VARCHAR(30)
);
INSERT INTO delivery_status (code,label,step_order,order_status_label) VALUES
 ('PENDING','Pending',0,NULL),
 ('ACCEPTED','Order Accepted',1,'Driver Assigned'),
 ('GOING_TO_RESTAURANT','Going to Restaurant',2,'Driver Assigned'),
 ('ARRIVED_RESTAURANT','Arrived at Restaurant',3,'Driver Assigned'),
 ('PICKED_UP','Order Picked Up',4,'Picked Up'),
 ('ON_THE_WAY','On the Way',5,'Out for Delivery'),
 ('ARRIVED_CUSTOMER','Arrived at Customer',6,'Out for Delivery'),
 ('OTP_VERIFIED','OTP Verified',7,'Out for Delivery'),
 ('DELIVERED','Delivered',8,'Delivered'),
 ('CANCELLED','Cancelled',99,NULL)
ON CONFLICT (code) DO NOTHING;

-- ============ DELIVERIES ============
CREATE TABLE IF NOT EXISTS driver_deliveries (
  delivery_id      SERIAL PRIMARY KEY,
  order_id         INT NOT NULL UNIQUE,
  driver_id        INT REFERENCES drivers(driver_id),
  restaurant_id    INT NOT NULL DEFAULT 1,
  customer_id      INT,
  restaurant_name  VARCHAR(100) NOT NULL DEFAULT 'Rameez Kitchen',
  restaurant_phone VARCHAR(15),
  pickup_address   TEXT NOT NULL DEFAULT '60 Feet Ring Road',
  delivery_address TEXT NOT NULL,
  customer_name    VARCHAR(100),
  customer_phone   VARCHAR(15),
  delivery_notes   TEXT,
  distance_km      NUMERIC(5,2) NOT NULL,
  est_minutes      INT NOT NULL DEFAULT 15,
  base_earning     NUMERIC(8,2) NOT NULL,
  status           VARCHAR(30) NOT NULL DEFAULT 'PENDING' REFERENCES delivery_status(code),
  accepted_at      TIMESTAMPTZ,
  picked_up_at     TIMESTAMPTZ,
  delivered_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_dd_driver ON driver_deliveries(driver_id, status);

-- ============ OFFERS (15-second requests) ============
CREATE TABLE IF NOT EXISTS delivery_offers (
  offer_id    SERIAL PRIMARY KEY,
  delivery_id INT NOT NULL REFERENCES driver_deliveries(delivery_id) ON DELETE CASCADE,
  driver_id   INT NOT NULL REFERENCES drivers(driver_id),
  status      VARCHAR(10) NOT NULL DEFAULT 'PENDING'
              CHECK (status IN ('PENDING','ACCEPTED','DECLINED','EXPIRED')),
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (delivery_id, driver_id)
);

-- ============ TIPS ============
CREATE TABLE IF NOT EXISTS driver_tips (
  tip_id     SERIAL PRIMARY KEY,
  order_id   INT NOT NULL UNIQUE,
  amount     NUMERIC(8,2) NOT NULL CHECK (amount >= 0 AND amount <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============ EARNINGS ============
CREATE TABLE IF NOT EXISTS driver_earnings (
  earning_id     SERIAL PRIMARY KEY,
  delivery_id    INT NOT NULL UNIQUE REFERENCES driver_deliveries(delivery_id),
  driver_id      INT NOT NULL REFERENCES drivers(driver_id),
  base_earning   NUMERIC(8,2) NOT NULL,
  tip_amount     NUMERIC(8,2) NOT NULL DEFAULT 0,
  total_earning  NUMERIC(8,2) NOT NULL,
  payment_status VARCHAR(10) NOT NULL DEFAULT 'PENDING'
                 CHECK (payment_status IN ('PENDING','PAID')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_de_driver ON driver_earnings(driver_id, created_at);

-- ============ OTP ============
CREATE TABLE IF NOT EXISTS delivery_otp (
  otp_id      SERIAL PRIMARY KEY,
  delivery_id INT NOT NULL UNIQUE REFERENCES driver_deliveries(delivery_id) ON DELETE CASCADE,
  otp_code    CHAR(4) NOT NULL,
  verified    BOOLEAN NOT NULL DEFAULT FALSE,
  attempts    INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  verified_at TIMESTAMPTZ
);

-- ============ NOTIFICATIONS ============
CREATE TABLE IF NOT EXISTS driver_notifications (
  notification_id SERIAL PRIMARY KEY,
  driver_id  INT NOT NULL REFERENCES drivers(driver_id),
  type       VARCHAR(30) NOT NULL,
  title      VARCHAR(100) NOT NULL,
  body       TEXT NOT NULL,
  is_read    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============ SESSIONS / LOGIN ACTIVITY ============
CREATE TABLE IF NOT EXISTS driver_sessions (
  session_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id   INT NOT NULL REFERENCES drivers(driver_id),
  device      VARCHAR(120),
  ip_address  VARCHAR(50),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked     BOOLEAN NOT NULL DEFAULT FALSE
);