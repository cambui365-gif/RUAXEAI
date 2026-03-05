import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> speak(String text) async {
    await init();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  // Pre-defined announcements
  Future<void> welcomePayment() => speak('Vui lòng quét mã QR để thanh toán');
  Future<void> paymentSuccess() => speak('Thanh toán thành công. Bắt đầu rửa xe');
  Future<void> lowBalance() => speak('Sắp hết tiền. Vui lòng nạp thêm để tiếp tục');
  Future<void> sessionEnded() => speak('Phiên rửa xe đã kết thúc. Cảm ơn quý khách');
  Future<void> pauseWarning() => speak('Đang tạm dừng. Nhấn tiếp tục để sử dụng');
  Future<void> switchService(String name) => speak('Đã chuyển sang $name');
}
