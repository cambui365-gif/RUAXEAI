class ServiceItem {
  final String id;
  final String name;
  final String icon;
  final int pricePerMinute;
  final int relayIndex;
  final bool isActive;

  ServiceItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.pricePerMinute,
    required this.relayIndex,
    required this.isActive,
  });

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    icon: json['icon'] ?? '⚙️',
    pricePerMinute: json['pricePerMinute'] ?? 0,
    relayIndex: json['relayIndex'] ?? 0,
    isActive: json['isActive'] ?? false,
  );
}

class Session {
  final String id;
  final String stationId;
  final String status;
  final int totalDeposited;
  final int totalUsed;
  final int remainingBalance;
  final String? currentServiceId;
  final int? currentServiceStartTime;
  final bool isPaused;

  Session({
    required this.id,
    required this.stationId,
    required this.status,
    required this.totalDeposited,
    required this.totalUsed,
    required this.remainingBalance,
    this.currentServiceId,
    this.currentServiceStartTime,
    required this.isPaused,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] ?? '',
    stationId: json['stationId'] ?? '',
    status: json['status'] ?? '',
    totalDeposited: json['totalDeposited'] ?? 0,
    totalUsed: json['totalUsed'] ?? 0,
    remainingBalance: json['remainingBalance'] ?? 0,
    currentServiceId: json['currentServiceId'],
    currentServiceStartTime: json['currentServiceStartTime'],
    isPaused: json['isPaused'] ?? false,
  );
}

class PaymentQR {
  final String refCode;
  final String qrUrl;
  final int amount;
  final String transferContent;

  PaymentQR({
    required this.refCode,
    required this.qrUrl,
    required this.amount,
    required this.transferContent,
  });

  factory PaymentQR.fromJson(Map<String, dynamic> json) => PaymentQR(
    refCode: json['refCode'] ?? '',
    qrUrl: json['qrUrl'] ?? '',
    amount: json['amount'] ?? 0,
    transferContent: json['transferContent'] ?? '',
  );
}
