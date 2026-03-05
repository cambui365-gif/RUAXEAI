// ============================================================
//  RUAXEAI — Constants
// ============================================================

export const COLLECTIONS = {
  STATIONS: 'stations',
  SESSIONS: 'sessions',
  TRANSACTIONS: 'transactions',
  SERVICES: 'services',
  ADMINS: 'admins',
  CONFIG: 'config',
  HEARTBEATS: 'heartbeats',
  STATION_LOGS: 'station_logs',
} as const;

export const DEFAULT_SERVICES = [
  { id: 'water', name: 'Rửa nước', icon: '💧', pricePerMinute: 1000, relayIndex: 1, isActive: true, sortOrder: 1 },
  { id: 'foam', name: 'Bọt tuyết', icon: '🧊', pricePerMinute: 2000, relayIndex: 2, isActive: true, sortOrder: 2 },
  { id: 'vacuum', name: 'Hút bụi', icon: '🌀', pricePerMinute: 1500, relayIndex: 3, isActive: true, sortOrder: 3 },
  { id: 'air', name: 'Khí nén', icon: '💨', pricePerMinute: 1000, relayIndex: 4, isActive: true, sortOrder: 4 },
  { id: 'heat', name: 'Hơi nóng', icon: '🔥', pricePerMinute: 500, relayIndex: 5, isActive: true, sortOrder: 5 },
  { id: 'soap', name: 'Nước rửa tay', icon: '🧴', pricePerMinute: 500, relayIndex: 6, isActive: true, sortOrder: 6 },
];

export const DEFAULT_CONFIG = {
  minDeposit: 10000, // 10k VND
  maxPauseMinutes: 5,
  autoRestartMinutes: 10,
  sepay: {
    apiKey: '',
    merchantId: '',
    bankAccount: '',
    bankCode: '',
    webhookSecret: '',
  },
  telegram: {
    botToken: '',
    alertChatIds: [],
  },
  services: DEFAULT_SERVICES,
};
