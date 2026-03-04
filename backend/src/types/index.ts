// ============================================================
//  RUAXEAI — Type Definitions
// ============================================================

// --- Station ---
export interface Station {
  id: string;
  name: string;
  location: string;
  status: StationStatus;
  tabletId: string;
  esp32Status: 'ONLINE' | 'OFFLINE' | 'ERROR';
  cameraUrl?: string;
  smartPlugId?: string;
  lastHeartbeat: number;
  createdAt: number;
  updatedAt: number;
  config?: StationConfigOverride;
}

export type StationStatus = 'ONLINE' | 'OFFLINE' | 'MAINTENANCE' | 'IN_USE';

export interface StationConfigOverride {
  minDeposit?: number;
  maxPauseMinutes?: number;
  autoRestartMinutes?: number;
  services?: Record<string, { pricePerMinute: number; isActive: boolean }>;
}

// --- Service ---
export interface Service {
  id: string;
  name: string;
  icon: string;
  pricePerMinute: number;
  relayIndex: number; // 1-6
  isActive: boolean;
  sortOrder: number;
}

// --- Session (phiên rửa xe) ---
export interface Session {
  id: string;
  stationId: string;
  status: SessionStatus;
  startTime: number;
  endTime?: number;
  totalDeposited: number;
  totalUsed: number;
  remainingBalance: number;
  currentServiceId?: string;
  currentServiceStartTime?: number;
  isPaused: boolean;
  pauseStartTime?: number;
  totalPauseSeconds: number;
  serviceUsage: ServiceUsageRecord[];
  transactions: string[]; // transaction IDs
  snapshotUrls?: string[];
}

export type SessionStatus = 'ACTIVE' | 'PAUSED' | 'COMPLETED' | 'EXPIRED' | 'ERROR';

export interface ServiceUsageRecord {
  serviceId: string;
  serviceName: string;
  startTime: number;
  endTime?: number;
  durationSeconds: number;
  cost: number;
  pricePerMinute: number;
}

// --- Transaction ---
export interface Transaction {
  id: string;
  sessionId: string;
  stationId: string;
  amount: number;
  type: TransactionType;
  status: TransactionStatus;
  sepayRef?: string;
  sepayTransId?: string;
  description: string;
  timestamp: number;
}

export type TransactionType = 'DEPOSIT' | 'SERVICE_USAGE' | 'REFUND';
export type TransactionStatus = 'PENDING' | 'COMPLETED' | 'FAILED' | 'CANCELLED';

// --- Admin ---
export interface Admin {
  id: string;
  username: string;
  passwordHash: string;
  name: string;
  role: AdminRole;
  telegramChatId?: string;
  stations: string[]; // station IDs accessible
  isActive: boolean;
  createdAt: number;
  lastLogin?: number;
}

export type AdminRole = 'OWNER' | 'MANAGER' | 'VIEWER';

// --- System Config ---
export interface SystemConfig {
  minDeposit: number; // VND, default 30000
  maxPauseMinutes: number; // default 5
  autoRestartMinutes: number; // restart tablet if offline > X min
  sepay: {
    apiKey: string;
    merchantId: string;
    bankAccount: string;
    bankCode: string;
    webhookSecret: string;
  };
  telegram: {
    botToken: string;
    alertChatIds: string[];
  };
  services: Service[];
}

// --- Heartbeat ---
export interface Heartbeat {
  stationId: string;
  tabletId: string;
  timestamp: number;
  esp32Connected: boolean;
  networkStatus: 'LAN' | 'WIFI' | 'OFFLINE';
  batteryLevel?: number;
  appVersion: string;
  activeSessionId?: string;
  relayStates: boolean[]; // 6 relay states
}

// --- Station Log ---
export interface StationLog {
  id: string;
  stationId: string;
  type: 'INFO' | 'WARNING' | 'ERROR' | 'PAYMENT' | 'SERVICE' | 'SYSTEM';
  message: string;
  details?: any;
  timestamp: number;
  snapshotUrl?: string;
}

// --- ESP32 Commands ---
export interface ESP32Command {
  action: 'ON' | 'OFF' | 'OFF_ALL' | 'STATUS';
  relay?: number; // 1-6
  timestamp: number;
}

export interface ESP32Status {
  connected: boolean;
  relays: boolean[]; // [false, false, false, false, false, false]
  uptime: number;
  firmware: string;
}

// --- API Responses ---
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

// --- SePay Webhook ---
export interface SepayWebhook {
  id: number;
  gateway: string;
  transactionDate: string;
  accountNumber: string;
  subAccount?: string;
  code?: string;
  content: string;
  transferType: 'in' | 'out';
  transferAmount: number;
  accumulated: number;
  referenceCode: string;
}
