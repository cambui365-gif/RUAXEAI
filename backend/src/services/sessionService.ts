/**
 * Session Service — Core business logic for wash sessions
 */
import { db } from '../config/firebase.js';
import { COLLECTIONS } from '../config/constants.js';
import { Session, ServiceUsageRecord, Transaction } from '../types/index.js';
import { v4 as uuid } from 'uuid';

/**
 * Create a new wash session when customer deposits money
 */
export async function createSession(stationId: string, depositAmount: number, sepayRef?: string): Promise<Session> {
  const sessionId = `ses_${Date.now()}_${uuid().slice(0, 8)}`;
  const txId = `tx_${Date.now()}_${uuid().slice(0, 8)}`;

  const session: Session = {
    id: sessionId,
    stationId,
    status: 'ACTIVE',
    startTime: Date.now(),
    totalDeposited: depositAmount,
    totalUsed: 0,
    remainingBalance: depositAmount,
    isPaused: false,
    totalPauseSeconds: 0,
    serviceUsage: [],
    transactions: [txId],
  };

  const transaction: Transaction = {
    id: txId,
    sessionId,
    stationId,
    amount: depositAmount,
    type: 'DEPOSIT',
    status: 'COMPLETED',
    sepayRef,
    description: `Nạp ${depositAmount.toLocaleString()}đ`,
    timestamp: Date.now(),
  };

  await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).set(session);
  await db.collection(COLLECTIONS.TRANSACTIONS).doc(txId).set(transaction);

  // Update station status
  await db.collection(COLLECTIONS.STATIONS).doc(stationId).update({
    status: 'IN_USE',
    updatedAt: Date.now(),
  });

  return session;
}

/**
 * Add deposit to existing session
 */
export async function addDeposit(sessionId: string, amount: number, sepayRef?: string): Promise<Session> {
  const sessionDoc = await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).get();
  if (!sessionDoc.exists) throw new Error('Session not found');

  const session = sessionDoc.data() as Session;
  if (session.status !== 'ACTIVE' && session.status !== 'PAUSED') {
    throw new Error('Session is not active');
  }

  const txId = `tx_${Date.now()}_${uuid().slice(0, 8)}`;

  const transaction: Transaction = {
    id: txId,
    sessionId,
    stationId: session.stationId,
    amount,
    type: 'DEPOSIT',
    status: 'COMPLETED',
    sepayRef,
    description: `Nạp thêm ${amount.toLocaleString()}đ`,
    timestamp: Date.now(),
  };

  await db.collection(COLLECTIONS.TRANSACTIONS).doc(txId).set(transaction);
  await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).update({
    totalDeposited: session.totalDeposited + amount,
    remainingBalance: session.remainingBalance + amount,
    transactions: [...session.transactions, txId],
  });

  return { ...session, totalDeposited: session.totalDeposited + amount, remainingBalance: session.remainingBalance + amount };
}

/**
 * Start using a service (switch relay on)
 */
export async function startService(sessionId: string, serviceId: string): Promise<{ session: Session; relayIndex: number }> {
  const sessionDoc = await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).get();
  if (!sessionDoc.exists) throw new Error('Session not found');
  const session = sessionDoc.data() as Session;

  if (session.status !== 'ACTIVE') throw new Error('Session is not active');
  if (session.remainingBalance <= 0) throw new Error('Insufficient balance');

  // Get service info
  const serviceDoc = await db.collection(COLLECTIONS.SERVICES).doc(serviceId).get();
  if (!serviceDoc.exists) throw new Error('Service not found');
  const service = serviceDoc.data();
  if (!service.isActive) throw new Error('Service is not available');

  // If currently using another service, stop it first
  const updatedUsage = [...session.serviceUsage];
  if (session.currentServiceId) {
    const lastUsage = updatedUsage[updatedUsage.length - 1];
    if (lastUsage && !lastUsage.endTime) {
      const elapsed = (Date.now() - lastUsage.startTime) / 1000;
      lastUsage.endTime = Date.now();
      lastUsage.durationSeconds = elapsed;
      lastUsage.cost = Math.ceil((elapsed / 60) * lastUsage.pricePerMinute);
    }
  }

  // Add new usage record
  const newUsage: ServiceUsageRecord = {
    serviceId,
    serviceName: service.name,
    startTime: Date.now(),
    durationSeconds: 0,
    cost: 0,
    pricePerMinute: service.pricePerMinute,
  };
  updatedUsage.push(newUsage);

  // Calculate total used
  const totalUsed = updatedUsage.reduce((sum, u) => sum + u.cost, 0);

  await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).update({
    currentServiceId: serviceId,
    currentServiceStartTime: Date.now(),
    isPaused: false,
    serviceUsage: updatedUsage,
    totalUsed,
    remainingBalance: session.totalDeposited - totalUsed,
  });

  return {
    session: { ...session, currentServiceId: serviceId, serviceUsage: updatedUsage, totalUsed, remainingBalance: session.totalDeposited - totalUsed },
    relayIndex: service.relayIndex,
  };
}

/**
 * Pause session — turn off current relay, start pause timer
 */
export async function pauseSession(sessionId: string): Promise<Session> {
  const sessionDoc = await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).get();
  if (!sessionDoc.exists) throw new Error('Session not found');
  const session = sessionDoc.data() as Session;

  if (session.status !== 'ACTIVE') throw new Error('Session is not active');

  // Finalize current service usage
  const updatedUsage = [...session.serviceUsage];
  if (session.currentServiceId && updatedUsage.length > 0) {
    const last = updatedUsage[updatedUsage.length - 1];
    if (last && !last.endTime) {
      const elapsed = (Date.now() - last.startTime) / 1000;
      last.endTime = Date.now();
      last.durationSeconds = elapsed;
      last.cost = Math.ceil((elapsed / 60) * last.pricePerMinute);
    }
  }

  const totalUsed = updatedUsage.reduce((sum, u) => sum + u.cost, 0);

  await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).update({
    status: 'PAUSED',
    isPaused: true,
    pauseStartTime: Date.now(),
    currentServiceId: null,
    currentServiceStartTime: null,
    serviceUsage: updatedUsage,
    totalUsed,
    remainingBalance: session.totalDeposited - totalUsed,
  });

  return { ...session, status: 'PAUSED', isPaused: true, totalUsed, remainingBalance: session.totalDeposited - totalUsed };
}

/**
 * Resume session from pause
 */
export async function resumeSession(sessionId: string): Promise<Session> {
  const sessionDoc = await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).get();
  if (!sessionDoc.exists) throw new Error('Session not found');
  const session = sessionDoc.data() as Session;

  if (session.status !== 'PAUSED') throw new Error('Session is not paused');

  const pauseDuration = session.pauseStartTime ? (Date.now() - session.pauseStartTime) / 1000 : 0;

  await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).update({
    status: 'ACTIVE',
    isPaused: false,
    pauseStartTime: null,
    totalPauseSeconds: session.totalPauseSeconds + pauseDuration,
  });

  return { ...session, status: 'ACTIVE', isPaused: false };
}

/**
 * End session — turn off all relays, finalize
 */
export async function endSession(sessionId: string): Promise<Session> {
  const sessionDoc = await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).get();
  if (!sessionDoc.exists) throw new Error('Session not found');
  const session = sessionDoc.data() as Session;

  // Finalize current usage
  const updatedUsage = [...session.serviceUsage];
  if (session.currentServiceId && updatedUsage.length > 0) {
    const last = updatedUsage[updatedUsage.length - 1];
    if (last && !last.endTime) {
      const elapsed = (Date.now() - last.startTime) / 1000;
      last.endTime = Date.now();
      last.durationSeconds = elapsed;
      last.cost = Math.ceil((elapsed / 60) * last.pricePerMinute);
    }
  }

  const totalUsed = updatedUsage.reduce((sum, u) => sum + u.cost, 0);

  await db.collection(COLLECTIONS.SESSIONS).doc(sessionId).update({
    status: 'COMPLETED',
    endTime: Date.now(),
    currentServiceId: null,
    currentServiceStartTime: null,
    isPaused: false,
    serviceUsage: updatedUsage,
    totalUsed,
    remainingBalance: session.totalDeposited - totalUsed,
  });

  // Update station
  await db.collection(COLLECTIONS.STATIONS).doc(session.stationId).update({
    status: 'ONLINE',
    updatedAt: Date.now(),
  });

  return { ...session, status: 'COMPLETED', endTime: Date.now(), totalUsed, remainingBalance: session.totalDeposited - totalUsed };
}

/**
 * Get active session for a station
 */
export async function getActiveSession(stationId: string): Promise<Session | null> {
  const snap = await db.collection(COLLECTIONS.SESSIONS)
    .where('stationId', '==', stationId)
    .where('status', 'in', ['ACTIVE', 'PAUSED'])
    .limit(1)
    .get();

  if (snap.empty) return null;
  return snap.docs[0].data() as Session;
}

/**
 * Calculate realtime remaining balance (considering current service running)
 */
export function calculateRealtimeBalance(session: Session): { remainingBalance: number; currentCost: number; totalUsed: number; estimatedMinutesLeft: number } {
  let totalUsed = session.serviceUsage
    .filter(u => u.endTime)
    .reduce((sum, u) => sum + u.cost, 0);

  let currentCost = 0;
  let currentPricePerMinute = 0;

  if (session.currentServiceId && session.currentServiceStartTime) {
    const lastUsage = session.serviceUsage[session.serviceUsage.length - 1];
    if (lastUsage && !lastUsage.endTime) {
      const elapsed = (Date.now() - lastUsage.startTime) / 1000;
      currentCost = Math.ceil((elapsed / 60) * lastUsage.pricePerMinute);
      currentPricePerMinute = lastUsage.pricePerMinute;
    }
  }

  totalUsed += currentCost;
  const remainingBalance = session.totalDeposited - totalUsed;
  const estimatedMinutesLeft = currentPricePerMinute > 0 ? remainingBalance / currentPricePerMinute : 0;

  return { remainingBalance, currentCost, totalUsed, estimatedMinutesLeft };
}
