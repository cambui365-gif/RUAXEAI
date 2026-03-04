import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/activation_screen.dart';
import 'screens/kiosk_screen.dart';
import 'screens/admin_mini_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Full screen, hide system bars
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

  // Keep screen on
  WakelockPlus.enable();

  runApp(const RuaxeaiApp());
}

class RuaxeaiApp extends StatelessWidget {
  const RuaxeaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RUAXEAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A0F1A),
        fontFamily: 'Roboto',
      ),
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _loading = true;
  bool _activated = false;
  String? _stationId;

  @override
  void initState() {
    super.initState();
    _checkActivation();
  }

  Future<void> _checkActivation() async {
    final prefs = await SharedPreferences.getInstance();
    final stationId = prefs.getString('station_id');
    final serverUrl = prefs.getString('server_url');

    if (stationId != null && serverUrl != null) {
      ApiService.instance.configure(serverUrl, stationId, prefs.getString('tablet_id') ?? '');
      setState(() {
        _activated = true;
        _stationId = stationId;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  void _onActivated(String stationId) {
    setState(() {
      _activated = true;
      _stationId = stationId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    if (!_activated) {
      return ActivationScreen(onActivated: _onActivated);
    }

    return KioskScreen(stationId: _stationId!);
  }
}
