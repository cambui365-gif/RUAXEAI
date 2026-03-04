import { db } from '../config/firebase.js';
import { COLLECTIONS } from '../config/constants.js';
import { v4 as uuid } from 'uuid';
import { StationLog } from '../types/index.js';

export async function log(
  stationId: string,
  type: StationLog['type'],
  message: string,
  details?: any
): Promise<void> {
  const logEntry: StationLog = {
    id: `log_${uuid().slice(0, 8)}`,
    stationId,
    type,
    message,
    details,
    timestamp: Date.now(),
  };
  await db.collection(COLLECTIONS.STATION_LOGS).add(logEntry);
}

export async function getStationLogs(stationId: string, limit = 50): Promise<StationLog[]> {
  const snap = await db.collection(COLLECTIONS.STATION_LOGS)
    .where('stationId', '==', stationId)
    .orderBy('timestamp', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((d: any) => d.data());
}
