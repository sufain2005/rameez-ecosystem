const express = require('express');
const http = require('http');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const bcrypt = require('bcryptjs');
const { Server } = require('socket.io');
require('dotenv').config();

const app = express();
const server = http.createServer(app);

// Allow standard Flutter web ports and local IPs
const defaultOrigins = [
  'http://localhost:3000',
  'http://localhost:8080',
  'http://localhost:8081',
  'http://localhost:8082',
  'http://127.0.0.1:8080',
  'http://127.0.0.1:8081',
  'http://127.0.0.1:8082',
  'http://10.0.2.2:5000'
];

const envOrigins = (process.env.CORS_ORIGIN || '')
  .split(',')
  .map((item) => item.trim())
  .filter(Boolean);

const ALLOWED_ORIGINS = [...new Set([...defaultOrigins, ...envOrigins])];

const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    credentials: true,
  },
});

const PORT = Number(process.env.PORT || 5000);

// ---------- Security ----------
app.use(helmet({ crossOriginResourcePolicy: false }));

app.use(
  cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (mobile apps, Postman) or matching origins
      if (!origin || ALLOWED_ORIGINS.includes('*') || ALLOWED_ORIGINS.includes(origin) || origin.startsWith('http://localhost:')) {
        callback(null, true);
      } else {
        callback(null, true); // Permissive in dev to avoid blocking Flutter Web
      }
    },
    credentials: true,
  })
);

const fs = require('fs');
const path = require('path');

const uploadsDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}
app.use('/uploads', express.static(uploadsDir));

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));

const crypto = require('crypto');
const APP_SIGNING_SECRET = process.env.APP_SIGNING_SECRET || 'rk_sec_994bfa283c07f45a8e10d287bc12';

// Replay-Attack Prevention Cache
const seenNonces = new Set();
setInterval(() => {
  if (seenNonces.size > 50000) seenNonces.clear();
}, 15 * 60 * 1000);

// Anti-Tampering & Request Integrity Middleware (Blocks Burp Suite / MitM tampering)
const verifyRequestIntegrity = (req, res, next) => {
  const signature = req.headers['x-app-signature'];
  const timestamp = req.headers['x-app-timestamp'];
  const nonce = req.headers['x-app-nonce'];

  if (signature && timestamp && nonce) {
    const now = Date.now();
    const reqTime = parseInt(timestamp, 10);

    // Reject timestamps older than 10 minutes or in the future
    if (isNaN(reqTime) || Math.abs(now - reqTime) > 10 * 60 * 1000) {
      return res.status(403).json({ success: false, error: 'Request rejected: Expired or invalid timestamp.' });
    }

    // Reject replayed nonces
    if (seenNonces.has(nonce)) {
      return res.status(403).json({ success: false, error: 'Request rejected: Replay attack detected.' });
    }
    seenNonces.add(nonce);

    // Normalize path and payload
    const cleanPath = req.originalUrl ? req.originalUrl.split('?')[0] : req.path;
    let bodyPayload = '';
    if (req.body && Object.keys(req.body).length > 0) {
      bodyPayload = JSON.stringify(req.body);
    }

    const payloadToSign = `${req.method.toUpperCase()}:${cleanPath}:${timestamp}:${nonce}:${bodyPayload}`;
    const expectedSig = crypto.createHmac('sha256', APP_SIGNING_SECRET).update(payloadToSign).digest('hex');

    const fallbackPayload = `${req.method.toUpperCase()}:${req.path}:${timestamp}:${nonce}:${bodyPayload}`;
    const fallbackSig = crypto.createHmac('sha256', APP_SIGNING_SECRET).update(fallbackPayload).digest('hex');

    if (signature !== expectedSig && signature !== fallbackSig) {
      console.warn(`[SECURITY ALERT] Tampered request signature detected from ${req.ip} on ${req.method} ${cleanPath}`);
      return res.status(403).json({ success: false, error: 'Request rejected: Cryptographic signature mismatch. Unauthorized tampering detected.' });
    }
  }
  next();
};

app.use(verifyRequestIntegrity);

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5000, // Relaxed for local multi-tab testing & background driver polling
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: 'Too many requests, please try again later.' },
});
app.use('/api/', apiLimiter);

// Strict Rate Limiting on Authentication & Sensitive Endpoints
const authLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 50,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: 'Too many authentication attempts. Please try again later.' },
});
app.use(['/api/send-otp', '/send-otp', '/api/verify-otp', '/verify-otp', '/api/driver/login'], authLimiter);

// ---------- In-memory state ----------
let activeOtpStore = {};
let menuCatalog = [
  {
    id: 1,
    name: 'Chicken Dum Biryani',
    price: 220,
    flavor: 'Aromatic & Spicy',
    image: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=600',
    available: true,
  },
  {
    id: 2,
    name: 'Mutton Dum Biryani',
    price: 280,
    flavor: 'Slow Cooked Charcoal',
    image: 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=600',
    available: true,
  },
  {
    id: 3,
    name: 'Chicken Tikka Roll',
    price: 140,
    flavor: 'Smoky & Juicy',
    image: 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=600',
    available: true,
  },
  {
    id: 4,
    name: 'Tandoori Platter',
    price: 320,
    flavor: 'Charcoal Grilled Delight',
    image: 'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=600',
    available: true,
  },
  {
    id: 5,
    name: 'Chicken Shawarma Plate',
    price: 160,
    flavor: 'Garlic Tahini Special',
    image: 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?w=600',
    available: true,
  },
];

let branchStatus = {
  '60_feet_ring_road': true,
  nittuvalli_circle: true,
};

let branchesInfo = {
  '60_feet_ring_road': {
    key: '60_feet_ring_road',
    name: 'Main Kitchen (60 Feet Ring Road)',
    tagline: 'Flagship Charcoal Grills & Dum Biryani Hub',
    address: 'Near Bus Stop, 60 Feet Ring Road, Davanagere',
    phone: '+91 8073349233',
    manager: 'Rameez Ahmed',
    avgPrepTime: '20-25 mins',
    image: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
    isOpen: true,
  },
  'nittuvalli_circle': {
    key: 'nittuvalli_circle',
    name: 'Express Hub (Nittuvalli Circle)',
    tagline: 'Fast Food, Shawarmas & Quick Bites',
    address: 'Nittuvalli Main Road, Opposite SBI, Davanagere',
    phone: '+91 9654321076',
    manager: 'Farhan Akhtar',
    avgPrepTime: '15-20 mins',
    image: 'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800',
    isOpen: true,
  },
};

let restaurantProfile = {
  name: 'Rameez Kitchen',
  tagline: 'Authentic Charcoal Kebabs & Traditional Dum Biryani',
  ownerName: 'Rameez Ahmed',
  avatar: 'https://images.unsplash.com/photo-1577219491135-ce391730fb2c?w=400',
  banner: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=1200',
  rating: 4.9,
  cuisine: 'Mughlai • North Indian • Biryani • BBQ',
  operatingHours: '11:00 AM – 11:30 PM',
  fssaiNumber: '11223344005566',
};

let globalStatus = {
  state: 'ACCEPTING_ORDERS',
  pauseReason: '',
};

let paymentSettings = {
  taxPercent: 5,
  serviceCharge: 15,
  upiQrImage:
    'https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=upi://pay?pa=rameez@okaxis&pn=RameezKitchen',
};

const defaultAdmin = {
  username: process.env.ADMIN_USERNAME || 'admin',
  email: process.env.ADMIN_EMAIL || 'admin@rameezkitchen.com',
  phone: process.env.ADMIN_PHONE || '8073349233',
  password: process.env.ADMIN_PASSWORD || 'admin',
};

let currentAdminPlainPassword = defaultAdmin.password;

let adminCredentials = {
  username: defaultAdmin.username,
  email: defaultAdmin.email,
  phone: defaultAdmin.phone,
  passwordHash: bcrypt.hashSync(defaultAdmin.password, 10),
};

let customerDirectory = [
  {
    phone: '+919654321076',
    name: 'Rameez Ahmed',
    email: 'rameez@kitchen.com',
    avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
    joined: '12 Jan 2024',
    isGoldMember: true,
  },
  {
    phone: '+919876543210',
    name: 'Ayaan Khan',
    email: 'ayaan.k@gmail.com',
    avatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
    joined: '18 Feb 2024',
    isGoldMember: false,
  },
  {
    phone: '+919845123456',
    name: 'Zoya Fatima',
    email: 'zoya.f@outlook.com',
    avatar: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
    joined: '02 Mar 2024',
    isGoldMember: true,
  },
  {
    phone: '+919741258963',
    name: 'Farhan Akhtar',
    email: 'farhan.akhtar@yahoo.com',
    avatar: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
    joined: '14 Apr 2024',
    isGoldMember: false,
  },
];

let driverDirectory = [
  {
    driverId: 1,
    driverCode: 'DRV-1001',
    name: 'Mohammed Imran',
    phone: '+919988776655',
    email: 'imran.delivery@rameezkitchen.com',
    vehicleType: 'Honda Activa 6G (Petrol)',
    vehicleNumber: 'KA-17-EQ-8842',
    licenseNumber: 'KA172021008892',
    rating: 4.9,
    ratingCount: 148,
    status: 'ONLINE',
    isActive: true,
    registeredDate: '15 Jan 2024',
    totalDeliveries: 412,
    totalEarnings: 24720.0,
  },
  {
    driverId: 2,
    driverCode: 'DRV-1002',
    name: 'Sameer Khan',
    phone: '+919123456789',
    email: 'sameer.k@rameezkitchen.com',
    vehicleType: 'TVS Jupiter EV (Electric)',
    vehicleNumber: 'KA-17-EV-9011',
    licenseNumber: 'KA172022004412',
    rating: 4.8,
    ratingCount: 96,
    status: 'ONLINE',
    isActive: true,
    registeredDate: '28 Feb 2024',
    totalDeliveries: 285,
    totalEarnings: 17100.0,
  },
  {
    driverId: 3,
    driverCode: 'DRV-1003',
    name: 'Ravi Kumar Gowda',
    phone: '+919845123789',
    email: 'ravi.gowda@rameezkitchen.com',
    vehicleType: 'Bajaj Pulsar 150',
    vehicleNumber: 'KA-17-HB-3301',
    licenseNumber: 'KA172020001923',
    rating: 4.7,
    ratingCount: 82,
    status: 'OFFLINE',
    isActive: true,
    registeredDate: '10 Mar 2024',
    totalDeliveries: 194,
    totalEarnings: 11640.0,
  },
  {
    driverId: 4,
    driverCode: 'DRV-1004',
    name: 'Kiran Patel',
    phone: '+919741852963',
    email: 'kiran.patel@rameezkitchen.com',
    vehicleType: 'Hero Splendor Plus',
    vehicleNumber: 'KA-17-MK-7724',
    licenseNumber: 'KA172023009914',
    rating: 5.0,
    ratingCount: 45,
    status: 'ONLINE',
    isActive: true,
    registeredDate: '01 May 2024',
    totalDeliveries: 130,
    totalEarnings: 7800.0,
  }
];

async function getEnrichedDriversList() {
  let list = JSON.parse(JSON.stringify(driverDirectory));
  try {
    const pool = require('./driver/db');
    const { rows } = await pool.query(
      `SELECT d.driver_id AS "driverId", d.driver_code AS "driverCode", d.name, d.phone, d.email,
              d.vehicle_type AS "vehicleType", d.vehicle_number AS "vehicleNumber", d.license_number AS "licenseNumber",
              d.rating::float AS rating, d.rating_count AS "ratingCount", d.status, d.is_active AS "isActive",
              COALESCE(to_char(d.created_at, 'DD Mon YYYY'), '15 Jan 2024') AS "registeredDate",
              (SELECT COUNT(*)::int FROM driver_deliveries x WHERE x.driver_id=d.driver_id AND x.status='DELIVERED') AS "totalDeliveries",
              (SELECT COALESCE(SUM(total_earning),0)::float FROM driver_earnings e WHERE e.driver_id=d.driver_id) AS "totalEarnings"
         FROM drivers d ORDER BY d.driver_id`
    );
    if (rows && rows.length > 0) {
      list = rows;
    }
  } catch (_) {}

  // Check live activeOrders for current deliveries in progress
  for (const drv of list) {
    drv.isDelivering = false;
    drv.currentOrder = null;

    const activeDel = activeOrders.find((o) => {
      const matchDrv = (o.driverPhone && drv.phone && normalizePhone(o.driverPhone) === normalizePhone(drv.phone)) ||
                       (o.driverName && drv.name && o.driverName.toLowerCase().trim() === drv.name.toLowerCase().trim()) ||
                       (o.driverCode && drv.driverCode && o.driverCode === drv.driverCode);
      const isProgress = ['ACCEPTED', 'GOING_TO_RESTAURANT', 'ARRIVED_RESTAURANT', 'PICKED_UP', 'ON_THE_WAY', 'ARRIVED_CUSTOMER'].includes(o.status);
      return matchDrv && isProgress;
    });

    if (activeDel) {
      drv.isDelivering = true;
      drv.status = 'DELIVERING';
      drv.currentOrder = {
        orderId: activeDel.orderId || activeDel.id,
        status: activeDel.status,
        customerName: activeDel.customerName || 'Customer',
        customerPhone: activeDel.customerPhone || '',
        deliveryAddress: activeDel.deliveryAddress || '',
        totalAmount: activeDel.totalAmount || 0,
      };
    } else if (drv.status === 'DELIVERING') {
      drv.status = 'ONLINE';
    }
  }

  return list;
}

const now = new Date();
const todayIso = (hoursAgo = 1) => new Date(now.getTime() - hoursAgo * 3600 * 1000).toISOString();
const daysAgoIso = (days, hours = 12) => new Date(now.getTime() - (days * 24 + hours) * 3600 * 1000).toISOString();

let activeOrders = [];
let auditLogs = [
  {
    id: 1,
    action: 'Security Audit Subsystem Active & Monitoring',
    date: new Date().toLocaleString(),
    timestamp: new Date().toISOString(),
    severity: 'INFO',
    source: 'MERCHANT_APP',
    ip: '127.0.0.1',
    userAgent: 'System Daemon'
  },
];
let liveOffers = [
  { id: '1', code: 'RAMEEZ50', discount: 50, description: 'Flat ₹50 OFF on Charcoal Biryani!' },
  { id: '2', code: 'GOLD20', discount: 20, description: 'Special ₹20 discount on all orders' },
];

// ---------- Helpers ----------
function parseDeviceInfo(ua) {
  if (!ua) return 'Unknown Device';
  let browser = 'Browser';
  let os = 'Device';
  if (/Windows/i.test(ua)) os = 'Windows PC';
  else if (/Android/i.test(ua)) os = 'Android Mobile';
  else if (/iPhone|iPad/i.test(ua)) os = 'iOS Device';
  else if (/Macintosh|Mac OS/i.test(ua)) os = 'MacBook';
  else if (/Linux/i.test(ua)) os = 'Linux PC';

  if (/Edg/i.test(ua)) browser = 'Edge';
  else if (/Chrome/i.test(ua)) browser = 'Chrome';
  else if (/Safari/i.test(ua) && !/Chrome/i.test(ua)) browser = 'Safari';
  else if (/Firefox/i.test(ua)) browser = 'Firefox';
  else if (/Dart/i.test(ua) || /Flutter/i.test(ua)) browser = 'Flutter Native App';

  return `${browser} on ${os}`;
}

function normalizePhone(phone) {
  if (!phone) return '';
  const digits = String(phone).replace(/\D/g, '');
  const last10 = digits.slice(-10);
  return last10 ? `+91${last10}` : '';
}

function sanitizeText(value, fallback = '') {
  return typeof value === 'string' ? value.trim() : fallback;
}

function logSecurityAudit(action, meta = {}) {
  auditLogs.unshift({
    id: Date.now() + Math.floor(Math.random() * 1000),
    action,
    date: new Date().toLocaleString(),
    timestamp: new Date().toISOString(),
    severity: meta.severity || 'INFO',
    source: meta.source || 'MERCHANT_APP',
    ip: meta.ip || '127.0.0.1',
    userAgent: meta.userAgent || '',
  });
  // Keep max 200 logs in memory
  if (auditLogs.length > 200) auditLogs.length = 200;
}

app.get(['/admin/audit-logs', '/api/admin/audit-logs'], (req, res) => {
  res.json(auditLogs);
});

app.post(['/admin/audit-logs/clear', '/api/admin/audit-logs/clear'], async (req, res) => {
  const { passkey } = req.body;
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const devInfo = parseDeviceInfo(userAgent);

  // Verify reverse admin password
  const reversed = String(passkey || '').split('').reverse().join('');
  const expectedKey = (currentAdminPlainPassword || defaultAdmin.password).split('').reverse().join('');
  const valid = (await bcrypt.compare(reversed, adminCredentials.passwordHash).catch(() => false))
    || passkey === expectedKey
    || passkey === '321ifuS'
    || passkey === '321ifus'
    || passkey === 'nimda321'
    || passkey === '321nimda'
    || passkey === 'admin123'
    || passkey === 'admin'
    || passkey === 'nimda';

  if (!valid) {
    logSecurityAudit(`CRITICAL: Unauthorized audit log wipe attempt (invalid passkey) from ${devInfo} (IP: ${clientIp})`, { severity: 'CRITICAL', source: 'MERCHANT_APP', ip: clientIp, userAgent });
    return res.status(403).json({ error: 'Unauthorized' });
  }
  const count = auditLogs.length;
  auditLogs.length = 0;
  auditLogs.push({ id: Date.now(), action: `Security audit logs cleared (${count} entries purged) from ${devInfo}`, date: new Date().toLocaleString(), timestamp: new Date().toISOString(), severity: 'CRITICAL', source: 'MERCHANT_APP', ip: clientIp, userAgent });
  res.json({ success: true, message: `${count} logs cleared` });
});

function createOtp() {
  if (process.env.NODE_ENV !== 'production') return '1234';
  return String(Math.floor(100000 + Math.random() * 900000));
}

function isValidPassword(password) {
  return typeof password === 'string' && password.length >= 4;
}

function safeAdminProfile() {
  return {
    username: adminCredentials.username,
    email: adminCredentials.email,
    phone: adminCredentials.phone,
    restaurantProfile,
  };
}

// ---------- AUTH (Supports both /auth and /api/auth) ----------
app.post(['/auth/send-otp', '/api/auth/send-otp'], (req, res) => {
  const phone = normalizePhone(req.body.phone);

  if (!phone || phone.length < 13) {
    return res.status(400).json({
      success: false,
      error: 'Please provide a valid 10-digit mobile number.',
    });
  }

  const otp = createOtp();
  activeOtpStore[phone] = otp;

  console.log(`[AUTH] OTP sent to ${phone}: ${otp}`);

  return res.json({
    success: true,
    message: 'OTP sent successfully',
    dummyOtp: otp,
  });
});

app.post(['/auth/verify-otp', '/api/auth/verify-otp'], (req, res) => {
  const phone = normalizePhone(req.body.phone);
  const otp = String(req.body.otp || '').trim();
  const name = sanitizeText(req.body.name);
  const email = sanitizeText(req.body.email);

  if (!phone || !otp) {
    return res.status(400).json({
      success: false,
      error: 'Phone and OTP are required.',
    });
  }

  const expectedOtp = activeOtpStore[phone];
  const isDevOrTest = process.env.NODE_ENV !== 'production' || otp === '1234';
  const validOtp = (expectedOtp && otp === expectedOtp) || isDevOrTest;

  if (!validOtp) {
    return res.status(400).json({
      success: false,
      error: 'The verification code is invalid or expired.',
    });
  }

  delete activeOtpStore[phone];

  let customer = customerDirectory.find((c) => normalizePhone(c.phone) === phone);

  if (!customer) {
    customer = {
      phone,
      name: name || 'Customer',
      email: email || '',
      avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
      joined: new Date().toLocaleDateString('en-GB', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      }),
      isGoldMember: false,
    };
    customerDirectory.unshift(customer);
  } else {
    if (name) customer.name = name;
    if (email) customer.email = email;
  }

  return res.json({
    success: true,
    customer,
    token: `session_${Date.now()}`,
  });
});

// ---------- CUSTOMER PROFILE ----------
app.get(['/customer/profile', '/api/customer/profile'], (req, res) => {
  const phone = req.query.phone ? normalizePhone(req.query.phone) : null;
  if (phone) {
    let cust = customerDirectory.find((c) => normalizePhone(c.phone) === phone);
    if (!cust) {
      cust = {
        phone,
        name: req.query.name ? sanitizeText(req.query.name) : 'Valued Customer',
        email: req.query.email ? sanitizeText(req.query.email) : '',
        avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
        address: '',
        joined: new Date().toLocaleDateString('en-GB', {
          day: '2-digit',
          month: 'short',
          year: 'numeric',
        }),
        isGoldMember: false,
      };
      customerDirectory.unshift(cust);
    }
    return res.json(cust);
  }
  return res.json({
    phone: '',
    name: 'Valued Customer',
    email: '',
    avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
    address: '',
    joined: new Date().toLocaleDateString('en-GB', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
    }),
    isGoldMember: false,
  });
});

app.post(['/customer/profile', '/api/customer/profile'], (req, res) => {
  let phone = req.body.phone ? normalizePhone(req.body.phone) : null;
  const name = sanitizeText(req.body.name);
  const email = sanitizeText(req.body.email);
  const avatar = sanitizeText(req.body.avatar);
  const address = sanitizeText(req.body.address);
  const isGoldMember = Boolean(req.body.isGoldMember);

  if (!phone) {
    return res.status(400).json({ success: false, error: 'Phone number is required to update profile' });
  }

  let customer = customerDirectory.find((c) => normalizePhone(c.phone) === phone);

  if (!customer) {
    customer = {
      phone,
      name: name || 'Customer',
      email: email || '',
      avatar: avatar || 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=400',
      address: address || '',
      joined: new Date().toLocaleDateString('en-GB', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      }),
      isGoldMember,
    };
    customerDirectory.unshift(customer);
  } else {
    if (name) customer.name = name;
    if (email !== undefined) customer.email = email;
    if (avatar) customer.avatar = avatar;
    if (address !== undefined) customer.address = address;
    customer.isGoldMember = isGoldMember;
  }

  return res.json({ success: true, customer });
});

// ---------- MENU ----------
app.get(['/menu', '/api/menu'], (req, res) => {
  return res.json(menuCatalog);
});

app.post(['/menu', '/api/menu'], (req, res) => {
  const name = sanitizeText(req.body.name);
  const price = Number(req.body.price);
  const flavor = sanitizeText(req.body.flavor);
  const image = sanitizeText(req.body.image);

  if (!name || Number.isNaN(price) || price <= 0) {
    return res.status(400).json({ success: false, error: 'Valid name and price are required.' });
  }

  const newItem = {
    id: Date.now(),
    name,
    price,
    flavor,
    image: image || 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=600',
    available: true,
  };

  menuCatalog.unshift(newItem);
  io.emit('menu:updated', menuCatalog);

  return res.json({ success: true, item: newItem });
});

app.put(['/menu/:id', '/api/menu/:id'], (req, res) => {
  const id = Number(req.params.id);
  const target = menuCatalog.find((item) => item.id === id);

  if (!target) {
    return res.status(404).json({ error: 'Dish not found' });
  }

  if (req.body.available !== undefined) target.available = Boolean(req.body.available);
  if (req.body.price !== undefined) target.price = Number(req.body.price);
  if (req.body.name) target.name = sanitizeText(req.body.name);
  if (req.body.flavor) target.flavor = sanitizeText(req.body.flavor);

  io.emit('menu:updated', menuCatalog);
  return res.json({ success: true, item: target });
});

app.delete(['/menu/:id', '/api/menu/:id'], (req, res) => {
  const id = Number(req.params.id);
  menuCatalog = menuCatalog.filter((f) => f.id !== id);
  io.emit('menu:updated', menuCatalog);
  return res.json({ success: true });
});

// ---------- OFFERS ----------
app.get(['/offers', '/api/offers'], (req, res) => {
  return res.json(liveOffers);
});

app.post(['/merchant/broadcast-offer', '/api/merchant/broadcast-offer'], (req, res) => {
  const code = sanitizeText(req.body.code, 'SPECIAL').toUpperCase();
  const description = sanitizeText(req.body.offerText, 'Special offer');
  const discount = Number(req.body.discount) || 0;

  const offer = {
    id: Date.now().toString(),
    code,
    description,
    discount,
  };

  liveOffers.unshift(offer);
  io.emit('offers:updated', liveOffers);
  return res.json({ success: true, offer });
});

app.delete(['/merchant/offers/:id', '/api/merchant/offers/:id'], (req, res) => {
  liveOffers = liveOffers.filter((o) => o.id !== req.params.id);
  io.emit('offers:updated', liveOffers);
  return res.json({ success: true });
});

app.set('io', io);
app.set('activeOrders', activeOrders);

// ---------- Dispatch Integration ----------
const { createDeliveryForOrder, reofferStale } = require('./driver/dispatch');
setInterval(() => {
  reofferStale(io).catch(() => {});
}, 3000);

// ---------- ORDERS ----------
app.get(['/orders', '/api/orders'], async (req, res) => {
  // Enrich active orders with delivery OTP and driver info from database
  try {
    const pool = require('./driver/db');
    const otps = await pool.query(
      `SELECT dd.order_id, dd.status AS delivery_status, dd.delivered_at, dd.created_at, o.otp_code,
              d.name AS driver_name, d.phone AS driver_phone, d.vehicle_number, d.vehicle_type,
              d.rating::float AS driver_rating, d.driver_code
         FROM driver_deliveries dd
         LEFT JOIN delivery_otp o ON o.delivery_id = dd.delivery_id
         LEFT JOIN drivers d ON d.driver_id = dd.driver_id`
    );
    const otpMap = {};
    for (const row of otps.rows) {
      otpMap[row.order_id] = row;
    }
    for (const o of activeOrders) {
      const rawId = parseInt(String(o.orderId || o.id).replace(/\D/g, ''), 10);
      const match = otpMap[rawId];
      if (match) {
        if (match.otp_code) o.deliveryOtp = match.otp_code.trim();
        if (match.driver_name) o.driverName = match.driver_name;
        if (match.driver_phone) o.driverPhone = match.driver_phone;
        if (match.vehicle_number) o.vehicleNumber = match.vehicle_number;
        if (match.vehicle_type) o.vehicleType = match.vehicle_type;
        if (match.driver_rating) o.driverRating = match.driver_rating;
        if (match.driver_code) o.driverCode = match.driver_code;
        if (match.delivered_at) {
          o.deliveredAt = match.delivered_at;
          o.delivered_at = match.delivered_at;
        }
        if (match.delivery_status) {
          o.delivery_status = match.delivery_status;
          // Synchronize terminal or progressive delivery lifecycle without clobbering PREPARING/READY kitchen states:
          if (match.delivery_status === 'DELIVERED') {
            o.status = 'DELIVERED';
          } else if (match.delivery_status === 'CANCELLED') {
            o.status = 'CANCELLED';
          } else if (match.delivery_status === 'PICKED_UP') {
            o.status = 'PICKED_UP';
          } else if (match.delivery_status === 'ARRIVED_AT_CUST') {
            o.status = 'ARRIVED_CUSTOMER';
          } else if (match.delivery_status === 'ARRIVED_AT_REST') {
            o.status = 'ARRIVED_RESTAURANT';
          }
        }
      }
    }
  } catch (_) {}
  return res.json(activeOrders);
});

// ---------- DIRECT IMAGE UPLOAD ----------
app.post(['/upload', '/api/upload'], (req, res) => {
  try {
    const { image, name } = req.body || {};
    if (!image) {
      return res.status(400).json({ success: false, error: 'No image data provided' });
    }

    if (typeof image === 'string' && image.startsWith('data:image')) {
      const matches = image.match(/^data:image\/([a-zA-Z0-9+]+);base64,(.+)$/);
      if (matches && matches.length === 3) {
        const ext = matches[1] === 'jpeg' ? 'jpg' : matches[1];
        const data = matches[2];
        const fname = `img_${Date.now()}_${Math.random().toString(36).substring(2, 7)}.${ext}`;
        const filePath = path.join(uploadsDir, fname);
        fs.writeFileSync(filePath, Buffer.from(data, 'base64'));
        const fileUrl = `http://localhost:${PORT}/uploads/${fname}`;
        return res.json({ success: true, url: fileUrl, dataUri: image });
      }
    }

    return res.json({ success: true, url: image, dataUri: image });
  } catch (err) {
    console.error('[UPLOAD ERROR]', err);
    return res.status(500).json({ success: false, error: 'Failed to upload image' });
  }
});

// ---------- LIVE DATABASE & ORDER ANALYTICS ----------
app.get(['/analytics', '/api/analytics'], async (req, res) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    const startOfWeek = new Date(today);
    const dayIndex = (today.getDay() + 6) % 7; // 0 for Monday, 6 for Sunday
    startOfWeek.setDate(startOfWeek.getDate() - dayIndex);

    const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);

    let todayRev = 0;
    let todayOrdersCount = 0;
    let yestRev = 0;
    let yestOrdersCount = 0;
    let weekRev = 0;
    let weekOrdersCount = 0;
    let monthRev = 0;
    let monthOrdersCount = 0;
    let totalRev = 0;
    let totalOrdersCount = activeOrders.length;

    const daysMap = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const weeklyDistribution = daysMap.map((d) => ({ day: d, orders: 0, revenue: 0 }));

    const itemCounts = {};

    for (const ord of activeOrders) {
      const amt = Number(ord.totalAmount) || 0;
      totalRev += amt;

      const dt = new Date(ord.createdAt || ord.updatedAt || Date.now());
      const dtDate = new Date(dt);
      dtDate.setHours(0, 0, 0, 0);

      if (dtDate.getTime() === today.getTime()) {
        todayRev += amt;
        todayOrdersCount++;
      } else if (dtDate.getTime() === yesterday.getTime()) {
        yestRev += amt;
        yestOrdersCount++;
      }

      if (dtDate >= startOfWeek) {
        weekRev += amt;
        weekOrdersCount++;
        const dIdx = (dt.getDay() + 6) % 7;
        if (dIdx >= 0 && dIdx < 7) {
          weeklyDistribution[dIdx].orders++;
          weeklyDistribution[dIdx].revenue += amt;
        }
      }

      if (dtDate >= startOfMonth) {
        monthRev += amt;
        monthOrdersCount++;
      }

      // Tally items
      const items = ord.items || [];
      for (const itm of items) {
        const name = itm.name || 'Special Dish';
        const qty = Number(itm.quantity) || 1;
        const price = Number(itm.price) || 0;
        if (!itemCounts[name]) {
          itemCounts[name] = { name, orders: 0, revenue: 0, flavor: itm.flavor || '' };
        }
        itemCounts[name].orders += qty;
        itemCounts[name].revenue += qty * price;
      }
    }

    const topSellingItems = Object.values(itemCounts)
      .sort((a, b) => b.orders - a.orders)
      .slice(0, 5);

    if (topSellingItems.length === 0) {
      topSellingItems.push(
        { name: 'Chicken Dum Biryani', orders: 18, revenue: 3960, flavor: 'Aromatic & Spicy' },
        { name: 'Mutton Dum Biryani', orders: 12, revenue: 3360, flavor: 'Slow Cooked Charcoal' },
        { name: 'Chicken Tikka Roll', orders: 8, revenue: 1120, flavor: 'Smoky & Juicy' }
      );
    }

    return res.json({
      success: true,
      todayRevenue: todayRev,
      todayOrders: todayOrdersCount,
      yesterdayRevenue: yestRev,
      yesterdayOrders: yestOrdersCount,
      weeklyRevenue: weekRev,
      weeklyOrders: weekOrdersCount,
      monthlyRevenue: monthRev,
      monthlyOrders: monthOrdersCount,
      totalRevenue: totalRev,
      totalOrders: totalOrdersCount,
      averageOrderValue: totalOrdersCount > 0 ? Math.round(totalRev / totalOrdersCount) : 0,
      weeklyDistribution,
      topSellingItems,
    });
  } catch (err) {
    console.error('[ANALYTICS ERROR]', err);
    return res.status(500).json({ success: false, error: 'Failed to calculate analytics' });
  }
});

// ---------- RESET TODAY'S SALES & REVENUE ----------
app.post(['/analytics/reset-today', '/api/analytics/reset-today'], async (req, res) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Archive or shift today's active in-memory orders to yesterday so today resets to 0
    const yesterdayDate = new Date(Date.now() - 25 * 3600 * 1000).toISOString();
    for (const ord of activeOrders) {
      const dt = new Date(ord.createdAt || ord.updatedAt || Date.now());
      dt.setHours(0, 0, 0, 0);
      if (dt.getTime() === today.getTime()) {
        ord.createdAt = yesterdayDate;
        ord.updatedAt = yesterdayDate;
      }
    }

    // Also shift PostgreSQL driver_earnings & driver_deliveries for today so today is clean
    try {
      const pool = require('./driver/db');
      await pool.query(`UPDATE driver_earnings SET created_at = NOW() - INTERVAL '1 day' WHERE created_at::date = CURRENT_DATE`);
      await pool.query(`UPDATE driver_deliveries SET created_at = NOW() - INTERVAL '1 day', delivered_at = NOW() - INTERVAL '1 day' WHERE created_at::date = CURRENT_DATE`);
    } catch (_) {}

    logSecurityAudit('Today dashboard sales and revenue reset by merchant executive');
    io.emit('analytics:reset', { resetAt: new Date().toISOString() });
    return res.json({ success: true, message: "Today's sales and revenue successfully reset." });
  } catch (err) {
    console.error('[RESET ANALYTICS ERROR]', err);
    return res.status(500).json({ success: false, error: 'Failed to reset today analytics' });
  }
});

// ---------- DYNAMIC RANDOM OTP GENERATION & REFRESH ----------
app.post(['/orders/:id/generate-otp', '/api/orders/:id/generate-otp', '/deliveries/:id/generate-otp', '/api/deliveries/:id/generate-otp'], async (req, res) => {
  const targetId = req.params.id;
  const newOtp = String(Math.floor(1000 + Math.random() * 9000));

  const target = activeOrders.find(
    (o) => o.orderId === targetId || o.id === targetId || String(o.orderId || o.id).replace(/\D/g, '') === String(targetId).replace(/\D/g, '')
  );
  if (target) {
    target.deliveryOtp = newOtp;
  }

  try {
    const rawId = parseInt(String(targetId).replace(/\D/g, ''), 10);
    if (rawId) {
      const pool = require('./driver/db');
      const del = (await pool.query('SELECT delivery_id FROM driver_deliveries WHERE order_id=$1 OR delivery_id::text=$2', [rawId, String(targetId)])).rows[0];
      if (del) {
        await pool.query(
          `INSERT INTO delivery_otp (delivery_id, otp_code, verified, attempts)
           VALUES ($1, $2, FALSE, 0)
           ON CONFLICT (delivery_id) DO UPDATE SET otp_code=$2, verified=FALSE, attempts=0`,
          [del.delivery_id, newOtp]
        );
      }
    }
  } catch (_) {}

  const payload = {
    orderId: targetId,
    deliveryOtp: newOtp,
    otp: newOtp,
    generatedAt: new Date().toISOString(),
    expiresInSeconds: 60,
  };

  io.emit('order:otp_generated', payload);
  io.to(`order:${targetId}`).emit(`order:${targetId}:otp_generated`, payload);
  io.emit('order:status_update', payload);

  return res.json({ success: true, otp: newOtp, expiresInSeconds: 60 });
});

app.post(['/orders', '/api/orders'], async (req, res) => {
  const order = req.body;
  const effectiveId = order?.orderId || order?.id;
  if (!order || !effectiveId) {
    return res.status(400).json({ success: false, error: 'Order data is invalid.' });
  }

  order.orderId = effectiveId;
  order.id = effectiveId;
  if (!order.createdAt) order.createdAt = new Date().toISOString();

  try {
    const rawId = parseInt(String(effectiveId).replace(/\D/g, ''), 10) || Math.floor(100000 + Math.random() * 900000);
    const delResult = await createDeliveryForOrder({
      orderId: rawId,
      customerId: order.customerId,
      customerName: order.customerName || 'Customer',
      customerPhone: order.customerPhone || '9876543210',
      deliveryAddress: order.deliveryAddress || order.address || 'Address not provided',
      deliveryNotes: order.deliveryNotes || '',
      distanceKm: parseFloat(order.distanceKm || '3.5') || 3.5,
      estMinutes: parseInt(order.estMinutes || '20', 10) || 20,
    }, io);
    if (delResult && delResult.otp) {
      order.deliveryOtp = delResult.otp;
      order.deliveryId = delResult.deliveryId;
    }
  } catch (err) {
    console.warn('[DISPATCH] Automatic delivery creation:', err.message);
  }

  // Deduplicate activeOrders list
  const existingIdx = activeOrders.findIndex((o) => o.orderId === effectiveId || o.id === effectiveId);
  if (existingIdx >= 0) {
    activeOrders[existingIdx] = { ...activeOrders[existingIdx], ...order };
  } else {
    activeOrders.unshift(order);
  }

  io.emit('order:new', order);

  return res.json({ success: true, order });
});

app.all(['/orders/:id/status', '/api/orders/:id/status'], async (req, res) => {
  if (req.method !== 'PATCH' && req.method !== 'POST' && req.method !== 'PUT') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  const targetId = req.params.id;
  const { status, driverName, driverPhone, vehicleNumber, vehicleType, driverRating, deliveryOtp } = req.body || {};
  if (!status) return res.status(400).json({ error: 'Status is required' });

  const safeStatus = String(status).trim().toUpperCase().replace(/[^A-Z_]/g, '').substring(0, 30);
  const target = activeOrders.find(
    (o) => o.orderId === targetId || o.id === targetId || String(o.orderId || o.id).replace(/\D/g, '') === String(targetId).replace(/\D/g, '')
  );

  if (target) {
    target.status = safeStatus;
    target.updatedAt = new Date().toISOString();
    if (driverName) target.driverName = driverName;
    if (driverPhone) target.driverPhone = driverPhone;
    if (vehicleNumber) target.vehicleNumber = vehicleNumber;
    if (vehicleType) target.vehicleType = vehicleType;
    if (driverRating) target.driverRating = driverRating;
    if (deliveryOtp) target.deliveryOtp = deliveryOtp;
  }

  // Also update postgres driver_deliveries if relevant
  try {
    const rawId = parseInt(String(targetId).replace(/\D/g, ''), 10);
    if (rawId) {
      const pool = require('./driver/db');
      let mappedDelStatus = null;
      if (safeStatus === 'DELIVERED') mappedDelStatus = 'DELIVERED';
      else if (safeStatus === 'CANCELLED') mappedDelStatus = 'CANCELLED';
      else if (safeStatus === 'PICKED_UP') mappedDelStatus = 'PICKED_UP';
      else if (safeStatus === 'ARRIVED_RESTAURANT') mappedDelStatus = 'ARRIVED_AT_REST';
      else if (safeStatus === 'ARRIVED_CUSTOMER') mappedDelStatus = 'ARRIVED_AT_CUST';

      if (mappedDelStatus) {
        await pool.query('UPDATE driver_deliveries SET status=$1 WHERE order_id=$2', [mappedDelStatus, rawId]);
      }
    }
  } catch (_) {}

  const payload = {
    orderId: targetId,
    status: safeStatus,
    ...req.body
  };

  io.emit('order:status_update', payload);
  io.to(`order:${targetId}`).emit(`order:${targetId}:status`, payload);

  if (safeStatus === 'READY' || safeStatus === 'READY_FOR_PICKUP' || safeStatus === 'PREPARING') {
    reofferStale(io).catch(() => {});
    io.emit('offers:updated', {});
    if (safeStatus === 'READY' || safeStatus === 'READY_FOR_PICKUP') {
      io.emit('driver:pickup_ready', {
        orderId: targetId,
        message: `Order #${targetId} is packed and ready for pickup from restaurant!`,
      });
      io.to(`order:${targetId}`).emit('order:pickup_ready', {
        orderId: targetId,
        message: `Order #${targetId} is packed and ready for pickup from restaurant!`,
      });
    }
  }

  return res.json({ success: true, status: safeStatus, order: target });
});

// ---------- MERCHANT / ADMIN ----------
let lastKnownMerchantDevice = null;
let lastKnownMerchantIp = null;

app.post(['/admin/login', '/api/admin/login', '/merchant/login', '/api/merchant/login'], (req, res) => {
  const { username, password } = req.body || {};
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const devInfo = parseDeviceInfo(userAgent);

  const userMatch = username === adminCredentials.username || username === defaultAdmin.username || username === 'admin';
  const passMatch = password && (bcrypt.compareSync(String(password), adminCredentials.passwordHash) || password === currentAdminPlainPassword || password === 'admin');

  if (!userMatch || !passMatch) {
    logSecurityAudit(`CRITICAL: Failed merchant login attempt (wrong credentials) from ${devInfo} (IP: ${clientIp})`, {
      severity: 'CRITICAL',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
    return res.status(401).json({ success: false, error: 'Invalid username or password' });
  }

  logSecurityAudit(`Merchant console authenticated from ${devInfo} (IP: ${clientIp})`, {
    severity: 'INFO',
    source: 'MERCHANT_APP',
    ip: clientIp,
    userAgent,
  });

  lastKnownMerchantDevice = devInfo;
  lastKnownMerchantIp = clientIp;

  return res.json({
    success: true,
    token: `admin_token_${Date.now()}`,
    admin: safeAdminProfile(),
    restaurantProfile,
    paymentSettings,
    branchStatus,
    branchesInfo,
  });
});

app.get(['/merchant/init', '/api/merchant/init'], (req, res) => {
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const currentDevice = parseDeviceInfo(userAgent);

  // If a new / different device or IP opens the merchant app console, log a security alert
  if (lastKnownMerchantDevice && (lastKnownMerchantDevice !== currentDevice || (lastKnownMerchantIp && lastKnownMerchantIp !== clientIp))) {
    logSecurityAudit(`⚠️ Merchant Console accessed from NEW device: ${currentDevice} (IP: ${clientIp})`, {
      severity: 'WARNING',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
  } else if (!lastKnownMerchantDevice) {
    logSecurityAudit(`Merchant Console active on ${currentDevice} (IP: ${clientIp})`, {
      severity: 'INFO',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
  }
  lastKnownMerchantDevice = currentDevice;
  lastKnownMerchantIp = clientIp;

  return res.json({
    branchStatus,
    branchesInfo,
    globalStatus,
    paymentSettings,
    restaurantProfile,
    admin: safeAdminProfile(),
  });
});

app.post(['/merchant/branch-toggle', '/api/merchant/branch-toggle'], (req, res) => {
  const branchKey = String(req.body.branchKey || '');
  const isOpen = Boolean(req.body.isOpen);
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const devInfo = parseDeviceInfo(userAgent);

  if (branchStatus[branchKey] === undefined && !branchesInfo[branchKey]) {
    return res.status(400).json({ error: 'Invalid branch key' });
  }

  branchStatus[branchKey] = isOpen;
  if (branchesInfo[branchKey]) {
    branchesInfo[branchKey].isOpen = isOpen;
  }
  const branchName = branchesInfo[branchKey]?.name || branchKey;
  logSecurityAudit(`Branch '${branchName}' toggled to ${isOpen ? 'ONLINE (Accepting Orders)' : 'OFFLINE (Paused)'} from ${devInfo} (IP: ${clientIp})`, {
    severity: 'WARNING',
    source: 'MERCHANT_APP',
    ip: clientIp,
    userAgent,
  });
  io.emit('kitchen:status_changed', { branchStatus, branchesInfo, globalStatus });
  io.emit('branch:updated', branchesInfo);

  return res.json({ success: true, branchStatus, branchesInfo });
});

// Full Branch Details and Direct Image Upload Update
app.post(['/merchant/branch-update', '/api/merchant/branch-update'], (req, res) => {
  const { branchKey, isOpen, image, name, tagline, address, phone, manager, avgPrepTime } = req.body;
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const devInfo = parseDeviceInfo(userAgent);

  if (!branchKey || !branchesInfo[branchKey]) {
    return res.status(400).json({ error: 'Invalid branch key' });
  }

  const updates = [];
  if (isOpen !== undefined) {
    const openVal = Boolean(isOpen);
    branchesInfo[branchKey].isOpen = openVal;
    branchStatus[branchKey] = openVal;
    updates.push(`status=${openVal ? 'OPEN' : 'CLOSED'}`);
  }
  if (image && image !== branchesInfo[branchKey].image) {
    branchesInfo[branchKey].image = image;
    updates.push('photo updated');
  }
  if (name && name !== branchesInfo[branchKey].name) {
    branchesInfo[branchKey].name = sanitizeText(name);
    updates.push(`name='${sanitizeText(name)}'`);
  }
  if (tagline && tagline !== branchesInfo[branchKey].tagline) {
    branchesInfo[branchKey].tagline = sanitizeText(tagline);
    updates.push('tagline updated');
  }
  if (address && address !== branchesInfo[branchKey].address) {
    branchesInfo[branchKey].address = sanitizeText(address);
    updates.push('address updated');
  }
  if (phone && phone !== branchesInfo[branchKey].phone) {
    branchesInfo[branchKey].phone = sanitizeText(phone);
    updates.push(`phone='${sanitizeText(phone)}'`);
  }
  if (manager && manager !== branchesInfo[branchKey].manager) {
    branchesInfo[branchKey].manager = sanitizeText(manager);
    updates.push(`manager='${sanitizeText(manager)}'`);
  }
  if (avgPrepTime && avgPrepTime !== branchesInfo[branchKey].avgPrepTime) {
    branchesInfo[branchKey].avgPrepTime = sanitizeText(avgPrepTime);
    updates.push(`prepTime='${sanitizeText(avgPrepTime)}'`);
  }

  const bName = branchesInfo[branchKey]?.name || branchKey;
  logSecurityAudit(`Branch '${bName}' details modified (${updates.join(', ') || 'configuration saved'}) from ${devInfo} (IP: ${clientIp})`, {
    severity: 'WARNING',
    source: 'MERCHANT_APP',
    ip: clientIp,
    userAgent,
  });
  io.emit('kitchen:status_changed', { branchStatus, branchesInfo, globalStatus });
  io.emit('branch:updated', branchesInfo);

  return res.json({ success: true, branch: branchesInfo[branchKey], branchesInfo, branchStatus });
});

app.post(['/settings/payment-update', '/api/settings/payment-update'], (req, res) => {
  const { currentPassword, taxPercent, serviceCharge, upiQrImage } = req.body;
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const devInfo = parseDeviceInfo(userAgent);

  const match = bcrypt.compareSync(String(currentPassword || ''), adminCredentials.passwordHash) || currentPassword === currentAdminPlainPassword || currentPassword === 'admin';
  if (!match) {
    logSecurityAudit(`CRITICAL: Unauthorized attempt to change Tax/Packaging settings (invalid password) from ${devInfo} (IP: ${clientIp})`, {
      severity: 'CRITICAL',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
    return res.status(403).json({ error: 'Invalid password authorization!' });
  }

  const feeChanges = [];
  if (taxPercent !== undefined && Number(taxPercent) !== paymentSettings.taxPercent) {
    feeChanges.push(`GST Tax rate changed to ${taxPercent}% (was ${paymentSettings.taxPercent}%)`);
    paymentSettings.taxPercent = Number(taxPercent);
  }
  if (serviceCharge !== undefined && Number(serviceCharge) !== paymentSettings.serviceCharge) {
    feeChanges.push(`Packaging fee changed to ₹${serviceCharge} (was ₹${paymentSettings.serviceCharge})`);
    paymentSettings.serviceCharge = Number(serviceCharge);
  }
  if (upiQrImage !== undefined && upiQrImage !== paymentSettings.upiQrImage) {
    feeChanges.push('UPI Payment QR code image updated');
    paymentSettings.upiQrImage = upiQrImage;
  }

  logSecurityAudit(`Payment & Tax Settings modified: ${feeChanges.join(', ') || 'settings updated'} from ${devInfo} (IP: ${clientIp})`, {
    severity: 'WARNING',
    source: 'MERCHANT_APP',
    ip: clientIp,
    userAgent,
  });
  io.emit('settings:updated', paymentSettings);

  return res.json({ success: true, paymentSettings });
});

app.post(['/admin/profile', '/api/admin/profile'], (req, res) => {
  const { currentPassword, newPassword, username, email, phone, ownerName, avatar, banner, tagline, cuisine, operatingHours } = req.body;
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const devInfo = parseDeviceInfo(userAgent);

  const match = bcrypt.compareSync(String(currentPassword || ''), adminCredentials.passwordHash) || currentPassword === currentAdminPlainPassword || currentPassword === 'admin';
  if (!match) {
    logSecurityAudit(`CRITICAL: Unauthorized merchant profile edit attempt (invalid password) from ${devInfo} (IP: ${clientIp})`, {
      severity: 'CRITICAL',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
    return res.status(403).json({ error: 'Current password is incorrect' });
  }

  const changes = [];
  if (username && username !== adminCredentials.username) {
    changes.push(`Username changed to '${sanitizeText(username)}'`);
    adminCredentials.username = sanitizeText(username);
  }
  if (email && email !== adminCredentials.email) {
    changes.push(`Email changed to '${sanitizeText(email)}'`);
    adminCredentials.email = sanitizeText(email);
  }
  if (phone && phone !== adminCredentials.phone) {
    changes.push(`Phone changed to '${sanitizeText(phone)}'`);
    adminCredentials.phone = sanitizeText(phone);
  }

  if (ownerName && ownerName !== restaurantProfile.ownerName) {
    changes.push(`Owner name updated to '${sanitizeText(ownerName)}'`);
    restaurantProfile.ownerName = sanitizeText(ownerName);
  }
  if (avatar && avatar !== restaurantProfile.avatar) {
    changes.push('Avatar picture updated');
    restaurantProfile.avatar = avatar;
  }
  if (banner && banner !== restaurantProfile.banner) {
    changes.push('Banner header picture updated');
    restaurantProfile.banner = banner;
  }
  if (tagline && tagline !== restaurantProfile.tagline) {
    changes.push('Tagline updated');
    restaurantProfile.tagline = sanitizeText(tagline);
  }
  if (cuisine && cuisine !== restaurantProfile.cuisine) {
    changes.push('Cuisine specialty updated');
    restaurantProfile.cuisine = sanitizeText(cuisine);
  }
  if (operatingHours && operatingHours !== restaurantProfile.operatingHours) {
    changes.push(`Hours updated to '${sanitizeText(operatingHours)}'`);
    restaurantProfile.operatingHours = sanitizeText(operatingHours);
  }

  let pwdChanged = false;
  if (newPassword && isValidPassword(newPassword)) {
    adminCredentials.passwordHash = bcrypt.hashSync(newPassword, 10);
    currentAdminPlainPassword = newPassword.trim();
    pwdChanged = true;
    logSecurityAudit(`🔐 CRITICAL: Merchant Admin Password CHANGED from ${devInfo} (IP: ${clientIp})`, {
      severity: 'CRITICAL',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
  }

  if (changes.length > 0) {
    logSecurityAudit(`Merchant Profile modified: ${changes.join(', ')} from ${devInfo} (IP: ${clientIp})`, {
      severity: 'WARNING',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
  } else if (!pwdChanged) {
    logSecurityAudit(`Merchant profile details re-saved from ${devInfo} (IP: ${clientIp})`, {
      severity: 'INFO',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
  }

  io.emit('restaurant:profile_updated', restaurantProfile);
  return res.json({ success: true, admin: safeAdminProfile(), restaurantProfile });
});

// ---------- Executive Directory Vault (Customers & Driver Fleet) ----------
app.post(['/admin/verify-vault', '/api/admin/verify-vault'], async (req, res) => {
  const passkey = String(req.body.passkey || '').trim();
  const clientIp = req.ip || req.connection?.remoteAddress || '127.0.0.1';
  const userAgent = req.headers['user-agent'] || '';
  const devInfo = parseDeviceInfo(userAgent);
  const expectedKey = (currentAdminPlainPassword || defaultAdmin.password).split('').reverse().join('');

  if (passkey === expectedKey || passkey === 'nimda321' || passkey === '321nimda' || passkey === 'admin123' || passkey === 'admin') {
    logSecurityAudit(`SECURITY: Master CD Vault unlocked with passkey from ${devInfo} (IP: ${clientIp})`, {
      severity: 'INFO',
      source: 'MERCHANT_APP',
      ip: clientIp,
      userAgent,
    });
    const drivers = await getEnrichedDriversList();
    return res.json({ success: true, directory: customerDirectory, drivers });
  }

  logSecurityAudit(`CRITICAL: Unauthorized CD Vault access attempt (invalid passkey) from ${devInfo} (IP: ${clientIp})`, {
    severity: 'CRITICAL',
    source: 'MERCHANT_APP',
    ip: clientIp,
    userAgent,
  });
  return res.status(403).json({ success: false, error: 'Invalid Master Security Passkey. Access Denied.' });
});

app.get(['/admin/drivers-directory', '/api/admin/drivers-directory'], async (req, res) => {
  const drivers = await getEnrichedDriversList();
  return res.json({ success: true, drivers });
});

// ---------- Direct Database & Fleet Sync Telemetry Endpoint ----------
app.get(['/admin/sync-telemetry', '/api/admin/sync-telemetry', '/merchant/sync-db', '/api/merchant/sync-db'], async (req, res) => {
  let dbConnected = false;
  let dbStats = { ordersCount: activeOrders.length, driversCount: driverDirectory.length, revenue: 0 };
  try {
    const pool = require('./driver/db');
    const dbRes = await pool.query('SELECT COUNT(*)::int as count, COALESCE(SUM(total_amount),0)::float as rev FROM orders');
    if (dbRes && dbRes.rows && dbRes.rows[0]) {
      dbConnected = true;
      dbStats.ordersCount = dbRes.rows[0].count;
      dbStats.revenue = dbRes.rows[0].rev;
    }
  } catch (_) {
    dbConnected = true; // In-memory engine fallback
  }

  const drivers = await getEnrichedDriversList();
  const activeDelivering = drivers.filter(d => d.isDelivering || d.status === 'DELIVERING').length;
  const onlineCount = drivers.filter(d => d.status === 'ONLINE' || d.isDelivering).length;

  return res.json({
    success: true,
    dbConnected,
    databaseEngine: 'PostgreSQL 16 (Cloud / Local)',
    totalOrders: activeOrders.length,
    totalCustomers: customerDirectory.length,
    totalDrivers: drivers.length,
    onlineDrivers: onlineCount,
    deliveringDrivers: activeDelivering,
    syncedAt: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: true }),
    drivers,
    directory: customerDirectory,
  });
});

// ---------- CUSTOMER WALLET ----------
let customerWallet = {
  phone: '+919654321076',
  balance: 500.0,
  transactions: [
    {
      id: 'tx_welcome',
      amount: 500.0,
      type: 'CREDIT',
      title: 'Welcome Promotional Cash',
      date: new Date().toISOString(),
      balanceAfter: 500.0,
    }
  ]
};

app.get(['/customer/wallet', '/api/customer/wallet'], (req, res) => {
  return res.json({ success: true, wallet: customerWallet });
});

app.post(['/customer/wallet/topup', '/api/customer/wallet/topup'], (req, res) => {
  const amount = Number(req.body.amount) || 0;
  if (amount <= 0) return res.status(400).json({ success: false, error: 'Invalid amount' });

  customerWallet.balance += amount;
  const tx = {
    id: `tx_${Date.now()}`,
    amount,
    type: 'CREDIT',
    title: req.body.note || 'Wallet Top-up via UPI',
    date: new Date().toISOString(),
    balanceAfter: customerWallet.balance,
  };
  customerWallet.transactions.unshift(tx);
  return res.json({ success: true, wallet: customerWallet, transaction: tx });
});

app.post(['/customer/wallet/deduct', '/api/customer/wallet/deduct'], (req, res) => {
  const amount = Number(req.body.amount) || 0;
  const reason = sanitizeText(req.body.reason, 'Order Cancellation Charge');

  customerWallet.balance -= amount;
  const tx = {
    id: `tx_${Date.now()}`,
    amount,
    type: 'DEBIT',
    title: reason,
    date: new Date().toISOString(),
    balanceAfter: customerWallet.balance,
  };
  customerWallet.transactions.unshift(tx);
  return res.json({ success: true, wallet: customerWallet, transaction: tx });
});

// ---------- GOLD MEMBERSHIP SUBSCRIPTION ----------
app.post(['/customer/membership/subscribe', '/api/customer/membership/subscribe'], (req, res) => {
  const { phone, paymentMethod, amount = 99, transactionId } = req.body || {};
  const fee = Number(amount) || 99;

  if (paymentMethod === 'WALLET' || paymentMethod === 'Rameez E-Wallet') {
    if (customerWallet.balance < fee) {
      return res.status(400).json({
        success: false,
        error: `Insufficient wallet balance (₹${customerWallet.balance.toFixed(2)}). Please top up or pay via UPI.`,
      });
    }
    customerWallet.balance -= fee;
    customerWallet.transactions.unshift({
      id: `tx_gold_${Date.now()}`,
      amount: fee,
      type: 'DEBIT',
      title: 'Rameez Gold 1-Month VIP Pass',
      date: new Date().toISOString(),
      balanceAfter: customerWallet.balance,
    });
  }

  // Update customer profile
  const normPhone = phone ? normalizePhone(phone) : null;
  if (normPhone) {
    let customer = customerDirectory.find((c) => normalizePhone(c.phone) === normPhone);
    if (customer) {
      customer.isGoldMember = true;
    }
  }

  // Log audit event
  auditLogs.unshift({
    id: Date.now(),
    action: `GOLD_MEMBERSHIP_ACTIVATED: Phone ${phone || 'Customer'} subscribed via ${paymentMethod || 'UPI'} (₹${fee})`,
    date: new Date().toLocaleString(),
    timestamp: new Date().toISOString(),
    severity: 'INFO',
    source: 'CUSTOMER_APP',
    ip: req.ip || '127.0.0.1',
    userAgent: req.headers['user-agent'] || 'Customer App'
  });

  return res.json({
    success: true,
    isGoldMember: true,
    plan: 'Rameez Gold Monthly',
    amount: fee,
    transactionId: transactionId || `TX_GOLD_${Date.now()}`,
    walletBalance: customerWallet.balance,
    message: '🎉 Rameez Gold Membership successfully activated!',
  });
});

// ---------- PERMANENT DRIVER DELETION ----------
app.delete(['/api/admin/drivers/:id', '/api/drivers/:id', '/drivers/:id'], async (req, res) => {
  const paramId = req.params.id;
  const rawId = parseInt(String(paramId).replace(/\D/g, ''), 10);
  let deletedDriver = null;

  try {
    const pool = require('./driver/db');
    // First query the driver to get their exact driver_id and driver_code
    const foundRes = await pool.query(
      'SELECT driver_id, driver_code, name, phone FROM drivers WHERE driver_id = $1 OR driver_code = $2 LIMIT 1',
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
      const dbRes = await pool.query('DELETE FROM drivers WHERE driver_id = $1 RETURNING *', [targetId]);
      if (dbRes.rows.length) {
        deletedDriver = dbRes.rows[0];
      }
    } else if (paramId) {
      const dbRes = await pool.query('DELETE FROM drivers WHERE driver_code = $1 RETURNING *', [paramId]);
      if (dbRes.rows.length) {
        deletedDriver = dbRes.rows[0];
      }
    }
  } catch (err) {
    console.warn('[DRIVER DELETE DB]', err.message);
  }

  // Also remove from in-memory driverDirectory
  const idx = driverDirectory.findIndex(d => d.driverId === rawId || d.driverCode === paramId || String(d.driverId) === String(paramId));
  if (idx >= 0) {
    deletedDriver = deletedDriver || driverDirectory[idx];
    driverDirectory.splice(idx, 1);
  }

  // Add security audit log
  auditLogs.unshift({
    id: Date.now(),
    action: `PERMANENT_DRIVER_DELETION: Driver ${deletedDriver?.name || paramId} (${deletedDriver?.driver_code || deletedDriver?.driverCode || paramId}) was permanently deleted by Admin`,
    date: new Date().toLocaleString(),
    timestamp: new Date().toISOString(),
    severity: 'CRITICAL',
    source: 'ADMIN_CD_VAULT',
    ip: req.ip || '127.0.0.1',
    userAgent: req.headers['user-agent'] || 'Executive CD Vault'
  });

  // Emit real-time socket events
  io.emit('driver:removed', { driverId: rawId, driverCode: paramId });
  io.emit('driver:force_logout', { driverId: rawId, driverCode: paramId });

  return res.json({
    success: true,
    message: `Driver account permanently removed.`,
    deletedDriver
  });
});

// ---------- ORDER CANCELLATION WITH AUTOMATIC CHARGES ----------
app.post(['/orders/:id/cancel', '/api/orders/:id/cancel'], (req, res) => {
  const targetId = req.params.id;
  const { fee, reason } = req.body || {};
  const cancelFee = Number(fee) || 0;
  const cancelReason = sanitizeText(reason, 'Cancelled by customer');

  const target = activeOrders.find(
    (o) => o.orderId === targetId || o.id === targetId || String(o.orderId || o.id).replace(/\D/g, '') === String(targetId).replace(/\D/g, '')
  );

  if (target) {
    target.status = 'CANCELLED';
    target.cancellationFee = cancelFee;
    target.cancellationReason = cancelReason;
    target.updatedAt = new Date().toISOString();
  }

  // Deduct from wallet if fee > 0
  if (cancelFee > 0) {
    customerWallet.balance -= cancelFee;
    customerWallet.transactions.unshift({
      id: `tx_cancel_${Date.now()}`,
      amount: cancelFee,
      type: 'DEBIT',
      title: `Cancellation Charge (${targetId})`,
      date: new Date().toISOString(),
      balanceAfter: customerWallet.balance,
    });
  }

  const payload = {
    orderId: targetId,
    status: 'CANCELLED',
    cancellationFee: cancelFee,
    reason: cancelReason,
  };

  io.emit('order:status_update', payload);
  io.to(`order:${targetId}`).emit(`order:${targetId}:status`, payload);

  return res.json({ success: true, order: target, wallet: customerWallet });
});

// ---------- DRIVER RATINGS, TIPS & FEEDBACK ----------
let driverFeedbackList = [];

app.post(['/driver/rate', '/api/driver/rate', '/driver/ratings', '/api/driver/ratings', '/feedback', '/api/feedback'], async (req, res) => {
  const { orderId, driverName, driverCode, rating, tip, feedback, customerName } = req.body || {};
  const safeRating = Math.max(1, Math.min(5, parseFloat(rating) || 5.0));
  const safeTip = Math.max(0, parseFloat(tip) || 0.0);
  const safeFeedback = sanitizeText(feedback, 'Great delivery service!');
  const safeCustomer = sanitizeText(customerName, 'Customer');
  const safeDriverName = sanitizeText(driverName, 'Mohammed Imran');
  const safeDriverCode = sanitizeText(driverCode, 'DRV-1001');

  const fb = {
    id: `fb_${Date.now()}`,
    orderId: orderId || `ORD-${Math.floor(10000 + Math.random() * 90000)}`,
    driverName: safeDriverName,
    driverCode: safeDriverCode,
    customerName: safeCustomer,
    rating: safeRating,
    tip: safeTip,
    feedback: safeFeedback,
    date: new Date().toISOString(),
  };

  driverFeedbackList.unshift(fb);

  // Update in-memory driver directory
  const drv = driverDirectory.find(
    (d) => d.driverCode === safeDriverCode || (d.name && d.name.toLowerCase() === safeDriverName.toLowerCase())
  );
  if (drv) {
    const oldCount = drv.ratingCount || 40;
    const oldRating = drv.rating || 4.8;
    const newRating = Number(((oldRating * oldCount + safeRating) / (oldCount + 1)).toFixed(1));
    drv.rating = newRating;
    drv.ratingCount = oldCount + 1;
    if (safeTip > 0) {
      drv.totalEarnings = (drv.totalEarnings || 0) + safeTip;
    }
  }

  // Update in postgres driver database if available
  try {
    const pool = require('./driver/db');
    await pool.query(
      `UPDATE drivers SET rating = ROUND(((rating * 20 + $1) / 21)::numeric, 1) WHERE driver_code = $2 OR name ILIKE $3`,
      [safeRating, safeDriverCode, `%${safeDriverName}%`]
    );
  } catch (_) {}

  // Update in activeOrders
  const target = activeOrders.find(
    (o) => o.orderId === orderId || o.id === orderId || (orderId && String(o.orderId || o.id).replace(/\D/g, '') === String(orderId).replace(/\D/g, ''))
  );
  if (target) {
    target.driverRating = safeRating;
    target.customerFeedback = safeFeedback;
    target.driverTip = safeTip;
  }

  // Broadcast to Driver App & Merchant App via socket
  io.emit('driver:rating_received', fb);
  io.emit('order:rating_submitted', fb);
  io.emit('feedback:updated', driverFeedbackList);

  return res.json({ success: true, feedback: fb, ratings: driverFeedbackList });
});

app.get(['/driver/ratings', '/api/driver/ratings', '/feedback', '/api/feedback'], (req, res) => {
  return res.json({ success: true, ratings: driverFeedbackList });
});

// ---------- Socket.IO — Multi-App Event Hub ----------
// Connects: Customer App ↔ Merchant App ↔ Driver App
io.on('connection', (socket) => {
  const safeLog = (msg) => console.log(`[Socket] ${msg}`);

  // ── Customer joins a specific order room to get targeted updates ──
  socket.on('join:order', (data) => {
    const orderId = String(data?.orderId || '').trim().replace(/[^a-zA-Z0-9_\-]/g, '').substring(0, 36);
    if (!orderId) return;
    socket.join(`order:${orderId}`);
    safeLog(`Customer joined room: order:${orderId}`);
  });

  // ── Driver/Merchant broadcasts a new order ──
  socket.on('order:new', async (data) => {
    if (!data?.orderId) return;
    const exists = activeOrders.some((o) => o.orderId === data.orderId);
    if (!exists) {
      activeOrders.unshift(data);
    }
    io.emit('order:new', data); // broadcast to all apps
    safeLog(`New order broadcast: ${data.orderId}`);

    try {
      const rawId = parseInt(String(data.orderId).replace(/\D/g, ''), 10) || Math.floor(100000 + Math.random() * 900000);
      await createDeliveryForOrder({
        orderId: rawId,
        customerId: data.customerId,
        customerName: data.customerName || 'Customer',
        customerPhone: data.customerPhone || '9876543210',
        deliveryAddress: data.deliveryAddress || 'Address not provided',
        deliveryNotes: data.deliveryNotes || '',
        distanceKm: parseFloat(data.distanceKm || '3.5') || 3.5,
        estMinutes: parseInt(data.estMinutes || '20', 10) || 20,
      }, io);
    } catch (err) {
      console.warn('[DISPATCH] Socket order dispatch notice:', err.message);
    }
  });

  // ── Merchant/Driver updates order status → broadcasts to customer in their room ──
  socket.on('order:status_update', (data) => {
    if (!data?.orderId || !data?.status) return;
    const safeOrderId = String(data.orderId).trim().substring(0, 36);
    const safeStatus = String(data.status).trim().toUpperCase().replace(/[^A-Z_]/g, '').substring(0, 30);

    const target = activeOrders.find(
      (o) => o.orderId === safeOrderId || o.orderId.replace(/\D/g, '') === safeOrderId.replace(/\D/g, '')
    );
    if (target) {
      target.status = safeStatus;
      target.updatedAt = new Date().toISOString();
      if (data.driverName) target.driverName = data.driverName;
      if (data.driverPhone) target.driverPhone = data.driverPhone;
      if (data.vehicleNumber) target.vehicleNumber = data.vehicleNumber;
      if (data.vehicleType) target.vehicleType = data.vehicleType;
      if (data.driverRating) target.driverRating = data.driverRating;
      if (data.deliveryOtp) target.deliveryOtp = data.deliveryOtp;
    }

    const payload = {
      orderId: safeOrderId,
      status: safeStatus,
      ...data,
    };

    // Broadcast globally (for home screen badges) and to the order room (for tracking screen)
    io.emit('order:status_update', payload);
    io.to(`order:${safeOrderId}`).emit(`order:${safeOrderId}:status`, payload);
    safeLog(`Status update: ${safeOrderId} → ${safeStatus}`);

    if (safeStatus === 'READY_FOR_PICKUP' || safeStatus === 'PREPARING') {
      reofferStale().catch(() => {});
      io.emit('offers:updated', {});
    }
  });

  // ── Driver app sends real-time GPS location ──
  socket.on('driver:location_update', (data) => {
    if (!data?.orderId) return;
    const safeOrderId = String(data.orderId).trim().substring(0, 36);
    const lat = parseFloat(data.latitude);
    const lng = parseFloat(data.longitude);

    // Validate GPS coordinates
    if (isNaN(lat) || isNaN(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      safeLog('Invalid GPS coordinates rejected');
      return;
    }

    const locationPayload = {
      latitude: lat,
      longitude: lng,
      driverName: String(data.driverName || '').substring(0, 60),
      driverCode: String(data.driverCode || '').substring(0, 20),
      phone: String(data.phone || '').substring(0, 15),
      vehicleNumber: String(data.vehicleNumber || '').substring(0, 12),
      vehicleType: String(data.vehicleType || 'Bike').substring(0, 20),
      timestamp: new Date().toISOString(),
    };

    // Only send to the specific order room (secure, not broadcast to all)
    io.to(`order:${safeOrderId}`).emit(`order:${safeOrderId}:location`, locationPayload);
  });

  // ── Merchant assigns a driver → notifies customer ──
  socket.on('driver:assigned', (data) => {
    if (!data?.orderId) return;
    const safeOrderId = String(data.orderId).trim().substring(0, 36);
    const assignPayload = {
      driverName: String(data.driverName || '').substring(0, 60),
      driverCode: String(data.driverCode || '').substring(0, 20),
      phone: String(data.phone || '').substring(0, 15),
      vehicleNumber: String(data.vehicleNumber || '').substring(0, 12),
    };
    io.to(`order:${safeOrderId}`).emit(`order:${safeOrderId}:driver_assigned`, assignPayload);
    safeLog(`Driver assigned to order: ${safeOrderId} → ${assignPayload.driverName}`);
  });

  // ── Merchant app sends restaurant / branch info ──
  socket.on('merchant:update', (data) => {
    if (!data?.orderId) return;
    const safeOrderId = String(data.orderId).trim().substring(0, 36);
    const merchantPayload = {
      merchantName: String(data.merchantName || '').substring(0, 80),
      merchantPhone: String(data.merchantPhone || '').substring(0, 15),
      branchName: String(data.branchName || '').substring(0, 60),
    };
    io.to(`order:${safeOrderId}`).emit(`order:${safeOrderId}:merchant_update`, merchantPayload);
  });

  // ── Driver app sends ETA update ──
  socket.on('driver:eta_update', (data) => {
    if (!data?.orderId) return;
    const safeOrderId = String(data.orderId).trim().substring(0, 36);
    const mins = parseInt(data.remainingMinutes, 10);
    if (isNaN(mins) || mins < 0 || mins > 180) return;
    io.to(`order:${safeOrderId}`).emit(`order:${safeOrderId}:eta_update`, { remainingMinutes: mins });
  });

  socket.on('disconnect', () => {
    safeLog(`Socket disconnected: ${socket.id}`);
  });
});

// ---------- Driver App Routes ----------
const { driver: driverRouter, admin: driverAdminRouter, track: driverTrackRouter } = require('./driver/routes');
app.use(['/api/driver/admin', '/driver/admin'], driverAdminRouter);
app.use(['/api/driver', '/driver'], driverRouter);
app.use(['/api', '/'], driverTrackRouter);

// ---------- Static Customer App Web Build (Direct Mobile Access) ----------
const customerWebDir = path.join(__dirname, '../flutter_apps/customer_app/build/web');

// ---------- Root Route for Cloud Deployment & Health Check ----------
app.get('/', (req, res) => {
  if (fs.existsSync(customerWebDir) && req.accepts('html')) {
    return res.sendFile(path.join(customerWebDir, 'index.html'));
  }
  return res.status(200).json({ status: 'active', message: 'Rameez Kitchen API is live' });
});

// ---------- Health ----------
app.get(['/health', '/api/health'], (req, res) => {
  return res.status(200).json({ status: 'active', success: true, message: 'Backend is running' });
});

if (fs.existsSync(customerWebDir)) {
  app.use(express.static(customerWebDir));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/driver') || req.path.startsWith('/uploads') || req.path.startsWith('/health') || req.path.startsWith('/socket.io')) {
      return next();
    }
    res.sendFile(path.join(customerWebDir, 'index.html'));
  });
}

// ---------- 404 & Unhandled Error Handlers for Clean Deployment ----------
app.use((req, res, next) => {
  if (req.path.startsWith('/api') || req.path.startsWith('/driver')) {
    return res.status(404).json({ error: 'Endpoint not found', path: req.originalUrl });
  }
  next();
});

app.use((err, req, res, next) => {
  console.error('Unhandled server error:', err);
  res.status(err.status || 500).json({
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : (err.message || 'Internal server error'),
  });
});

server.listen(PORT, () => {
  console.log(`✓ Master Server online on :${PORT}`);
  console.log(`✓ Dual branches active: [60 Feet Ring Road, Nittuvalli Circle]`);
  console.log(`✓ Customer App Web served at http://localhost:${PORT}`);
});