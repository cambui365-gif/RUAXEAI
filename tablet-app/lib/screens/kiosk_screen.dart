import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/esp32_service.dart';
import '../services/tts_service.dart';
import 'payment_screen.dart';
import 'admin_mini_screen.dart';

class KioskScreen extends StatefulWidget {
  final String stationId;
  const KioskScreen({super.key, required this.stationId});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> with WidgetsBindingObserver {
  final _api = ApiService.instance;
  final _esp32 = Esp32Service.instance;
  final _tts = TtsService.instance;
  final _fmt = NumberFormat('#,###', 'vi');

  List<ServiceItem> _services = [];
  Session? _session;
  String? _activeServiceId;
  String? _lastServiceId;
  bool _loading = true;
  bool _isPaused = false;
  bool _lowBalanceWarning = false;
  Timer? _timer;
  Timer? _heartbeatTimer;
  Timer? _pauseTimer;
  Timer? _marqueeTimer;
  int _elapsedSeconds = 0;
  int _totalPauseUsed = 0; // Accumulated pause seconds used
  int _pauseCountdown = 300; // Current countdown
  int _maxPauseSeconds = 300; // From config
  int _adminTapCount = 0;
  DateTime? _lastAdminTap;
  DateTime? _lastServiceTap;
  String _marqueeText = 'Chào mừng đến trạm rửa xe RUAXEAI • Rửa xe tự phục vụ 24/7 • Thanh toán QR nhanh chóng •';
  double _marqueeOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // Keep screen on
    _tts.init();
    _loadStationInfo();
    _esp32.connect();
    _startHeartbeat();
    _startMarquee();
    // Kiosk: block system navigation
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kiosk mode: bring app back to front if paused/minimized
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Re-assert immersive mode when coming back
      Future.delayed(const Duration(milliseconds: 500), () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      });
    }
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _startMarquee() {
    _marqueeTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() => _marqueeOffset += 1.5);
    });
  }

  Future<void> _loadStationInfo() async {
    final res = await _api.getStationInfo();
    if (res['success'] == true) {
      final data = res['data'];
      final config = data['config'];
      setState(() {
        _services = (data['services'] as List).map((s) => ServiceItem.fromJson(s)).toList();
        _maxPauseSeconds = ((config?['maxPauseMinutes'] ?? 5) as int) * 60;
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

  void _startBillingTimer() {
    _elapsedSeconds = 0;
    _lowBalanceWarning = false;
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

        // Low balance warning at ~1 minute
        final remainingSecs = (_session!.remainingBalance / costPerSecond).floor();
        if (remainingSecs <= 60 && !_lowBalanceWarning) {
          _lowBalanceWarning = true;
          _tts.lowBalance();
          // Play system alert sound
          SystemSound.play(SystemSoundType.alert);
        }

        if (_session!.remainingBalance <= 0) {
          _forceEndSession();
        }
      });

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

  Future<void> _autoStartDefaultService() async {
    if (_session == null) return;
    final defaultService = _services.firstWhere(
      (s) => s.id == 'water' && s.isActive,
      orElse: () => _services.firstWhere((s) => s.isActive, orElse: () => _services.first),
    );
    await _doStartService(defaultService);
  }

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

  Future<void> _doStartService(ServiceItem service) async {
    if (_session == null) return;
    final res = await _api.startService(_session!.id, service.id);
    if (res['success'] == true) {
      final relayIndex = res['data']['relayIndex'];
      await _esp32.allOff();
      await _esp32.relayOn(relayIndex);
      _tts.switchService(service.name);
      setState(() {
        _activeServiceId = service.id;
        _lastServiceId = service.id;
        _isPaused = false;
        _lowBalanceWarning = false;
      });
      _startBillingTimer();
      final infoRes = await _api.getStationInfo();
      if (infoRes['success'] == true && infoRes['data']['activeSession'] != null) {
        setState(() => _session = Session.fromJson(infoRes['data']['activeSession']));
      }
    }
  }

  Future<void> _selectService(ServiceItem service) async {
    if (_session == null || !service.isActive) return;
    final now = DateTime.now();
    if (_lastServiceTap != null && now.difference(_lastServiceTap!).inMilliseconds < 500) return;
    _lastServiceTap = now;
    if (_activeServiceId == service.id) return;

    if (_activeServiceId != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Xác nhận chuyển dịch vụ', style: TextStyle(color: Colors.white, fontSize: 20)),
          content: Text('Chuyển qua ${service.icon} ${service.name}?', style: const TextStyle(color: Colors.grey, fontSize: 18)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không', style: TextStyle(fontSize: 16))),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không', style: TextStyle(fontSize: 16))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              child: const Text('Đồng ý', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await _esp32.allOff();
      _timer?.cancel();
    }

    _tts.welcomePayment();

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PaymentScreen(stationId: widget.stationId, sessionId: _session?.id)),
    );

    if (result == true) {
      _tts.paymentSuccess();
      await _loadStationInfo();
      if (_session != null) await _autoStartDefaultService();
    } else if (_session != null && _lastServiceId != null) {
      await _resumeLastService();
    }
  }

  /// Pause — uses accumulated time
  Future<void> _pauseSession() async {
    if (_session == null) return;
    final remaining = _maxPauseSeconds - _totalPauseUsed;
    if (remaining <= 0) {
      _showSnack('Đã hết thời gian tạm dừng cho phiên này');
      return;
    }

    final res = await _api.pauseSession(_session!.id);
    if (res['success'] == true) {
      await _esp32.allOff();
      _timer?.cancel();
      _tts.pauseWarning();
      setState(() {
        _isPaused = true;
        _activeServiceId = null;
        _pauseCountdown = remaining;
      });

      _pauseTimer?.cancel();
      _pauseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _pauseCountdown--;
          _totalPauseUsed++;
        });
        if (_pauseCountdown <= 0) {
          _pauseTimer?.cancel();
          _tts.speak('Hết thời gian tạm dừng. Phiên kết thúc.');
          _forceEndSession();
        }
      });
      _loadStationInfo();
    }
  }

  Future<void> _resumeSession() async {
    if (_session == null) return;
    _pauseTimer?.cancel();
    final res = await _api.resumeSession(_session!.id);
    if (res['success'] == true) {
      setState(() => _isPaused = false);
      await _resumeLastService();
    }
  }

  Future<void> _forceEndSession() async {
    if (_session == null) return;
    await _esp32.allOff();
    await _api.endSession(_session!.id);
    _timer?.cancel();
    _pauseTimer?.cancel();
    _tts.sessionEnded();
    setState(() {
      _session = null;
      _activeServiceId = null;
      _lastServiceId = null;
      _isPaused = false;
      _lowBalanceWarning = false;
      _totalPauseUsed = 0;
      _elapsedSeconds = 0;
    });
  }

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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không', style: TextStyle(fontSize: 16))),
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
    if (_lastAdminTap != null && now.difference(_lastAdminTap!).inSeconds > 3) _adminTapCount = 0;
    _adminTapCount++;
    _lastAdminTap = now;
    if (_adminTapCount >= 5) {
      _adminTapCount = 0;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMiniScreen()));
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ──────────── BUILD ────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.blue)));

    // Block back button (kiosk mode)
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(child: _session != null ? _buildActiveView() : _buildWelcomeView()),
      ),
    );
  }

  // ──────────── WELCOME ────────────

  Widget _buildWelcomeView() {
    return Column(
      children: [
        // Marquee banner
        _buildMarquee(),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 24),

                GestureDetector(
                  onTap: _handleAdminTap,
                  child: TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(seconds: 2),
                    builder: (context, double value, child) {
                      return Transform.scale(
                        scale: 0.8 + (value * 0.2),
                        child: Opacity(opacity: value, child: const Text('🚗💨', style: TextStyle(fontSize: 72))),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(colors: [Colors.blue[300]!, Colors.blue[600]!]).createShader(bounds),
                  child: const Text('RUAXEAI', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const Text('Trạm rửa xe tự phục vụ', style: TextStyle(fontSize: 16, color: Colors.grey, letterSpacing: 1)),

                const SizedBox(height: 24),

                // How to use guide
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📖 HƯỚNG DẪN SỬ DỤNG', style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      _guideStep('1', 'Nhấn "BẮT ĐẦU" và nạp tiền qua QR'),
                      _guideStep('2', 'Máy tự động chạy Rửa nước'),
                      _guideStep('3', 'Chọn dịch vụ khác nếu muốn'),
                      _guideStep('4', 'Nhấn "Tạm dừng" khi cần nghỉ (tối đa 5 phút)'),
                      _guideStep('5', 'Nhấn "Kết thúc" khi xong'),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Services list
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1F2937)),
                  ),
                  child: Column(
                    children: [
                      const Text('💧 BẢNG GIÁ DỊCH VỤ', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      ..._services.where((s) => s.isActive).map((s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(s.icon, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                            Text('${_fmt.format(s.pricePerMinute)}đ/phút', style: TextStyle(color: Colors.blue[300], fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // CTA
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _openPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code, size: 28, color: Colors.white),
                        SizedBox(width: 10),
                        Text('BẮT ĐẦU SỬ DỤNG', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Nạp tối thiểu 10.000đ • Thanh toán QR', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _guideStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(11)),
            child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildMarquee() {
    return Container(
      height: 32,
      color: Colors.blue[800],
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final textWidth = _marqueeText.length * 8.0;
            final offset = _marqueeOffset % (textWidth + width);
            return Stack(
              children: [
                Positioned(
                  left: width - offset,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      _marqueeText,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ──────────── ACTIVE SESSION ────────────

  Widget _buildActiveView() {
    return Column(
      children: [
        // Low balance warning banner
        if (_lowBalanceWarning) _buildLowBalanceBanner(),

        // Balance bar
        _buildBalanceBar(),

        // Content
        Expanded(child: _isPaused ? _buildPausedView() : _buildServiceGrid()),

        // Controls
        _buildControls(),
      ],
    );
  }

  Widget _buildLowBalanceBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.red,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
          SizedBox(width: 8),
          Text('⚠️ SẮP HẾT TIỀN - NẠP THÊM NGAY!', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
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
    final balance = _session?.remainingBalance ?? 0;
    final isLow = balance < 5000;

    return GestureDetector(
      onTap: _handleAdminTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          border: Border(bottom: BorderSide(color: Color(0xFF1F2937), width: 2)),
        ),
        child: Column(
          children: [
            Text(
              '${_fmt.format(balance)}đ',
              style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: isLow ? Colors.red : Colors.green),
            ),
            if (activeService != null) ...[
              const SizedBox(height: 2),
              Text(
                'Còn ~$mins phút ${secs.toString().padLeft(2, '0')} giây',
                style: TextStyle(color: isLow ? Colors.red[300] : Colors.grey, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(activeService.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text('${activeService.name} • ${_fmt.format(activeService.pricePerMinute)}đ/phút',
                    style: TextStyle(color: Colors.blue[300], fontSize: 14, fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
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
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isActive ? Colors.blue : const Color(0xFF1F2937), width: isActive ? 3 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(service.icon, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 6),
            Text(service.name, style: TextStyle(color: isActive ? Colors.white : Colors.grey[300], fontWeight: FontWeight.w900, fontSize: 17), textAlign: TextAlign.center),
            const SizedBox(height: 3),
            Text('${_fmt.format(service.pricePerMinute)}đ/phút', style: TextStyle(color: isActive ? Colors.blue : Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
            if (isActive) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(8)),
                child: const Text('ĐANG DÙNG', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
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
          const Icon(Icons.pause_circle_outline, color: Colors.yellow, size: 72),
          const SizedBox(height: 12),
          const Text('TẠM DỪNG', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.w900, fontSize: 26)),
          const SizedBox(height: 8),
          Text(
            '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.w900, fontSize: 52, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 6),
          Text('Tổng đã dùng: ${_totalPauseUsed ~/ 60}p${(_totalPauseUsed % 60).toString().padLeft(2, '0')}s / ${_maxPauseSeconds ~/ 60} phút',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 6),
          const Text('Hết thời gian tạm dừng sẽ tự kết thúc phiên', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _resumeSession,
              icon: const Icon(Icons.play_arrow, size: 26, color: Colors.white),
              label: const Text('TIẾP TỤC', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final pauseRemaining = _maxPauseSeconds - _totalPauseUsed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(top: BorderSide(color: Color(0xFF1F2937), width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: _openPayment,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: EdgeInsets.zero),
                child: const Text('💰 Nạp thêm', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: _isPaused ? _resumeSession : (pauseRemaining > 0 && _activeServiceId != null ? _pauseSession : null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isPaused ? Colors.blue[700] : (pauseRemaining > 0 ? Colors.orange[700] : Colors.grey[700]),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                child: Text(_isPaused ? '▶ Tiếp tục' : '⏸ Dừng', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: _endSession,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: EdgeInsets.zero),
                child: const Text('⏹ Kết thúc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    _pauseTimer?.cancel();
    _marqueeTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}
