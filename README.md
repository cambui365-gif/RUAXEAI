# 🚗 RUAXEAI — Hệ thống rửa xe tự phục vụ thông minh

## Tổng quan
Hệ thống quản lý trạm rửa xe tự phục vụ: Tablet Android (kiosk) + ESP32 điều khiển relay + Thanh toán QR (SePay) + Admin Dashboard.

## Kiến trúc
```
VPS (Backend API + Admin Web)
  ├── Firebase Firestore (Realtime DB)
  ├── SePay Webhook (Thanh toán)
  └── Telegram Bot (Thông báo)

Trạm rửa xe
  ├── Tablet Android (Kiosk Mode) ── USB ── ESP32 (6 Relay)
  ├── Router (LAN + WiFi)
  └── Camera Imou (RTSP) [Phase 2]
```

## Cấu trúc dự án
```
RUAXEAI/
├── backend/          # Node.js + Express + TypeScript
├── admin-web/        # React + Vite + TailwindCSS
├── tablet-app/       # Flutter (Android Kiosk)
├── esp32-firmware/   # Arduino/PlatformIO
└── docs/             # Tài liệu
```

## 6 Dịch vụ
1. 💧 Rửa nước
2. 🧊 Bọt tuyết
3. 🌀 Hút bụi
4. 💨 Khí nén
5. 🔥 Hơi nóng
6. 🧴 Nước rửa tay

## Tech Stack
- **Tablet:** Flutter + Dart (Android Kiosk)
- **ESP32:** Arduino USB Serial + 6 Relay
- **Backend:** Node.js + Express + TypeScript
- **Database:** Firebase Firestore
- **Admin:** React + Vite + TailwindCSS
- **Payment:** SePay (QR Bank Transfer)
