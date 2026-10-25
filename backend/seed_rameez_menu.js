const pool = require('./db.js');

async function setupAndSeed() {
  try {
    // 1. Ensure table has availability toggle, tags, and portion columns
    await pool.query(`
      CREATE TABLE IF NOT EXISTS menu_items (
        id SERIAL PRIMARY KEY,
        name VARCHAR(120) NOT NULL,
        category VARCHAR(60) NOT NULL,
        portion VARCHAR(50) DEFAULT 'Regular',
        price NUMERIC(10, 2) NOT NULL,
        description TEXT,
        image_url TEXT,
        tag VARCHAR(40) DEFAULT 'Popular',
        is_available BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Add is_available column if not already present
    await pool.query(`
      ALTER TABLE menu_items 
      ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT TRUE,
      ADD COLUMN IF NOT EXISTS tag VARCHAR(40) DEFAULT 'Popular',
      ADD COLUMN IF NOT EXISTS portion VARCHAR(50) DEFAULT 'Regular';
    `);

    // Clear old sample data
    await pool.query('TRUNCATE TABLE menu_items RESTART IDENTITY CASCADE;');

    // 2. Exact items & prices from Rameez Kitchen board with rich culinary photos
    const menu = [
      // Chicken Rolls
      { name: 'Shawarma Roll', category: 'Chicken Rolls', portion: 'Single', price: 60, tag: 'Bestseller', desc: 'Flame-roasted shredded chicken stuffed with creamy garlic mayo.', img: 'https://images.unsplash.com/photo-1561651823-34feb02250e4?auto=format&fit=crop&w=600&q=80' },
      { name: 'Full Chicken Roll', category: 'Chicken Rolls', portion: 'Regular', price: 120, tag: 'Must Try', desc: 'Loaded marinated chicken chunks rolled in flaky paratha.', img: 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?auto=format&fit=crop&w=600&q=80' },
      { name: 'Plate Shawarma', category: 'Chicken Rolls', portion: 'Full Plate', price: 150, tag: 'Chef Special', desc: 'Generous portion of carved chicken meat served with kuboos and dip.', img: 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=600&q=80' },
      { name: 'Extra Mayonnaise', category: 'Chicken Rolls', portion: 'Dip', price: 20, tag: 'Add-on', desc: 'Signature thick garlic mayo.', img: 'https://images.unsplash.com/photo-1585238342024-78d387f4a707?auto=format&fit=crop&w=600&q=80' },

      // Soups
      { name: 'Chicken Manchow Soup (Half)', category: 'Soups', portion: 'Half Bowl', price: 40, tag: 'Spicy', desc: 'Spicy, tangy Indo-Chinese soup topped with crispy noodles.', img: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=600&q=80' },
      { name: 'Chicken Manchow Soup (Full)', category: 'Soups', portion: 'Full Bowl', price: 60, tag: 'Spicy', desc: 'Hearty, steaming bowl loaded with chicken shreds and pepper.', img: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=600&q=80' },

      // Tandoori Specials
      { name: 'Tandoori Chicken (Quarter)', category: 'Tandoori', portion: 'Quarter', price: 150, tag: 'Smoky & Spicy', desc: 'Charcoal-grilled chicken marinated in spiced curd and red chili.', img: 'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?auto=format&fit=crop&w=600&q=80' },
      { name: 'Tandoori Chicken (Full)', category: 'Tandoori', portion: 'Full Bird', price: 500, tag: 'Party Choice', desc: 'Whole tandoor roasted bird cooked to tender perfection.', img: 'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?auto=format&fit=crop&w=600&q=80' },
      { name: 'Alfaham Chicken (Red/Yellow)', category: 'Tandoori', portion: 'Half', price: 260, tag: 'Arabian Delight', desc: 'Arabian barbecued chicken glazed with authentic Arabic spice blend.', img: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=600&q=80' },
      { name: 'Grill Chicken (Full)', category: 'Tandoori', portion: 'Full', price: 550, tag: 'Juicy', desc: 'Slow rotisserie grilled chicken with crisp outer skin.', img: 'https://images.unsplash.com/photo-1598103442097-8b74394b95c6?auto=format&fit=crop&w=600&q=80' },

      // Chicken Biryani Specials
      { name: 'Chicken Dum Biryani (Half)', category: 'Biryani Specials', portion: 'Half (500 gm)', price: 100, tag: 'Top Rated', desc: 'Flavourful long-grain basmati cooked on sealed dum with fragrant spices.', img: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?auto=format&fit=crop&w=600&q=80' },
      { name: 'Chicken Dum Biryani (Full)', category: 'Biryani Specials', portion: 'Full (1 kg)', price: 200, tag: 'Family Pack', desc: 'Classic Lucknowi/Hyderabadi style sealed pot biryani served with gravy.', img: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?auto=format&fit=crop&w=600&q=80' },
      { name: 'Lollipop Biryani (Half)', category: 'Biryani Specials', portion: 'Half (500 gm)', price: 140, tag: 'Crunchy & Spicy', desc: 'Aromatic dum rice paired with crisp, deep-fried chicken lollipops.', img: 'https://images.unsplash.com/photo-1589302168068-964664d93dc0?auto=format&fit=crop&w=600&q=80' },
      { name: 'Leg Piece Fried Biryani (Full)', category: 'Biryani Specials', portion: 'Full (1 kg)', price: 280, tag: 'Customer Favorite', desc: 'Rich spiced biryani rice garnished with crispy fried chicken drumsticks.', img: 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?auto=format&fit=crop&w=600&q=80' },
      { name: 'Kushka Biryani Rice', category: 'Biryani Specials', portion: 'Half (500 gm)', price: 70, tag: 'Classic', desc: 'Aromatic pure biryani rice without meat pieces.', img: 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?auto=format&fit=crop&w=600&q=80' },

      // Chicken Kabab Specials
      { name: 'Chicken Kabab (Quarter)', category: 'Kabab Specials', portion: 'Quarter (250 gm)', price: 120, tag: 'Extra Crispy', desc: 'Deep-fried chicken pieces infused with ginger, garlic, and hot red chillies.', img: 'https://images.unsplash.com/photo-1603894584373-5ac82b2ae398?auto=format&fit=crop&w=600&q=80' },
      { name: 'Pudina Kabab', category: 'Kabab Specials', portion: 'Quarter (250 gm)', price: 140, tag: 'Herbal Mint', desc: 'Succulent chicken marinated in freshly ground green mint and coriander.', img: 'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?auto=format&fit=crop&w=600&q=80' },
      { name: 'Chicken Lollipop', category: 'Kabab Specials', portion: 'Quarter (250 gm)', price: 150, tag: 'Hot Seller', desc: 'Frenched chicken winglets tossed in fiery Szechuan red seasoning.', img: 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?auto=format&fit=crop&w=600&q=80' }
    ];

    for (const item of menu) {
      await pool.query(
        `INSERT INTO menu_items (name, category, portion, price, description, image_url, tag, is_available)
         VALUES ($1, $2, $3, $4, $5, $6, $7, TRUE)`,
        [item.name, item.category, item.portion, item.price, item.desc, item.img, item.tag]
      );
    }

    console.log(`✓ Rameez Kitchen Menu seeded: ${menu.length} items with high-res photos & portions.`);
    process.exit(0);
  } catch (err) {
    console.error('Error seeding menu:', err);
    process.exit(1);
  }
}

setupAndSeed();