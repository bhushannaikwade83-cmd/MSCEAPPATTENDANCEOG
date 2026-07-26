import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Service for network verification and IP tracking
/// Helps detect VPN usage and log network information
class NetworkVerificationService {
  /// Get current network information
  static Future<Map<String, dynamic>> getNetworkInfo() async {
    try {
      if (kIsWeb) {
        return {
          'platform': 'web',
          'networkType': 'web',
          'ipAddress': 'web',
        };
      }

      // Get connectivity type
      final connectivityResult = await Connectivity().checkConnectivity();
      String networkType = 'unknown';
      
      if (connectivityResult.contains(ConnectivityResult.mobile)) {
        networkType = 'mobile';
      } else if (connectivityResult.contains(ConnectivityResult.wifi)) {
        networkType = 'wifi';
      } else if (connectivityResult.contains(ConnectivityResult.ethernet)) {
        networkType = 'ethernet';
      } else if (connectivityResult.contains(ConnectivityResult.none)) {
        networkType = 'none';
      }

      // Get IP address
      String? ipAddress;
      try {
        final response = await http.get(
          Uri.parse('https://api.ipify.org?format=json'),
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          ipAddress = data['ip'] as String?;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Could not fetch IP: $e');
      }

      final networkInfo = {
        'networkType': networkType,
        'ipAddress': ipAddress ?? 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (kDebugMode) {
        debugPrint('🌐 Network Info:');
        debugPrint('   Type: $networkType');
        debugPrint('   IP: ${ipAddress ?? 'unknown'}');
      }

      return networkInfo;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting network info: $e');
      return {
        'networkType': 'unknown',
        'ipAddress': 'unknown',
        'error': e.toString(),
      };
    }
  }

  /// Check if VPN is likely being used (basic detection)
  static Future<bool> isLikelyVPN() async {
    try {
      final networkInfo = await getNetworkInfo();
      final ipAddress = networkInfo['ipAddress'] as String?;
      
      if (ipAddress == null || ipAddress == 'unknown') {
        return false; // Can't determine
      }

      // Check against known VPN/datacenter IP ranges
      // This is a simplified check - for production, use a proper VPN detection API
      final suspiciousPatterns = [
        'vpn',
        'proxy',
        'datacenter',
      ];

      // Try to get IP info (this would require a service like ip-api.com)
      // For now, we'll just log the IP and let server-side handle detection
      
      return false; // Default to false, server can verify
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking VPN: $e');
      return false;
    }
  }

  /// Get network info for logging
  static Future<Map<String, dynamic>> getNetworkInfoForLogging() async {
    final networkInfo = await getNetworkInfo();
    final isVpn = await isLikelyVPN();
    
    return {
      ...networkInfo,
      'isLikelyVpn': isVpn,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
