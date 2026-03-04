import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_service.dart';
import '../models/models.dart';

class PaymentScreen extends StatefulWidget {
  final String stationId;
  final String? sessionId;
  const PaymentScreen({super.key, required this.stationId, this.sessionId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _api = ApiService.instance;
  final _fmt = NumberFormat('#,###', 'vi');
  final _amounts = [30000, 50000, 100000, 200000];

  int _selectedAmount = 30000;
  PaymentQR? _qr;
  bool _loading = false;
  bool _paid = false;
  Timer? _pollTimer;
  int _countdown = 900; // 15 min

  Future<void> _createQR() async {
    setState(() => _loading = true);
    final res = await _api.createPaymentQR(_selectedAmount, sessionId: widget.sessionId);
    if (res['success'] == true) {
      setState(() {
        _qr = PaymentQR.fromJson(res['data']);
        _loading = false;
      });
      _startPolling();
    } else {
      setState(() => _loading = false);
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_qr == null) return;
      final res = await _api.checkPayment(_qr!.refCode);
      if (res['success'] == true && res['data']['status'] == 'COMPLETED') {
        _pollTimer?.cancel();
        setState(() => _paid = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
      }

      // Countdown
      setState(() => _countdown -= 3);
      if (_countdown <= 0) {
        _pollTimer?.cancel();
        if (mounted) Navigator.pop(context, false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _paid ? _buildSuccessView() : _qr != null ? _buildQRView() : _buildAmountSelection(),
        ),
      ),
    );
  }

  Widget _buildAmountSelection() {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💰', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            widget.sessionId != null ? 'Nạp thêm tiền' : 'Nạp tiền để bắt đầu',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 24),

          // Amount buttons
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _amounts.map((amt) => GestureDetector(
              onTap: () => setState(() => _selectedAmount = amt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: _selectedAmount == amt ? Colors.blue.withOpacity(0.15) : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedAmount == amt ? Colors.blue : const Color(0xFF374151),
                    width: _selectedAmount == amt ? 2 : 1,
                  ),
                ),
                child: Text('${_fmt.format(amt)}đ',
                    style: TextStyle(
                      color: _selectedAmount == amt ? Colors.blue : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    )),
              ),
            )).toList(),
          ),

          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF374151)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Quay lại', style: TextStyle(color: Colors.grey)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _createQR,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Hiển thị QR thanh toán', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQRView() {
    final minutes = _countdown ~/ 60;
    final seconds = _countdown % 60;

    return Container(
      width: 500,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Quét mã QR để thanh toán',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 20),

          // QR Code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: _qr!.qrUrl,
              version: QrVersions.auto,
              size: 250,
            ),
          ),

          const SizedBox(height: 16),

          Text('${_fmt.format(_qr!.amount)}đ',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.blue)),
          const SizedBox(height: 8),

          // Transfer content
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Nội dung CK: ${_qr!.transferContent}',
                style: const TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 13)),
          ),

          const SizedBox(height: 16),

          // Countdown + checking
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
              const SizedBox(width: 8),
              Text('Đang chờ thanh toán... ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),

          const SizedBox(height: 20),

          TextButton(
            onPressed: () { _pollTimer?.cancel(); Navigator.pop(context, false); },
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Container(
      width: 400,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 80),
          const SizedBox(height: 16),
          const Text('Thanh toán thành công!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          Text('+${_fmt.format(_selectedAmount)}đ', style: const TextStyle(fontSize: 28, color: Colors.green, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
