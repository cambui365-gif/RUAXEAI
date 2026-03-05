/**
 * Admin Routes — Dashboard, Stations, Config, Reports
 */
import { Router, Request, Response } from 'express';
import { adminAuth } from '../middleware/auth.js';
import { db } from '../config/firebase.js';
import { COLLECTIONS } from '../config/constants.js';

const router = Router();

// --- Auth ---
router.post('/login', async (req: Request, res: Response) => {
  try {
    const { username, password } = req.body;
    const adminDoc = await db.collection(COLLECTIONS.ADMINS).doc(username).get();
    if (!adminDoc.exists) {
      res.status(401).json({ success: false, error: 'Invalid credentials' });
      return;
    }
    const admin = adminDoc.data();
    if (admin.passwordHash !== password || !admin.isActive) {
      res.status(401).json({ success: false, error: 'Invalid credentials' });
      return;
    }

    // Update last login
    await db.collection(COLLECTIONS.ADMINS).doc(username).update({ lastLogin: Date.now() });

    const token = Buffer.from(`${username}:${password}`).toString('base64');
    res.json({
      success: true,
      data: {
        token,
        admin: { id: admin.id, username: admin.username, name: admin.name, role: admin.role, stations: admin.stations },
      },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// All routes below require admin auth
router.use(adminAuth);

// --- Dashboard ---
router.get('/dashboard', async (req: Request, res: Response) => {
  try {
    const stationsSnap = await db.collection(COLLECTIONS.STATIONS).get();
    const stations = stationsSnap.docs.map((d: any) => d.data());

    // Filter by admin's accessible stations
    const myStations = req.admin!.role === 'OWNER'
      ? stations
      : stations.filter((s: any) => req.admin!.stations.includes(s.id));

    // Today's sessions
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const sessionsSnap = await db.collection(COLLECTIONS.SESSIONS)
      .where('startTime', '>=', todayStart.getTime())
      .get();

    let todayRevenue = 0;
    let todaySessions = 0;
    let totalMinutes = 0;
    const serviceBreakdown: Record<string, { count: number; minutes: number; revenue: number }> = {};

    sessionsSnap.forEach((doc: any) => {
      const s = doc.data();
      if (!myStations.find((st: any) => st.id === s.stationId)) return;
      todaySessions++;
      todayRevenue += s.totalUsed || 0;

      for (const usage of (s.serviceUsage || [])) {
        const mins = (usage.durationSeconds || 0) / 60;
        totalMinutes += mins;
        if (!serviceBreakdown[usage.serviceName]) {
          serviceBreakdown[usage.serviceName] = { count: 0, minutes: 0, revenue: 0 };
        }
        serviceBreakdown[usage.serviceName].count++;
        serviceBreakdown[usage.serviceName].minutes += mins;
        serviceBreakdown[usage.serviceName].revenue += usage.cost || 0;
      }
    });

    // Today's deposits
    const txSnap = await db.collection(COLLECTIONS.TRANSACTIONS)
      .where('timestamp', '>=', todayStart.getTime())
      .where('type', '==', 'DEPOSIT')
      .get();
    let todayDeposits = 0;
    txSnap.forEach((doc: any) => { todayDeposits += doc.data().amount || 0; });

    res.json({
      success: true,
      data: {
        stations: {
          total: myStations.length,
          online: myStations.filter((s: any) => s.status === 'ONLINE' || s.status === 'IN_USE').length,
          inUse: myStations.filter((s: any) => s.status === 'IN_USE').length,
          offline: myStations.filter((s: any) => s.status === 'OFFLINE' || s.status === 'MAINTENANCE').length,
        },
        today: {
          sessions: todaySessions,
          revenue: todayRevenue,
          deposits: todayDeposits,
          totalMinutes: Math.round(totalMinutes),
        },
        serviceBreakdown,
        stationList: myStations,
      },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Stations ---
router.get('/stations', async (req: Request, res: Response) => {
  try {
    const snap = await db.collection(COLLECTIONS.STATIONS).get();
    const stations = snap.docs.map((d: any) => d.data());
    const filtered = req.admin!.role === 'OWNER'
      ? stations
      : stations.filter((s: any) => req.admin!.stations.includes(s.id));
    res.json({ success: true, data: filtered });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/stations/:id', async (req: Request, res: Response) => {
  try {
    const doc = await db.collection(COLLECTIONS.STATIONS).doc(req.params.id).get();
    if (!doc.exists) { res.status(404).json({ success: false, error: 'Not found' }); return; }
    res.json({ success: true, data: doc.data() });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.post('/stations', async (req: Request, res: Response) => {
  try {
    const { id, name, location, tabletId, cameraUrl, imageUrl } = req.body;
    if (!id || !name) { res.status(400).json({ success: false, error: 'id and name required' }); return; }

    await db.collection(COLLECTIONS.STATIONS).doc(id).set({
      id, name, location: location || '', status: 'OFFLINE',
      tabletId: tabletId || '', esp32Status: 'OFFLINE',
      cameraUrl: cameraUrl || '', imageUrl: imageUrl || '',
      lastHeartbeat: 0,
      createdAt: Date.now(), updatedAt: Date.now(),
    });
    res.json({ success: true, message: 'Station created' });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.put('/stations/:id', async (req: Request, res: Response) => {
  try {
    await db.collection(COLLECTIONS.STATIONS).doc(req.params.id).update({ ...req.body, updatedAt: Date.now() });
    res.json({ success: true, message: 'Station updated' });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Sessions ---
router.get('/sessions', async (req: Request, res: Response) => {
  try {
    const stationId = req.query.stationId as string;
    const status = req.query.status as string;
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);

    let query: any = db.collection(COLLECTIONS.SESSIONS);
    if (stationId) query = query.where('stationId', '==', stationId);
    if (status) query = query.where('status', '==', status);
    query = query.orderBy('startTime', 'desc').limit(limit);

    const snap = await query.get();
    res.json({ success: true, data: snap.docs.map((d: any) => d.data()) });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Transactions ---
router.get('/transactions', async (req: Request, res: Response) => {
  try {
    const stationId = req.query.stationId as string;
    const type = req.query.type as string;
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 500);

    let query: any = db.collection(COLLECTIONS.TRANSACTIONS);
    if (stationId) query = query.where('stationId', '==', stationId);
    if (type) query = query.where('type', '==', type);
    query = query.orderBy('timestamp', 'desc').limit(limit);

    const snap = await query.get();
    res.json({ success: true, data: snap.docs.map((d: any) => d.data()) });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Services ---
router.get('/services', async (req: Request, res: Response) => {
  try {
    const snap = await db.collection(COLLECTIONS.SERVICES).get();
    res.json({ success: true, data: snap.docs.map((d: any) => ({ id: d.id, ...d.data() })) });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.put('/services/:id', async (req: Request, res: Response) => {
  try {
    await db.collection(COLLECTIONS.SERVICES).doc(req.params.id).update(req.body);
    res.json({ success: true, message: 'Service updated' });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Config ---
router.get('/config', async (_req: Request, res: Response) => {
  try {
    const doc = await db.collection(COLLECTIONS.CONFIG).doc('main').get();
    res.json({ success: true, data: doc.data() });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

router.put('/config', async (req: Request, res: Response) => {
  try {
    await db.collection(COLLECTIONS.CONFIG).doc('main').update(req.body);
    res.json({ success: true, message: 'Config updated' });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Station Logs ---
router.get('/stations/:id/logs', async (req: Request, res: Response) => {
  try {
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
    const snap = await db.collection(COLLECTIONS.STATION_LOGS)
      .where('stationId', '==', req.params.id)
      .orderBy('timestamp', 'desc')
      .limit(limit)
      .get();
    res.json({ success: true, data: snap.docs.map((d: any) => d.data()) });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Revenue Report ---
router.get('/reports/revenue', async (req: Request, res: Response) => {
  try {
    const days = parseInt(req.query.days as string) || 30;
    const startDate = Date.now() - days * 24 * 60 * 60 * 1000;

    const sessionsSnap = await db.collection(COLLECTIONS.SESSIONS)
      .where('startTime', '>=', startDate)
      .where('status', '==', 'COMPLETED')
      .get();

    const dailyData: Record<string, { revenue: number; sessions: number; deposits: number; minutes: number }> = {};

    sessionsSnap.forEach((doc: any) => {
      const s = doc.data();
      const date = new Date(s.startTime).toISOString().split('T')[0];
      if (!dailyData[date]) dailyData[date] = { revenue: 0, sessions: 0, deposits: 0, minutes: 0 };
      dailyData[date].revenue += s.totalUsed || 0;
      dailyData[date].sessions++;
      dailyData[date].deposits += s.totalDeposited || 0;
      const mins = (s.serviceUsage || []).reduce((sum: number, u: any) => sum + (u.durationSeconds || 0) / 60, 0);
      dailyData[date].minutes += mins;
    });

    res.json({ success: true, data: dailyData });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
