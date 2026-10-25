const ORDER_STATUS = {
  ACCEPTED: 'Driver Assigned',
  GOING_TO_RESTAURANT: 'Driver Assigned',
  ARRIVED_RESTAURANT: 'Driver Assigned',
  PICKED_UP: 'Picked Up',
  ON_THE_WAY: 'Out for Delivery',
  ARRIVED_CUSTOMER: 'Out for Delivery',
  OTP_VERIFIED: 'Out for Delivery',
  DELIVERED: 'Delivered',
};

const NEXT = {
  GOING_TO_RESTAURANT: 'ARRIVED_RESTAURANT',
  ARRIVED_RESTAURANT: 'PICKED_UP',
  PICKED_UP: 'ON_THE_WAY',
  ON_THE_WAY: 'ARRIVED_CUSTOMER',
};

module.exports = { ORDER_STATUS, NEXT };