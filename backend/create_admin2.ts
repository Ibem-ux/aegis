import { buildApp } from './src/app';
import * as bcrypt from 'bcryptjs';

async function run() {
  const app = buildApp();
  await app.ready();

  const username = 'admin2';
  const displayName = 'Admin User 2';
  const password = 'password123';

  // Check if admin2 already exists
  const existing = await app.db.query("SELECT * FROM users WHERE username = $1", [username]);
  if (existing.rows.length > 0) {
    console.log(`User ${username} already exists! Re-hashing password.`);
    const hash = bcrypt.hashSync(password, 12);
    await app.db.query(
      "UPDATE users SET password_hash = $1, role = 'admin', status = 'ACTIVE' WHERE username = $2",
      [hash, username]
    );
    console.log(`Successfully updated password for ${username} to: ${password}`);
  } else {
    const hash = bcrypt.hashSync(password, 12);
    await app.db.query(
      "INSERT INTO users (username, display_name, password_hash, status, role) VALUES ($1, $2, $3, 'ACTIVE', 'admin')",
      [username, displayName, hash]
    );
    console.log(`Successfully created new admin user:`);
    console.log(`Username: ${username}`);
    console.log(`Password: ${password}`);
  }

  await app.close();
}

run().catch(err => {
  console.error("Failed to run seed script:", err);
});
