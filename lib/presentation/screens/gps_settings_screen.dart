import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/gps_attendance_constants.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/geofence_service.dart';
import '../../services/institute_realtime_sync_service.dart';
import 'main_navigation_screen.dart';

class GpsSettingsScreen extends StatefulWidget {
  static const routeName = '/gps-settings';
  final bool isMandatory;
  final bool fromLogin;

  const GpsSettingsScreen({
    super.key,
    this.isMandatory = false,
    this.fromLogin = false,
  });

  @override
  State<GpsSettingsScreen> createState() => _GpsSettingsScreenState();
}

class _GpsSettingsScreenState extends State<GpsSettingsScreen> with WidgetsBindingObserver {
  User? get _currentUser => appDb.auth.currentUser;
  bool _isAdmin = false;
  bool _isCheckingRole = true;
  String? _instituteId; // Store user's institute ID
  final _formKey = GlobalKey<FormState>();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController(
        text: kAttendanceFenceRadiusMeters.toStringAsFixed(0),
      );
  final GeofenceService _geofenceService = GeofenceService();
  bool _isLoading = false;
  bool _isLocked = false; // Track if location is locked (after lat/lng are set)
  bool _hasLocation = false; // Track if location coordinates exist
  late bool _isMandatory; // Mandatory GPS setup (from first login)
  late bool _fromLogin; // Coming from login flow

  /// Poll server so web dashboard unlock / re-lock + new coordinates appear in the app.
  Timer? _serverPollTimer;
  String? _lastServerFingerprint;
  StreamSubscription<InstituteSyncEvent>? _syncSubscription;
  Timer? _syncDebounce;

  static String _fingerprintForRow(Map<String, dynamic>? row) {
    if (row == null) return '__none__';
    final lat = row['latitude'];
    final lng = row['longitude'];
    final locked = row['is_locked'] == true;
    return '$locked|${lat ?? ''}|${lng ?? ''}';
  }

  void _startServerPolling() {
    _serverPollTimer?.cancel();
    _serverPollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_isAdmin || _instituteId == null || _isLoading) return;
      _loadCurrentSettings(silent: true);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isMandatory = widget.isMandatory;
    _fromLogin = widget.fromLogin;

    if (kDebugMode) {
      debugPrint('🛰️ GPS Settings: mandatory=$_isMandatory, fromLogin=$_fromLogin');
    }

    _loadUserInstituteId();
  }

  @override
  void dispose() {
    _serverPollTimer?.cancel();
    _syncDebounce?.cancel();
    _syncSubscription?.cancel();
    final iid = _instituteId;
    if (iid != null && iid.isNotEmpty) {
      InstituteRealtimeSyncService.instance.release(iid);
    }
    WidgetsBinding.instance.removeObserver(this);
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _isAdmin && _instituteId != null) {
      _loadCurrentSettings(silent: true);
    }
  }

  Future<void> _loadUserInstituteId() async {
    final u = _currentUser;
    if (u == null) {
      setState(() {
        _isCheckingRole = false;
        _isAdmin = false;
      });
      return;
    }

    try {
      final row = await appDb.from('profiles').select('institute_id,role').eq('id', u.id).maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _isCheckingRole = false;
          _isAdmin = false;
        });
        return;
      }
      _instituteId = row['institute_id'] as String?;
      final role = (row['role'] as String?) ?? '';
      setState(() {
        _isAdmin = role == 'admin';
        _isCheckingRole = false;
      });
      if (_isAdmin && _instituteId != null) {
        await InstituteRealtimeSyncService.instance.retain(_instituteId!);
        _syncSubscription?.cancel();
        _syncSubscription = InstituteRealtimeSyncService.instance
            .watch(_instituteId!)
            .listen((event) {
          if (!mounted) return;
          if (event.type == 'gps' || event.type == 'institute') {
            _syncDebounce?.cancel();
            _syncDebounce = Timer(const Duration(milliseconds: 500), () {
              if (!mounted) return;
              _loadCurrentSettings(silent: true);
            });
          }
        });
        await _loadCurrentSettings();
        _startServerPolling();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking role: $e');
      if (mounted) setState(() {
        _isCheckingRole = false;
        _isAdmin = false;
      });
    }
  }

  Future<void> _loadCurrentSettings({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final cu = _currentUser;
      Map<String, dynamic>? row;
      if (_instituteId != null && cu != null) {
        row = await appDb
            .from('gps_settings')
            .select()
            .eq('institute_id', _instituteId!)
            .eq('admin_id', cu.id)
            .maybeSingle();
        if (!mounted) return;

        final fp = _fingerprintForRow(row);
        if (silent && fp == _lastServerFingerprint) {
          return;
        }
        _lastServerFingerprint = fp;

        if (row != null) {
          final r = row;
          final lat = r['latitude'];
          final lng = r['longitude'];
          final hasLoc = lat != null &&
              lng != null &&
              lat.toString().isNotEmpty &&
              lng.toString().isNotEmpty &&
              (lat as num) != 0.0 &&
              (lng as num) != 0.0;
          if (mounted) {
            setState(() {
              _hasLocation = hasLoc;
              if (hasLoc) {
                _latController.text = lat.toString();
                _lngController.text = lng.toString();
                _isLocked = r['is_locked'] == true;
              } else {
                _isLocked = false;
              }
              _radiusController.text = kAttendanceFenceRadiusMeters.toStringAsFixed(0);
            });
          }
          final currentRadius = (r['radius'] as num?)?.toDouble() ?? 0.0;
          if ((currentRadius >= 24.9 && currentRadius <= 25.1) ||
              (currentRadius >= 29.0 && currentRadius <= 31.0)) {
            await appDb
                .from('gps_settings')
                .update({
                  'radius': kAttendanceFenceRadiusMeters,
                  'extra': {
                    'radiusMigrated_at': DateTime.now().toUtc().toIso8601String(),
                    'from': currentRadius,
                  },
                })
                .eq('institute_id', _instituteId!)
                .eq('admin_id', cu.id);
          }
        } else {
          if (mounted) {
            setState(() {
              _radiusController.text = kAttendanceFenceRadiusMeters.toStringAsFixed(0);
              _hasLocation = false;
              _isLocked = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _radiusController.text = kAttendanceFenceRadiusMeters.toStringAsFixed(0);
            _hasLocation = false;
            _isLocked = false;
          });
        }
        _lastServerFingerprint = _fingerprintForRow(null);
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    } finally {
      if (!silent && mounted) setState(() => _isLoading = false);
    }
  }

  // 2. Get Current Location (Auto-fill)
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        if (!mounted) return;
        _latController.text = position.latitude.toString();
        _lngController.text = position.longitude.toString();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(
                          child: Text(
                        'Location fetched!',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      )),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Important: Capture your location only while physically at your institute premises. '
                    'Do not set the attendance point from home or elsewhere.\n'
                    '(महत्वाचे: ही जागा फक्त संस्थेच्या परिसरातून घ्या.)',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
              backgroundColor: AppTheme.accentGreen,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text("Location permission denied"),
                ],
              ),
              backgroundColor: AppTheme.accentRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 3. Save Settings to Firestore
  Future<void> _saveSettings() async {
    final latStr = _latController.text.trim();
    final lngStr = _lngController.text.trim();
    final latVal = double.tryParse(latStr);
    final lngVal = double.tryParse(lngStr);
    if (latStr.isEmpty || lngStr.isEmpty || latVal == null || lngVal == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.location_off_outlined, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tap “Use Current Location” to fetch coordinates before saving.',
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    
    if (_instituteId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text("Error: Institute ID not found. Please login again."),
              ],
            ),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Save to admin-specific GPS settings (each admin has their own geo-fencing)
      if (_currentUser == null) {
        throw 'User not authenticated';
      }
      
      final cu = _currentUser;
      if (cu == null) throw 'User not authenticated';
      final existingRow = await appDb
          .from('gps_settings')
          .select()
          .eq('institute_id', _instituteId!)
          .eq('admin_id', cu.id)
          .maybeSingle();
      if (!mounted) return;

      final existingData = existingRow;
      final existingLat = existingData?['latitude'];
      final existingLng = existingData?['longitude'];
      final hasExistingLocation = existingLat != null &&
          existingLng != null &&
          (existingLat as num) != 0.0 &&
          (existingLng as num) != 0.0;
      final isLocationLocked = existingData != null && hasExistingLocation && (existingData['is_locked'] == true);
      
      // If location is already set and locked, cannot change
      if (isLocationLocked) {
        throw 'Location is locked. Contact super admin to unlock for changes.';
      }

      // Radius is fixed at the system attendance fence distance
      final radiusToSave = kAttendanceFenceRadiusMeters;

      final ts = DateTime.now().toUtc().toIso8601String();
      final cu2 = _currentUser!;
      await appDb.from('gps_settings').upsert({
        'institute_id': _instituteId,
        'admin_id': cu2.id,
        'latitude': latVal,
        'longitude': lngVal,
        'radius': radiusToSave,
        'is_locked': true,
        'locked_at': ts,
        'locked_by': cu2.id,
        'extra': {'updated_at': ts},
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text("GPS Settings Saved!"),
              ],
            ),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        setState(() {
          _hasLocation = true;
          _isLocked = true; // Lock location after saving
        });
        await _loadCurrentSettings(silent: true);

        // If coming from login with mandatory GPS setup, navigate to home
        if (_fromLogin && _isMandatory && mounted) {
          if (kDebugMode) debugPrint('✅ GPS configured from login. Navigating to home...');

          // Navigate to main app after short delay to show success message
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              MainNavigationScreen.routeName,
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving: $e"),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isCheckingRole) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
        body: const SafeArea(
          top: false,
          child: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryBlue),
          ),
        ),
      );
    }

    final blockBackUntilGpsSaved = _isAdmin && !_hasLocation;

    return PopScope(
      canPop: !blockBackUntilGpsSaved && Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && blockBackUntilGpsSaved && mounted) {
          if (kDebugMode) debugPrint('⚠️ Cannot exit until admin GPS is saved');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Save your GPS zone before leaving this screen.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(isDark),
                  SizedBox(height: 20.h),
                  _buildInfoCard(isDark),
                  SizedBox(height: 20.h),
                  _buildRadiusLockBanner(isDark),
                  SizedBox(height: 20.h),
                  if (_isLocked) _buildLocationLockBanner(isDark),
                  if (_isLocked) SizedBox(height: 20.h),
                  _buildCoordinatesSection(isDark),
                  SizedBox(height: 28.h),
                  _buildRadiusSection(isDark),
                  SizedBox(height: 32.h),
                  _buildSaveButton(isDark),
                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
            AppTheme.primaryBlue.withOpacity(isDark ? 0.08 : 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.1 : 0.06),
            blurRadius: 16.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryBlue.withOpacity(0.3),
                  AppTheme.primaryBlue.withOpacity(0.15),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(Icons.location_on_rounded, color: AppTheme.primaryBlue, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS Attendance Zone',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.textDark,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Configure your location boundary',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentSaffron.withOpacity(isDark ? 0.1 : 0.05),
            AppTheme.accentSaffron.withOpacity(isDark ? 0.05 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: AppTheme.accentSaffron.withOpacity(isDark ? 0.25 : 0.15),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(14.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: AppTheme.accentSaffron.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(Icons.info_rounded, color: AppTheme.accentSaffron, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personal Attendance Zone',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Each admin has their own geo-fencing settings. You can only mark attendance within your configured radius.',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusLockBanner(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.06),
            AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.4 : 0.2),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(14.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(Icons.lock_rounded, color: AppTheme.primaryBlue, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Radius Fixed at ${kAttendanceFenceRadiusMeters.toStringAsFixed(0)} m',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Attendance may only be marked within about ${kAttendanceMaxEffectiveFenceMeters.toStringAsFixed(0)} m of your location (nominal ${kAttendanceFenceRadiusMeters.toStringAsFixed(0)} m + GPS tolerance).',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationLockBanner(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentRed.withOpacity(isDark ? 0.12 : 0.06),
            AppTheme.accentRed.withOpacity(isDark ? 0.06 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppTheme.accentRed.withOpacity(isDark ? 0.4 : 0.2),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(14.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: AppTheme.accentRed.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(Icons.lock_outline_rounded, color: AppTheme.accentRed, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location Locked',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Coordinates are locked after being set. Contact super admin to unlock for changes.',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinatesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(Icons.map_rounded, color: AppTheme.primaryGreen, size: 18.sp),
            ),
            SizedBox(width: 8.w),
            Text(
              'School Coordinates',
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(
              child: _buildModernField(
                controller: _latController,
                label: 'Latitude',
                icon: Icons.location_on_outlined,
                isDark: isDark,
                enabled: false,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: _buildModernField(
                controller: _lngController,
                label: 'Longitude',
                icon: Icons.location_on_outlined,
                isDark: isDark,
                enabled: false,
              ),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        _buildLocationButton(isDark),
      ],
    );
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        fontSize: 13.sp,
        color: isDark ? Colors.white : AppTheme.textDark,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryGreen, size: 18.sp),
        filled: true,
        fillColor: isDark
            ? Colors.white.withOpacity(0.05)
            : AppTheme.primaryGreen.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(
            color: AppTheme.primaryGreen.withOpacity(isDark ? 0.2 : 0.1),
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(
            color: AppTheme.primaryGreen.withOpacity(isDark ? 0.15 : 0.08),
            width: 1.5,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(
            color: AppTheme.primaryGreen.withOpacity(isDark ? 0.1 : 0.05),
            width: 1.5,
          ),
        ),
        labelStyle: TextStyle(
          fontSize: 12.sp,
          color: isDark ? Colors.white70 : AppTheme.textGray,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      ),
    );
  }

  Widget _buildLocationButton(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withOpacity(0.1),
            AppTheme.primaryGreen.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: AppTheme.primaryGreen.withOpacity(isDark ? 0.4 : 0.2),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (_isLoading || _isLocked) ? null : _getCurrentLocation,
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.my_location_rounded,
                  color: AppTheme.primaryGreen,
                  size: 20.sp,
                ),
                SizedBox(width: 8.w),
                Text(
                  'Use Current Location',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadiusSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(Icons.radar_rounded, color: AppTheme.accentOrange, size: 18.sp),
            ),
            SizedBox(width: 8.w),
            Text(
              'Allowed Radius',
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        TextFormField(
          controller: _radiusController,
          enabled: false,
          readOnly: true,
          keyboardType: TextInputType.number,
          style: TextStyle(
            fontSize: 13.sp,
            color: isDark ? Colors.white70 : AppTheme.textGray,
          ),
          decoration: InputDecoration(
            labelText: 'Radius in Meters',
            prefixIcon: Icon(Icons.radar_rounded, color: AppTheme.accentOrange, size: 18.sp),
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.03)
                : AppTheme.accentOrange.withOpacity(0.03),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(
                color: AppTheme.accentOrange.withOpacity(isDark ? 0.15 : 0.08),
                width: 1.5,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(
                color: AppTheme.accentOrange.withOpacity(isDark ? 0.15 : 0.08),
                width: 1.5,
              ),
            ),
            labelStyle: TextStyle(
              fontSize: 12.sp,
              color: isDark ? Colors.white70 : AppTheme.textGray,
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          ),
          validator: (v) {
            if (v!.isEmpty) return 'Required';
            final radius = double.tryParse(v);
            if (radius == null) return 'Invalid number';
            if (radius != kAttendanceFenceRadiusMeters) {
              return 'Radius must be exactly ${kAttendanceFenceRadiusMeters.toStringAsFixed(0)} m';
            }
            return null;
          },
        ),
        SizedBox(height: 10.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: AppTheme.accentOrange.withOpacity(isDark ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text(
            'This value is fixed and cannot be changed.',
            style: TextStyle(
              fontSize: 11.sp,
              color: isDark ? Colors.white70 : AppTheme.textGray,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _isLocked ? Colors.grey.withOpacity(0.5) : AppTheme.primaryBlue,
            _isLocked
                ? Colors.grey.withOpacity(0.4)
                : AppTheme.primaryBlue.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: (_isLocked ? Colors.grey : AppTheme.primaryBlue).withOpacity(_isLoading ? 0 : 0.3),
            blurRadius: 12,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (_isLoading || _isLocked) ? null : _saveSettings,
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: _isLoading
                  ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isLocked ? '✓ Location Locked' : 'Save Configuration',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
