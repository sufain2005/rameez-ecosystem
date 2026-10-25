// 0-2 km = 20, 2-4 = 25, 4-6 = 30, 6-8 = 35, 8+ = 40
function calcBaseEarning(km) {
  const d = Number(km);
  if (d <= 2) return 20;
  if (d <= 4) return 25;
  if (d <= 6) return 30;
  if (d <= 8) return 35;
  return 40;
}
module.exports = { calcBaseEarning };