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
  bool _loading = true;
  Timer? _timer;
  Timer? _heartbeatTimer;
  int _elapsedSeconds = 0;
  int _adminTapCount = 0;
  DateTime? _lastAdminTap;

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
          if (_activeServiceId != null) _startTimer();
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

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
      // Check balance every 10s
      if (_elapsedSeconds % 10 == 0 && _session != null) {
        _checkBalance();
      }
    });
  }

  Future<void> _checkBalance() async {
    if (_session == null) return;
    final res = await _api.getSessionBalance(_session!.id);
    if (res['success'] == true) {
      final remaining = res['data']['remainingBalance'] ?? 0;
      if (remaining <= 0) {
        _endSession();
      }
    }
  }

  Future<void> _openPayment() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PaymentScreen(
        stationId: widget.stationId,
        sessionId: _session?.id,
      )),
    );

    if (result == true) {
      await _loadStationInfo();
    }
  }

  Future<void> _selectService(ServiceItem service) async {
    if (_session == null) return;
    if (!service.isActive) return;

    final res = await _api.startService(_session!.id, service.id);
    if (res['success'] == true) {
      final relayIndex = res['data']['relayIndex'];

      // Turn off previous relay, turn on new one
      await _esp32.allOff();
      await _esp32.relayOn(relayIndex);

      setState(() => _activeServiceId = service.id);
      _startTimer();
      _loadStationInfo();
    }
  }

  Future<void> _pauseSession() async {
    if (_session == null) return;
    final res = await _api.pauseSession(_session!.id);
    if (res['success'] == true) {
      await _esp32.allOff();
      _timer?.cancel();
      setState(() => _activeServiceId = null);
      _loadStationInfo();
    }
  }

  Future<void> _resumeSession() async {
    if (_session == null) return;
    final res = await _api.resumeSession(_session!.id);
    if (res['success'] == true) {
      _loadStationInfo();
    }
  }

  Future<void> _endSession() async {
    if (_session == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Kết thúc phiên?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Số dư còn lại: ${_fmt.format(_session!.remainingBalance)}đ\nSẽ được hoàn lại.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kết thúc', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _esp32.allOff();
    await _api.endSession(_session!.id);
    _timer?.cancel();
    setState(() {
      _session = null;
      _activeServiceId = null;
      _elapsedSeconds = 0;
    });
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.blue)));
    }

    final hasSession = _session != null;
    final isPaused = _session?.isPaused ?? false;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Main content
            Expanded(
              child: hasSession ? _buildActiveView(isPaused) : _buildWelcomeView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      onTap: _handleAdminTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
        ),
        child: Row(
          children: [
            const Text('🚗', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            const Text('RUAXEAI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            const Spacer(),
            if (_session != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Text(
                  'Số dư: ${_fmt.format(_session!.remainingBalance)}đ',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
            ],
            // ESP32 status
            Icon(
              _esp32.isConnected ? Icons.usb : Icons.usb_off,
              color: _esp32.isConnected ? Colors.green : Colors.red,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🚗', style: TextStyle(fontSize: 80)),
          const SizedBox(height: 24),
          const Text('Chào mừng đến trạm rửa xe!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Vui lòng nạp tiền để bắt đầu sử dụng',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 40),
          SizedBox(
            width: 300,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: _openPayment,
              icon: const Icon(Icons.qr_code, size: 28, color: Colors.white),
              label: const Text('NẠP TIỀN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Tối thiểu 30.000đ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildActiveView(bool isPaused) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Left: Services grid
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chọn dịch vụ:', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.3,
                    ),
                    itemCount: _services.length,
                    itemBuilder: (ctx, i) => _buildServiceCard(_services[i]),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // Right: Status + Controls
          Expanded(
            flex: 2,
            child: Column(
              children: [
                // Active service info
                if (_activeServiceId != null) _buildActiveServiceCard(),
                if (isPaused) _buildPausedCard(),

                const Spacer(),

                // Controls
                _buildControlButtons(isPaused),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(ServiceItem service) {
    final isActive = _activeServiceId == service.id;
    return GestureDetector(
      onTap: service.isActive ? () => _selectService(service) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withOpacity(0.15) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? Colors.blue : const Color(0xFF1F2937),
            width: isActive ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(service.icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(service.name,
                style: TextStyle(
                    color: service.isActive ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.w800, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('${_fmt.format(service.pricePerMinute)}đ/phút',
                style: TextStyle(color: isActive ? Colors.blue : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveServiceCard() {
    final service = _services.firstWhere((s) => s.id == _activeServiceId, orElse: () => _services.first);
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(service.icon, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(service.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          Text('${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w900, fontSize: 36, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text('${_fmt.format(service.pricePerMinute)}đ/phút', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPausedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.yellow.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.yellow.withOpacity(0.3)),
      ),
      child: const Column(
        children: [
          Icon(Icons.pause_circle, color: Colors.yellow, size: 40),
          SizedBox(height: 8),
          Text('TẠM DỪNG', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.w900, fontSize: 18)),
          SizedBox(height: 4),
          Text('Tối đa 5 phút', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildControlButtons(bool isPaused) {
    return Column(
      children: [
        // Deposit more
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _openPayment,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('NẠP THÊM', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Pause / Resume
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: isPaused ? _resumeSession : (_activeServiceId != null ? _pauseSession : null),
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white),
            label: Text(isPaused ? 'TIẾP TỤC' : 'TẠM DỪNG',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPaused ? Colors.blue[700] : Colors.orange[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // End session
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _endSession,
            icon: const Icon(Icons.stop, color: Colors.white),
            label: const Text('KẾT THÚC', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
