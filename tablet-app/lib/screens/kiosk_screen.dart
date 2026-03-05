import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/esp32_service.dart';
import 'payment_screen.dart';
import 'admin_mini_screen.dart';

class KioskScreen extends StatefulWidget {
  final String stationId;
  const KioskScreen({super.key, required this.stationId});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final _api = ApiService.instance;
  final _esp32 = Esp32Service.instance;
  final _fmt = NumberFormat('#,###', 'vi');

  List<ServiceItem> _services = [];
  Session? _session;
  String? _activeServiceId;
  String? _lastServiceId; // Track last used service for resume
  bool _loading = true;
  bool _isPaused = false;
  Timer? _timer;
  Timer? _heartbeatTimer;
  Timer? _pauseTimer;
  int _elapsedSeconds = 0;
  int _pauseCountdown = 300; // 5 minutes in seconds
  int _adminTapCount = 0;
  DateTime? _lastAdminTap;
  DateTime? _lastServiceTap;

  @override
  void initState() {
    super.initState();
    _loadStationInfo();
    _esp32.connect();
    _startHeartbeat();
  }

  Future<void> _loadStationInfo() async {
    final res = await _api.getStationInfo();
    if (res['success'] == true) {
      final data = res['data'];
      setState(() {
        _services = (data['services'] as List).map((s) => ServiceItem.fromJson(s)).toList();
        if (data['activeSession'] != null) {
          _session = Session.fromJson(data['activeSession']);
          _activeServiceId = _session?.currentServiceId;
          _lastServiceId = _activeServiceId;
          if (_activeServiceId != null) _startBillingTimer();
        }
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _api.sendHeartbeat(
        esp32Connected: _esp32.isConnected,
        networkStatus: 'LAN',
        appVersion: '1.0.0',
        activeSessionId: _session?.id,
      );
    });
  }

  /// Start billing timer — deducts balance every second
  void _startBillingTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session == null || _activeServiceId == null || _isPaused) return;

      final service = _services.firstWhere(
        (s) => s.id == _activeServiceId,
        orElse: () => _services.first,
      );
      final costPerSecond = service.pricePerMinute / 60.0;

      setState(() {
        _elapsedSeconds++;
        _session = Session(
          id: _session!.id,
          stationId: _session!.stationId,
          status: _session!.status,
          totalDeposited: _session!.totalDeposited,
          totalUsed: _session!.totalUsed + costPerSecond.ceil(),
          remainingBalance: (_session!.remainingBalance - costPerSecond).floor(),
          currentServiceId: _session!.currentServiceId,
          currentServiceStartTime: _session!.currentServiceStartTime,
          isPaused: _session!.isPaused,
        );

        if (_session!.remainingBalance <= 0) {
          _forceEndSession();
        }
      });

      // Sync with server every 10s
      if (_elapsedSeconds % 10 == 0) _syncBalance();
    });
  }

  Future<void> _syncBalance() async {
    if (_session == null) return;
    final res = await _api.getSessionBalance(_session!.id);
    if (res['success'] == true) {
      final remaining = res['data']['remainingBalance'] ?? 0;
      if (remaining <= 0) _forceEndSession();
    }
  }

  /// Auto-start "Rửa nước" (water) service after payment
  Future<void> _autoStartDefaultService() async {
    if (_session == null) return;
    // Find water service, or first active service
    final defaultService = _services.firstWhere(
      (s) => s.id == 'water' && s.isActive,
      orElse: () => _services.firstWhere((s) => s.isActive, orElse: () => _services.first),
    );
    await _doStartService(defaultService);
  }

  /// Resume last service (or default to water)
  Future<void> _resumeLastService() async {
    if (_session == null) return;
    ServiceItem service;
    if (_lastServiceId != null) {
      service = _services.firstWhere(
        (s) => s.id == _lastServiceId && s.isActive,
        orElse: () => _services.firstWhere((s) => s.id == 'water' && s.isActive, orElse: () => _services.first),
      );
    } else {
      service = _services.firstWhere((s) => s.id == 'water' && s.isActive, orElse: () => _services.first);
    }
    await _doStartService(service);
  }

  /// Actually call API to start a service + turn on relay
  Future<void> _doStartService(ServiceItem service) async {
    if (_session == null) return;
    final res = await _api.startService(_session!.id, service.id);
    if (res['success'] == true) {
      final relayIndex = res['data']['relayIndex'];
      await _esp32.allOff();
      await _esp32.relayOn(relayIndex);
      setState(() {
        _activeServiceId = service.id;
        _lastServiceId = service.id;
        _isPaused = false;
      });
      _startBillingTimer();
      // Refresh session from server
      final infoRes = await _api.getStationInfo();
      if (infoRes['success'] == true && infoRes['data']['activeSession'] != null) {
        setState(() => _session = Session.fromJson(infoRes['data']['activeSession']));
      }
    }
  }

  Future<void> _selectService(ServiceItem service) async {
    if (_session == null || !service.isActive) return;

    // Prevent double-tap (500ms debounce)
    final now = DateTime.now();
    if (_lastServiceTap != null && now.difference(_lastServiceTap!).inMilliseconds < 500) return;
    _lastServiceTap = now;

    // If same service, ignore
    if (_activeServiceId == service.id) return;

    // Confirm switch if already running another service
    if (_activeServiceId != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Xác nhận chuyển dịch vụ', style: TextStyle(color: Colors.white, fontSize: 20)),
          content: Text(
            'Chuyển qua ${service.icon} ${service.name}?',
            style: const TextStyle(color: Colors.grey, fontSize: 18),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không', style: TextStyle(fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700]),
              child: const Text('Có, chuyển', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await _doStartService(service);
  }

  Future<void> _openPayment() async {
    // If in active session, confirm relay cutoff
    if (_session != null && _activeServiceId != null) {
      final activeService = _services.firstWhere((s) => s.id == _activeServiceId, orElse: () => _services.first);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('⚠️ Nạp thêm tiền', style: TextStyle(color: Colors.white, fontSize: 20)),
          content: Text(
            '${activeService.icon} ${activeService.name} sẽ bị ngắt trong lúc nạp tiền.\n\nBạn có đồng ý?',
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không', style: TextStyle(fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              child: const Text('Đồng ý', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      // Cut all relays
      await _esp32.allOff();
      _timer?.cancel();
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PaymentScreen(
        stationId: widget.stationId,
        sessionId: _session?.id,
      )),
    );

    if (result == true) {
      await _loadStationInfo();
      // After payment, auto-start default service
      if (_session != null) {
        await _autoStartDefaultService();
      }
    } else if (_session != null && _lastServiceId != null) {
      // Payment cancelled, resume last service
      await _resumeLastService();
    }
  }

  /// Pause session — start 5-minute countdown
  Future<void> _pauseSession() async {
    if (_session == null) return;
    final res = await _api.pauseSession(_session!.id);
    if (res['success'] == true) {
      await _esp32.allOff();
      _timer?.cancel();
      setState(() {
        _isPaused = true;
        _activeServiceId = null;
        _pauseCountdown = 300; // Reset to 5 minutes
      });

      // Start pause countdown
      _pauseTimer?.cancel();
      _pauseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _pauseCountdown--);
        if (_pauseCountdown <= 0) {
          _pauseTimer?.cancel();
          _forceEndSession();
        }
      });

      _loadStationInfo();
    }
  }

  /// Resume session — go back to last service
  Future<void> _resumeSession() async {
    if (_session == null) return;
    _pauseTimer?.cancel();
    final res = await _api.resumeSession(_session!.id);
    if (res['success'] == true) {
      setState(() => _isPaused = false);
      await _resumeLastService();
    }
  }

  /// Force end (balance depleted or pause timeout)
  Future<void> _forceEndSession() async {
    if (_session == null) return;
    await _esp32.allOff();
    await _api.endSession(_session!.id);
    _timer?.cancel();
    _pauseTimer?.cancel();
    setState(() {
      _session = null;
      _activeServiceId = null;
      _lastServiceId = null;
      _isPaused = false;
      _elapsedSeconds = 0;
    });
  }

  /// End session with confirmation
  Future<void> _endSession() async {
    if (_session == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ Kết thúc phiên?', style: TextStyle(color: Colors.white, fontSize: 20)),
        content: Text(
          'Số dư còn lại: ${_fmt.format(_session!.remainingBalance)}đ\n\n⚠️ Số dư còn lại sẽ KHÔNG được hoàn lại.\nBạn có chắc muốn kết thúc?',
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('Kết thúc', style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _forceEndSession();
  }

  void _handleAdminTap() {
    final now = DateTime.now();
    if (_lastAdminTap != null && now.difference(_lastAdminTap!).inSeconds > 3) {
      _adminTapCount = 0;
    }
    _adminTapCount++;
    _lastAdminTap = now;
    if (_adminTapCount >= 5) {
      _adminTapCount = 0;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMiniScreen()));
    }
  }

  // ──────────────────── BUILD ────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.blue)));
    }

    return Scaffold(
      body: SafeArea(
        child: _session != null ? _buildActiveView() : _buildWelcomeView(),
      ),
    );
  }

  // ──────────── WELCOME (no session) ────────────

  Widget _buildWelcomeView() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 40),

            // Header with admin tap
            GestureDetector(
              onTap: _handleAdminTap,
              child: TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(seconds: 2),
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: 0.8 + (value * 0.2),
                    child: Opacity(
                      opacity: value,
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.blue.withOpacity(0.3),
                              Colors.blue.withOpacity(0.05),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: const Text('🚗💨', style: TextStyle(fontSize: 80)),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [Colors.blue[300]!, Colors.blue[600]!],
              ).createShader(bounds),
              child: const Text(
                'RUAXEAI',
                style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Trạm rửa xe tự phục vụ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 1)),

            const SizedBox(height: 32),

            // Services showcase — vertical layout
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Column(
                children: [
                  const Text('Dịch vụ có sẵn', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ..._services.where((s) => s.isActive).map((service) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(service.icon, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(service.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          Text('${_fmt.format(service.pricePerMinute)}đ/phút',
                              style: TextStyle(color: Colors.blue[300], fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // CTA
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: _openPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 8,
                  shadowColor: Colors.blue.withOpacity(0.5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code, size: 30, color: Colors.white),
                    SizedBox(width: 12),
                    Text('BẮT ĐẦU SỬ DỤNG', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Nạp tối thiểu 10.000đ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 4),
            Text('💳 Thanh toán QR Code', style: TextStyle(color: Colors.blue[300], fontSize: 13)),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ──────────── ACTIVE SESSION ────────────

  Widget _buildActiveView() {
    return Column(
      children: [
        // Top: Balance bar
        _buildBalanceBar(),

        // Middle: Service grid
        Expanded(child: _isPaused ? _buildPausedView() : _buildServiceGrid()),

        // Bottom: Control buttons
        _buildControls(),
      ],
    );
  }

  Widget _buildBalanceBar() {
    final activeService = _activeServiceId != null
        ? _services.firstWhere((s) => s.id == _activeServiceId, orElse: () => _services.first)
        : null;

    int remainingSeconds = 0;
    if (activeService != null && _session != null) {
      remainingSeconds = (_session!.remainingBalance / (activeService.pricePerMinute / 60.0)).floor();
    }
    final mins = remainingSeconds ~/ 60;
    final secs = remainingSeconds % 60;

    return GestureDetector(
      onTap: _handleAdminTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          border: const Border(bottom: BorderSide(color: Color(0xFF1F2937), width: 2)),
        ),
        child: Column(
          children: [
            // Balance — BIG
            Text(
              '${_fmt.format(_session?.remainingBalance ?? 0)}đ',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: (_session?.remainingBalance ?? 0) < 5000 ? Colors.red : Colors.green,
              ),
            ),
            if (activeService != null) ...[
              const SizedBox(height: 4),
              Text(
                'Còn ~$mins phút ${secs.toString().padLeft(2, '0')} giây',
                style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(activeService.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(
                    '${activeService.name} • ${_fmt.format(activeService.pricePerMinute)}đ/phút',
                    style: TextStyle(color: Colors.blue[300], fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildServiceGrid() {
    final activeServices = _services.where((s) => s.isActive).toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.1,
        ),
        itemCount: activeServices.length,
        itemBuilder: (ctx, i) => _buildServiceCard(activeServices[i]),
      ),
    );
  }

  Widget _buildServiceCard(ServiceItem service) {
    final isActive = _activeServiceId == service.id;
    return GestureDetector(
      onTap: () => _selectService(service),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withOpacity(0.2) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.blue : const Color(0xFF1F2937),
            width: isActive ? 3 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(service.icon, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(
              service.name,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[300],
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '${_fmt.format(service.pricePerMinute)}đ/phút',
              style: TextStyle(
                color: isActive ? Colors.blue : Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('ĐANG DÙNG', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPausedView() {
    final mins = _pauseCountdown ~/ 60;
    final secs = _pauseCountdown % 60;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.pause_circle_outline, color: Colors.yellow, size: 80),
          const SizedBox(height: 16),
          const Text('TẠM DỪNG', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.w900, fontSize: 28)),
          const SizedBox(height: 12),
          Text(
            '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.w900, fontSize: 56, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          const Text('Hết thời gian tạm dừng sẽ tự kết thúc phiên',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 32),
          SizedBox(
            width: 250,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _resumeSession,
              icon: const Icon(Icons.play_arrow, size: 28, color: Colors.white),
              label: const Text('TIẾP TỤC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(top: BorderSide(color: Color(0xFF1F2937), width: 2)),
      ),
      child: Row(
        children: [
          // Nạp thêm
          Expanded(
            child: SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _openPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                child: const Text('💰 Nạp thêm', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Tạm dừng
          Expanded(
            child: SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _isPaused ? _resumeSession : (_activeServiceId != null ? _pauseSession : null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isPaused ? Colors.blue[700] : Colors.orange[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  _isPaused ? '▶ Tiếp tục' : '⏸ Tạm dừng',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Kết thúc
          Expanded(
            child: SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _endSession,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                child: const Text('⏹ Kết thúc', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    _pauseTimer?.cancel();
    super.dispose();
  }
}
