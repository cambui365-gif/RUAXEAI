/**
 * Station Routes — Called by Tablet App
 * Auth: X-Station-ID + X-Tablet-ID headers
 */
import { Router, Request, Response } from 'express';
import { stationAuth } from '../middleware/auth.js';
import { db } from '../config/firebase.js';
import { COLLECTIONS } from '../config/constants.js';
import * as sessionService from '../services/sessionService.js';
import * as logService from '../services/logService.js';

const router = Router();
router.use(stationAuth);

// --- Station Info ---
router.get('/info', async (req: Request, res: Response) => {
  try {
    const stationDoc = await db.collection(COLLECTIONS.STATIONS).doc(req.stationId!).get();
    const station = stationDoc.data();

    // Get services
    const servicesSnap = await db.collection(COLLECTIONS.SERVICES).get();
    const services = servicesSnap.docs.map((d: any) => d.data()).sort((a: any, b: any) => a.sortOrder - b.sortOrder);

    // Get config
    const configDoc = await db.collection(COLLECTIONS.CONFIG).doc('main').get();
    const config = configDoc.data();

    // Get active session if any
    const activeSession = await sessionService.getActiveSession(req.stationId!);

    res.json({
      success: true,
      data: { station, services, config, activeSession },
    });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Heartbeat ---
router.post('/heartbeat', async (req: Request, res: Response) => {
  try {
    const { esp32Connected, networkStatus, appVersion, relayStates, activeSessionId } = req.body;

    await db.collection(COLLECTIONS.STATIONS).doc(req.stationId!).update({
      esp32Status: esp32Connected ? 'ONLINE' : 'OFFLINE',
      lastHeartbeat: Date.now(),
      updatedAt: Date.now(),
    });

    await db.collection(COLLECTIONS.HEARTBEATS).add({
      stationId: req.stationId,
      tabletId: req.headers['x-tablet-id'],
      timestamp: Date.now(),
      esp32Connected,
      networkStatus,
      appVersion,
      activeSessionId,
      relayStates: relayStates || [],
    });

    // Check if there's an active session that needs balance check
    let sessionUpdate = null;
    if (activeSessionId) {
      const session = await sessionService.getActiveSession(req.stationId!);
      if (session) {
        const balance = sessionService.calculateRealtimeBalance(session);
        if (balance.remainingBalance <= 0) {
          sessionUpdate = { action: 'END_SESSION', reason: 'BALANCE_DEPLETED' };
        }
      }
    }

    res.json({ success: true, data: { sessionUpdate } });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Create Session (after payment confirmed) ---
router.post('/session/create', async (req: Request, res: Response) => {
  try {
    const { amount, sepayRef } = req.body;

    // Check config for min deposit
    const configDoc = await db.collection(COLLECTIONS.CONFIG).doc('main').get();
    const config = configDoc.data();
    if (amount < (config?.minDeposit || 30000)) {
      res.status(400).json({ success: false, error: `Minimum deposit: ${config?.minDeposit || 30000}đ` });
      return;
    }

    // Check no active session
    const existing = await sessionService.getActiveSession(req.stationId!);
    if (existing) {
      res.status(400).json({ success: false, error: 'Station already has active session' });
      return;
    }

    const session = await sessionService.createSession(req.stationId!, amount, sepayRef);
    await logService.log(req.stationId!, 'PAYMENT', `Phiên mới: nạp ${amount.toLocaleString()}đ`, { sessionId: session.id });

    res.json({ success: true, data: session });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Add Deposit to Existing Session ---
router.post('/session/deposit', async (req: Request, res: Response) => {
  try {
    const { sessionId, amount, sepayRef } = req.body;
    const session = await sessionService.addDeposit(sessionId, amount, sepayRef);
    await logService.log(req.stationId!, 'PAYMENT', `Nạp thêm ${amount.toLocaleString()}đ`, { sessionId });

    res.json({ success: true, data: session });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Start Service ---
router.post('/session/start-service', async (req: Request, res: Response) => {
  try {
    const { sessionId, serviceId } = req.body;
    const result = await sessionService.startService(sessionId, serviceId);
    await logService.log(req.stationId!, 'SERVICE', `Bắt đầu: ${serviceId}`, { sessionId, serviceId });

    res.json({ success: true, data: result });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Pause Session ---
router.post('/session/pause', async (req: Request, res: Response) => {
  try {
    const { sessionId } = req.body;
    const session = await sessionService.pauseSession(sessionId);
    await logService.log(req.stationId!, 'SERVICE', 'Tạm dừng', { sessionId });

    res.json({ success: true, data: session });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Resume Session ---
router.post('/session/resume', async (req: Request, res: Response) => {
  try {
    const { sessionId } = req.body;
    const session = await sessionService.resumeSession(sessionId);
    await logService.log(req.stationId!, 'SERVICE', 'Tiếp tục', { sessionId });

    res.json({ success: true, data: session });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- End Session ---
router.post('/session/end', async (req: Request, res: Response) => {
  try {
    const { sessionId } = req.body;
    const session = await sessionService.endSession(sessionId);
    await logService.log(req.stationId!, 'SERVICE', `Kết thúc phiên. Đã dùng: ${session.totalUsed.toLocaleString()}đ`, { sessionId });

    res.json({ success: true, data: session });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Get Session Balance (realtime) ---
router.get('/session/:sessionId/balance', async (req: Request, res: Response) => {
  try {
    const sessionDoc = await db.collection(COLLECTIONS.SESSIONS).doc(req.params.sessionId).get();
    if (!sessionDoc.exists) {
      res.status(404).json({ success: false, error: 'Session not found' });
      return;
    }
    const session = sessionDoc.data();
    const balance = sessionService.calculateRealtimeBalance(session as any);

    res.json({ success: true, data: balance });
  } catch (error: any) {
    res.status(500).json({ success: false, error: error.message });
  }
});

export default router;
