import 'package:http/http.dart' as http;
import 'dart:async';

/// Monitors backend connection status and logs to console
class BackendMonitorService {
  static const String _backendUrl = 'http://192.0.0.2:5001';
  static Timer? _monitorTimer;
  static bool _isConnected = false;

  /// Start monitoring backend connection
  static Future<void> startMonitoring() async {
    print('🔍 Starting backend connection monitor...');

    // Check immediately on startup
    await _checkBackendHealth();

    // Check every 5 seconds
    _monitorTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkBackendHealth();
    });
  }

  /// Stop monitoring
  static void stopMonitoring() {
    _monitorTimer?.cancel();
    print('⏹️ Backend monitor stopped');
  }

  /// Check if backend is reachable
  static Future<void> _checkBackendHealth() async {
    try {
      print('🔄 Checking backend health...');
      final response = await http.get(
        Uri.parse('$_backendUrl/api/health'),
      ).timeout(const Duration(seconds: 10));  // 🔥 Increased timeout

      print('📡 Backend response: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (!_isConnected) {
          _isConnected = true;
          print('✅ BACKEND CONNECTED - Status: ONLINE 🟢');
          print('   URL: $_backendUrl');
          print('   Status: Ready for registration');
        }
      } else {
        _setDisconnected('Status: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Backend check error: $e');
      _setDisconnected('Error: $e');
    }
  }

  static void _setDisconnected(String reason) {
    if (_isConnected) {
      _isConnected = false;
      print('❌ BACKEND DISCONNECTED - $reason 🔴');
      print('   URL: $_backendUrl (unreachable)');
      print('   Action: Make sure backend is running!');
    }
  }

  /// Get connection status
  static String getStatus() {
    return _isConnected ? '✅ CONNECTED' : '❌ DISCONNECTED';
  }

  /// Get connection status for display
  static bool isConnected() => _isConnected;
}
