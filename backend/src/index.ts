import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';

dotenv.config();

import { db, DEMO_MODE } from './config/firebase.js';
import stationRoutes from './routes/station.js';
import paymentRoutes from './routes/payment.js';
import adminRoutes from './routes/admin.js';

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: '*', credentials: true }));
app.use(express.json({ limit: '1mb' }));

// Routes
app.use('/api/station', stationRoutes);
app.use('/api/payment', paymentRoutes);
app.use('/api/admin', adminRoutes);

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', demo: DEMO_MODE, timestamp: Date.now(), service: 'RUAXEAI' });
});

// Serve admin-web frontend in production
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fs from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const adminDist = join(__dirname, '../../admin-web/dist');
if (fs.existsSync(adminDist)) {
  app.use(express.static(adminDist));
  app.get('*', (_req, res) => {
    res.sendFile(join(adminDist, 'index.html'));
  });
  console.log('📂 Serving admin-web from', adminDist);
}

// Error handler
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ success: false, error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`🚗 RUAXEAI Backend running on port ${PORT}`);
  console.log(`   Mode: ${DEMO_MODE ? '🧪 DEMO' : '🟢 PRODUCTION'}`);
  if (DEMO_MODE) console.log(`   Admin: admin / demo123`);
});

export default app;
