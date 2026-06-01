import { buildApp } from './src/app';

async function test() {
  const app = buildApp();
  await app.ready();
  
  // Find a user to test with
  const user = await app.db.query("SELECT * FROM users LIMIT 1");
  if (!user.rows || user.rows.length === 0) {
    console.log("No user found in database!");
    await app.close();
    return;
  }
  const userId = user.rows[0].id;
  console.log("Found user ID:", userId);

  // Generate a mock JWT for this user
  const token = app.jwt.sign({ userId, sessionId: 'test-session-id' });
  console.log("Generated test token");

  // Call /api/users/me
  const response = await app.inject({
    method: 'GET',
    url: '/api/users/me',
    headers: {
      Authorization: `Bearer ${token}`
    }
  });

  console.log("STATUS CODE:", response.statusCode);
  console.log("BODY:", response.body);
  
  await app.close();
}

test().catch(err => {
  console.error("DIAGNOSTIC ERROR:", err);
});
