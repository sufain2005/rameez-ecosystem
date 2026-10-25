import 'menu_item.dart';

class CartItem {
  static const int maxQuantity = 20;

  final MenuItem item;
  int quantity;

  CartItem({required this.item, int quantity = 1})
      : quantity = quantity < 1 ? 1 : (quantity > maxQuantity ? maxQuantity : quantity);

  bool get canIncrease => quantity < maxQuantity;

  /// Rounded to 2 decimals to avoid floating-point drift (e.g. 199.99999).
  double get totalPrice => double.parse((item.price * quantity).toStringAsFixed(2));

  CartItem copyWith({int? quantity}) =>
      CartItem(item: item, quantity: quantity ?? this.quantity);

  /// Only IDs and quantities go to the server. The SERVER must look up prices
  /// and calculate the total, never trust a price sent from the app.
  Map<String, dynamic> toOrderJson() => {
        'menu_item_id': item.id,
        'quantity': quantity,
      };

  @override
  bool operator ==(Object other) => other is CartItem && other.item.id == item.id;

  @override
  int get hashCode => item.id.hashCode;
}