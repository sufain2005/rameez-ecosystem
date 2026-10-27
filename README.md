# Rameez Kitchen 🍛

An online food ordering and delivery system for a two-branch restaurant in Davanagere. Customers order, the kitchen prepares, and delivery partners bring the food to the door, with live updates at every step.

Apps
- Customer app: browse the menu, apply offers, order, pay, and track delivery live
- Merchant app: manage orders, menu, offers, branches, drivers and analytics
- Driver app: accept deliveries, confirm with a customer OTP, and track earnings
- Backend: Node.js API with live updates and a PostgreSQL database

Built with
Flutter, Node.js, Express, Socket.IO, PostgreSQL

# Run it locally

```bash
# Backend
cd backend
npm install
cp .env.example .env   # then add your own values
npm run dev

# Any app (example: customer app)
cd flutter_apps/customer_app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000
```

The server runs on port 5000 and creates the database tables on first start.

## Note

Never commit your `.env` file. Use long, random values for all secrets.
