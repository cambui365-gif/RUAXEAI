import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';

class ActivationScreen extends StatefulWidget {
  final Function(String stationId) onActivated;
  const ActivationScreen({super.key, required this.onActivated});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _serverController = TextEditingController(text: 'https://');
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _generateDeviceId();
  }

  Future<void> _generateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      deviceId = 'TAB-${const Uuid().v4().substring(0, 8).toUpperCase()}';
      await prefs.setString('device_id', deviceId);
    }
    setState(() => _deviceId = deviceId!);
  }

  Future<void> _activate() async {
    final serverUrl = _serverController.text.trim().replaceAll(RegExp(r'/$'), '');
    final code = _codeController.text.trim().toUpperCase();

    if (serverUrl.isEmpty || code.isEmpty) {
      setState(() => _error = 'Vui lòng nhập đầy đủ thông tin');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Test connection to server
      final api = ApiService.instance;
      api.configure(serverUrl, code, _deviceId);

      final res = await api.getStationInfo();

      if (res['success'] == true) {
        // Save activation
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server_url', serverUrl);
        await prefs.setString('station_id', code);
        await prefs.setString('tablet_id', _deviceId);

        widget.onActivated(code);
      } else {
        setState(() => _error = res['error'] ?? 'Mã kích hoạt không hợp lệ');
      }
    } catch (e) {
      setState(() => _error = 'Không kết nối được server: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF1F2937)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              const Text('🚗', style: TextStyle(fontSize: 60)),
              const SizedBox(height: 16),
              const Text('RUAXEAI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
              const Text('Kích hoạt thiết bị', style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 8),

              // Device ID
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices, color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    Text('Device ID: $_deviceId',
                        style: const TextStyle(color: Colors.blue, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Server URL
              _buildField('Server URL', _serverController, 'https://your-server.com', Icons.cloud),
              const SizedBox(height: 16),

              // Activation Code (= Station ID)
              _buildField('Mã trạm (Station ID)', _codeController, 'station-001', Icons.key),
              const SizedBox(height: 24),

              // Error
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                    ],
                  ),
                ),

              // Activate button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _activate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Kích hoạt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[700]),
            prefixIcon: Icon(icon, color: Colors.grey, size: 20),
            filled: true,
            fillColor: const Color(0xFF1F2937),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
