const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

const dbPath = path.resolve(__dirname, process.env.DATABASE_PATH || 'aegis.db');
if (fs.existsSync(dbPath)) {
  console.log('Migrating SQLite at', dbPath);
  const db = new Database(dbPath);
  try {
    db.exec('ALTER TABLE user_invite_links ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP');
    console.log('Migration applied to SQLite successfully.');
  } catch (e) {
    if (e.message.includes('duplicate column name')) {
      console.log('Migration already applied to SQLite.');
    } else {
      console.error('Error applying migration to SQLite:', e.message);
    }
  }
  db.close();
} else {
  console.log('SQLite database not found at', dbPath);
}
