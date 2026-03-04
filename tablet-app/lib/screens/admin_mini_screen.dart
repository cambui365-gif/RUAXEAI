import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/esp32_service.dart';

class AdminMiniScreen extends StatefulWidget {
  const AdminMiniScreen({super.key});

  @override
  State<AdminMiniScreen> createState() => _AdminMiniScreenState();
}

class _AdminMiniScreenState extends State<AdminMiniScreen> {
  final _pinController = TextEditingController();
  bool _authenticated = false;
  Map<String, dynamic>? _stationInfo;
  String _deviceId = '';
  String _stationId = '';
  String _serverUrl = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id') ?? '';
    _stationId = prefs.getString('station_id') ?? '';
    _serverUrl = prefs.getString('server_url') ?? '';

    final res = await ApiService.instance.getStationInfo();
    if (res['success'] == true) {
      setState(() => _stationInfo = res['data']);
    }
  }

  void _authenticate() {
    // Simple PIN: 123456 (should be configurable)
    if (_pinController.text == '123456') {
      setState(() => _authenticated = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN sai'), backgroundColor: Colors.red),
      );
    }
    _pinController.clear();
  }

  Future<void> _testRelays() async {
    final esp32 = Esp32Service.instance;
    for (int i = 1; i <= 6; i++) {
      await esp32.relayOn(i);
      await Future.delayed(const Duration(milliseconds: 500));
      await esp32.relayOff(i);
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _resetActivation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Reset kích hoạt?', style: TextStyle(color: Colors.white)),
        content: const Text('Thiết bị sẽ quay về màn hình kích hoạt.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('station_id');
      await prefs.remove('server_url');
      // Restart app - in real app would use SystemNavigator or restart
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔧 Admin Mini', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: const Color(0xFF111827),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: _authenticated ? _buildDashboard() : _buildPinEntry(),
    );
  }

  Widget _buildPinEntry() {
    return Center(
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1F2937)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, color: Colors.blue, size: 48),
            const SizedBox(height: 16),
            const Text('Nhập PIN Admin', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 24),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF1F2937),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _authenticate(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _authenticate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Xác nhận', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final station = _stationInfo?['station'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station info
          _card('📋 Thông tin trạm', [
            _row('Station ID', _stationId),
            _row('Device ID', _deviceId),
            _row('Server', _serverUrl),
            _row('Trạng thái', station?['status'] ?? '—'),
            _row('ESP32', station?['esp32Status'] ?? '—'),
            _row('Heartbeat', station?['lastHeartbeat'] != null
                ? DateTime.fromMillisecondsSinceEpoch(station!['lastHeartbeat']).toString()
                : '—'),
          ]),

          const SizedBox(height: 16),

          // Controls
          _card('🎛️ Điều khiển', [
            Row(
              children: [
                Expanded(child: _actionButton('🔌 Test Relay', Colors.blue, _testRelays)),
                const SizedBox(width: 8),
                Expanded(child: _actionButton('⛔ Tắt tất cả', Colors.orange, () => Esp32Service.instance.allOff())),
                const SizedBox(width: 8),
                Expanded(child: _actionButton('🔄 Reset', Colors.red, _resetActivation)),
              ],
            ),
          ]),

          const SizedBox(height: 16),

          // Services
          if (_stationInfo?['services'] != null)
            _card('⚙️ Dịch vụ', [
              ...(_stationInfo!['services'] as List).map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(s['icon'] ?? '', style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s['name'], style: const TextStyle(color: Colors.white))),
                    Text('${s['pricePerMinute']}đ/p', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Icon(s['isActive'] ? Icons.check_circle : Icons.cancel,
                        color: s['isActive'] ? Colors.green : Colors.red, size: 18),
                  ],
                ),
              )),
            ]),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12))),
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
      ),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }
}
