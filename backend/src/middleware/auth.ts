import { Request, Response, NextFunction } from 'express';
import { db } from '../config/firebase.js';
import { COLLECTIONS } from '../config/constants.js';

// Extend Express Request
declare global {
  namespace Express {
    interface Request {
      admin?: { id: string; username: string; role: string; stations: string[] };
      stationId?: string;
    }
  }
}

/**
 * Admin auth — simple token/session for now
 * Header: Authorization: Bearer <admin-token>
 */
export const adminAuth = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      res.status(401).json({ success: false, error: 'No token provided' });
      return;
    }

    const token = authHeader.slice(7);
    // In demo mode, token = "admin:demo123" base64
    const decoded = Buffer.from(token, 'base64').toString();
    const [username, password] = decoded.split(':');

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

    req.admin = { id: admin.id, username: admin.username, role: admin.role, stations: admin.stations };
    next();
  } catch (error) {
    res.status(401).json({ success: false, error: 'Authentication failed' });
  }
};

/**
 * Station auth — tablet identifies itself
 * Header: X-Station-ID: station-001
 * Header: X-Tablet-ID: tablet-001
 */
export const stationAuth = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const stationId = req.headers['x-station-id'] as string;
    const tabletId = req.headers['x-tablet-id'] as string;

    if (!stationId || !tabletId) {
      res.status(401).json({ success: false, error: 'Station/Tablet ID required' });
      return;
    }

    const stationDoc = await db.collection(COLLECTIONS.STATIONS).doc(stationId).get();
    if (!stationDoc.exists) {
      res.status(404).json({ success: false, error: 'Station not found' });
      return;
    }

    const station = stationDoc.data();
    if (station.tabletId && station.tabletId !== tabletId && station.tabletId !== 'tablet-001') {
      // Only reject if station has a real (non-default) tablet assigned AND it doesn't match
      res.status(403).json({ success: false, error: 'Tablet not assigned to this station' });
      return;
    }
    // Auto-assign tablet on first connection (demo-friendly)
    if (!station.tabletId || station.tabletId === 'tablet-001' || station.tabletId !== tabletId) {
      await db.collection(COLLECTIONS.STATIONS).doc(stationId).update({ tabletId, updatedAt: Date.now() });
    }

    req.stationId = stationId;
    next();
  } catch (error) {
    res.status(401).json({ success: false, error: 'Station auth failed' });
  }
};
