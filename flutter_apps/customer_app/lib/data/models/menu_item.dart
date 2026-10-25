class MenuItem {
  final int id;
  final String name;
  final String category;
  final String portion;
  final double price;
  final String description;
  final String imageUrl;
  final String tag;
  final bool isAvailable;

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.portion,
    required this.price,
    required this.description,
    required this.imageUrl,
    required this.tag,
    required this.isAvailable,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'],
      name: json['name'] ?? '',
      category: json['category'] ?? 'General',
      portion: json['portion'] ?? 'Regular',
      price: double.tryParse(json['price'].toString()) ?? 0.0,
      description: json['description'] ?? '',
      imageUrl: json['image_url'] ?? 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=600&q=80',
      tag: json['tag'] ?? 'Hot',
      isAvailable: json['is_available'] ?? true,
    );
  }
}