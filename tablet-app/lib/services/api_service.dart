import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  String _baseUrl = '';
  String _stationId = '';
  String _tabletId = '';

  void configure(String baseUrl, String stationId, String tabletId) {
    _baseUrl = baseUrl;
    _stationId = stationId;
    _tabletId = tabletId;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Station-ID': _stationId,
    'X-Tablet-ID': _tabletId,
  };

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- Station ---
  Future<Map<String, dynamic>> getStationInfo() => _get('/api/station/info');

  Future<Map<String, dynamic>> sendHeartbeat({
    required bool esp32Connected,
    required String networkStatus,
    required String appVersion,
    String? activeSessionId,
    List<bool>? relayStates,
  }) => _post('/api/station/heartbeat', {
    'esp32Connected': esp32Connected,
    'networkStatus': networkStatus,
    'appVersion': appVersion,
    'activeSessionId': activeSessionId,
    'relayStates': relayStates ?? List.filled(6, false),
  });

  // --- Session ---
  Future<Map<String, dynamic>> createSession(int amount, {String? sepayRef}) =>
      _post('/api/station/session/create', {'amount': amount, 'sepayRef': sepayRef});

  Future<Map<String, dynamic>> addDeposit(String sessionId, int amount, {String? sepayRef}) =>
      _post('/api/station/session/deposit', {'sessionId': sessionId, 'amount': amount, 'sepayRef': sepayRef});

  Future<Map<String, dynamic>> startService(String sessionId, String serviceId) =>
      _post('/api/station/session/start-service', {'sessionId': sessionId, 'serviceId': serviceId});

  Future<Map<String, dynamic>> pauseSession(String sessionId) =>
      _post('/api/station/session/pause', {'sessionId': sessionId});

  Future<Map<String, dynamic>> resumeSession(String sessionId) =>
      _post('/api/station/session/resume', {'sessionId': sessionId});

  Future<Map<String, dynamic>> endSession(String sessionId) =>
      _post('/api/station/session/end', {'sessionId': sessionId});

  Future<Map<String, dynamic>> getSessionBalance(String sessionId) =>
      _get('/api/station/session/$sessionId/balance');

  // --- Payment ---
  Future<Map<String, dynamic>> createPaymentQR(int amount, {String? sessionId}) =>
      _post('/api/payment/create-qr', {
        'stationId': _stationId,
        'amount': amount,
        'sessionId': sessionId,
      });

  Future<Map<String, dynamic>> checkPayment(String refCode) =>
      _get('/api/payment/check/$refCode');
}
