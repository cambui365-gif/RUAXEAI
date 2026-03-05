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
      if (_session == null || _activeServiceId == null) return;
      
      final service = _services.firstWhere((s) => s.id == _activeServiceId, orElse: () => _services.first);
      final costPerSecond = service.pricePerMinute / 60.0;
      
      setState(() {
        _elapsedSeconds++;
        // Deduct balance every second
        if (_session != null) {
          _session = Session(
            id: _session!.id,
            stationId: _session!.stationId,
            status: _session!.status,
            totalDeposited: _session!.totalDeposited,
            totalUsed: _session!.totalUsed + costPerSecond.floor(),
            remainingBalance: (_session!.remainingBalance - costPerSecond).floor(),
            currentServiceId: _session!.currentServiceId,
            currentServiceStartTime: _session!.currentServiceStartTime,
            isPaused: _session!.isPaused,
          );
          
          // Check if balance depleted
          if (_session!.remainingBalance <= 0) {
            _endSession();
          }
        }
      });
      
      // Sync with server every 10s
      if (_elapsedSeconds % 10 == 0) {
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

  DateTime? _lastServiceTap;
  
  Future<void> _selectService(ServiceItem service) async {
    if (_session == null) return;
    if (!service.isActive) return;

    // Prevent double-tap
    final now = DateTime.now();
    if (_lastServiceTap != null && now.difference(_lastServiceTap!).inMilliseconds < 500) {
      return;
    }
    _lastServiceTap = now;

    // If already active on another service, confirm switch
    if (_activeServiceId != null && _activeServiceId != service.id) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          title: const Text('Xác nhận chuyển dịch vụ', style: TextStyle(color: Colors.white)),
          content: Text(
            'Xác nhận chuyển qua ${service.name}?',
            style: const TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Có', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
    }

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
          'Số dư còn lại: ${_fmt.format(_session!.remainingBalance)}đ\n\n⚠️ Số dư còn lại sẽ KHÔNG được hoàn lại. Bạn có chắc muốn kết thúc?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withOpacity(0.3), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_fmt.format(_session!.remainingBalance)}đ',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 32),
                    ),
                    if (_activeServiceId != null) ...[
                      const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final service = _services.firstWhere((s) => s.id == _activeServiceId, orElse: () => _services.first);
                          final remainingSeconds = (_session!.remainingBalance / (service.pricePerMinute / 60.0)).floor();
                          final minutes = remainingSeconds ~/ 60;
                          final seconds = remainingSeconds % 60;
                          return Text(
                            'Còn ~$minutes phút $seconds giây',
                            style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w600),
                          );
                        },
                      ),
                    ],
                  ],
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated car wash icon
            TweenAnimationBuilder(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(seconds: 2),
              builder: (context, double value, child) {
                return Transform.scale(
                  scale: 0.8 + (value * 0.2),
                  child: Opacity(
                    opacity: value,
                    child: Container(
                      padding: const EdgeInsets.all(32),
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
                      child: const Text('🚗💨', style: TextStyle(fontSize: 100)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            
            // Title with gradient
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [Colors.blue[300]!, Colors.blue[600]!],
              ).createShader(bounds),
              child: const Text(
                'RUAXEAI',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Trạm rửa xe tự phục vụ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 1)),
            
            const SizedBox(height: 48),
            
            // Services showcase
            Container(
              width: 600,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Column(
                children: [
                  const Text('Dịch vụ có sẵn:', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: _services.where((s) => s.isActive).map((service) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(service.icon, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(service.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text('${_fmt.format(service.pricePerMinute)}đ/phút', style: const TextStyle(color: Colors.blue, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // CTA Button
            SizedBox(
              width: 350,
              height: 70,
              child: ElevatedButton(
                onPressed: _openPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 8,
                  shadowColor: Colors.blue.withOpacity(0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.qr_code, size: 36, color: Colors.white),
                    SizedBox(width: 16),
                    Text('BẮT ĐẦU SỬ DỤNG', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Nạp tối thiểu 10.000đ', style: TextStyle(color: Colors.grey[600], fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('💳 Thanh toán qua QR Code - Nhanh chóng & An toàn', 
                style: TextStyle(color: Colors.blue[300], fontSize: 14)),
          ],
        ),
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.blue : const Color(0xFF1F2937),
            width: isActive ? 3 : 1,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(service.icon, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text(service.name,
                style: TextStyle(
                    color: service.isActive ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.w900, fontSize: 18),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('${_fmt.format(service.pricePerMinute)}đ/phút',
                style: TextStyle(color: isActive ? Colors.blue : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
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
          height: 40,
          child: ElevatedButton.icon(
            onPressed: _openPayment,
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text('Nạp thêm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Pause / Resume
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton.icon(
            onPressed: isPaused ? _resumeSession : (_activeServiceId != null ? _pauseSession : null),
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white, size: 18),
            label: Text(isPaused ? 'Tiếp tục' : 'Tạm dừng',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPaused ? Colors.blue[700] : Colors.orange[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // End session
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton.icon(
            onPressed: _endSession,
            icon: const Icon(Icons.stop, color: Colors.white, size: 18),
            label: const Text('Kết thúc', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
