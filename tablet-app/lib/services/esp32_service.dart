import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// ESP32 USB Serial communication service
/// Uses usb_serial plugin for Android USB OTG
class Esp32Service {
  static final Esp32Service instance = Esp32Service._();
  Esp32Service._();

  dynamic _port; // UsbPort from usb_serial
  bool _connected = false;
  final _statusController = StreamController<Esp32Status>.broadcast();
  final _responseController = StreamController<Map<String, dynamic>>.broadcast();
  String _buffer = '';

  bool get isConnected => _connected;
  Stream<Esp32Status> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get responseStream => _responseController.stream;

  /// Try to connect to ESP32 via USB Serial
  Future<bool> connect() async {
    try {
      // Import dynamically to avoid crash on non-Android
      // In real app, use usb_serial package
      // For now, simulate connection
      _connected = true;
      _statusController.add(Esp32Status(connected: true, relays: List.filled(6, false)));
      return true;
    } catch (e) {
      _connected = false;
      _statusController.add(Esp32Status(connected: false, relays: List.filled(6, false)));
      return false;
    }
  }

  /// Send command to ESP32
  Future<Map<String, dynamic>?> sendCommand(String action, {int? relay}) async {
    if (!_connected) return null;

    final cmd = <String, dynamic>{'action': action};
    if (relay != null) cmd['relay'] = relay;

    try {
      final json = jsonEncode(cmd) + '\n';

      if (_port != null) {
        // Real USB Serial write
        await _port.write(Uint8List.fromList(utf8.encode(json)));
      }

      // Wait for response (with timeout)
      final response = await _responseController.stream
          .timeout(const Duration(seconds: 3))
          .first;
      return response;
    } catch (e) {
      return {'ok': false, 'error': 'Timeout or communication error'};
    }
  }

  /// Turn on a relay (1-6)
  Future<bool> relayOn(int relay) async {
    final res = await sendCommand('ON', relay: relay);
    return res?['ok'] == true;
  }

  /// Turn off a relay (1-6)
  Future<bool> relayOff(int relay) async {
    final res = await sendCommand('OFF', relay: relay);
    return res?['ok'] == true;
  }

  /// Turn off all relays
  Future<bool> allOff() async {
    final res = await sendCommand('OFF_ALL');
    return res?['ok'] == true;
  }

  /// Get relay status
  Future<Map<String, dynamic>?> getStatus() async {
    return sendCommand('STATUS');
  }

  /// Ping ESP32
  Future<bool> ping() async {
    final res = await sendCommand('PING');
    return res?['ok'] == true;
  }

  /// Handle incoming serial data
  void _onData(Uint8List data) {
    _buffer += utf8.decode(data);

    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);

      if (line.isNotEmpty) {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          _responseController.add(json);

          // Update status if it's a status response
          if (json['action'] == 'STATUS' && json['relays'] != null) {
            final relays = (json['relays'] as List).map((e) => e as bool).toList();
            _statusController.add(Esp32Status(connected: true, relays: relays));
          }
        } catch (_) {}
      }
    }
  }

  void dispose() {
    _statusController.close();
    _responseController.close();
  }
}

class Esp32Status {
  final bool connected;
  final List<bool> relays;

  Esp32Status({required this.connected, required this.relays});
}
