/**
 * Database abstraction — uses demo in-memory DB or Firebase
 */
const DEMO_MODE = process.env.DEMO_MODE === 'true' || !process.env.FIREBASE_PROJECT_ID;

let db: any;

if (DEMO_MODE) {
  const { demoDB } = await import('./demoDb.js');
  db = demoDB;
  console.log('🧪 Running in DEMO MODE (in-memory database)');
} else {
  const admin = await import('firebase-admin');
  if (!admin.default.apps.length) {
    admin.default.initializeApp({
      credential: admin.default.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
      }),
    });
  }
  db = admin.default.firestore();
  console.log('🟢 Connected to Firebase Firestore');
}

export { db, DEMO_MODE };
