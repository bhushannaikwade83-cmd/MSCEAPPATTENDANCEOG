import 'dart:async';

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
    if (_isCheckingRole) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
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
        backgroundColor: AppTheme.backgroundGrey,
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            "Set your personal attendance zone. Each admin has their own geo-fencing settings. You can only mark attendance within your configured radius.\n\n"
                            "Unlock or save location on the website? This screen updates automatically every few seconds, and when you return to the app.",
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppTheme.textGray,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

              // Radius Lock Banner (Always shown - radius is always locked)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.blue, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: Colors.blue, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Radius fixed at 15 m",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Attendance may only be marked within about ${kAttendanceMaxEffectiveFenceMeters.toStringAsFixed(0)} m of your locked point (nominal ${kAttendanceFenceRadiusMeters.toStringAsFixed(0)} m + small GPS tolerance). This cannot be changed.",
                            style: TextStyle(
                              color: Colors.blue.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Location Lock Banner (Only shown if location is set and locked)
              Visibility(
                visible: _isLocked,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.orange, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock, color: Colors.orange, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Location Locked",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Location coordinates are locked after being set. Contact super admin to unlock for changes.",
                                  style: TextStyle(
                                    color: Colors.orange.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              Text(
                "School Coordinates",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Latitude",
                        prefixIcon: Icon(Icons.map_outlined),
                        helperText: "Auto-filled — use current location",
                        helperMaxLines: 2,
                      ),
                      enabled: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Longitude",
                        prefixIcon: Icon(Icons.map_outlined),
                        helperText: "Auto-filled — use current location",
                        helperMaxLines: 2,
                      ),
                      enabled: false,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isLoading || _isLocked) ? null : _getCurrentLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text("Use Current Location"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    foregroundColor: AppTheme.primaryBlue,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                "Allowed Radius",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _radiusController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Radius in Meters",
                  prefixIcon: const Icon(Icons.radar_outlined),
                  helperText:
                      "Radius is fixed at 15 m for all admins. It cannot be changed, even by super admin.",
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  if (v!.isEmpty) return "Required";
                  final radius = double.tryParse(v);
                  if (radius == null) return "Invalid number";
                  if (radius != kAttendanceFenceRadiusMeters) {
                    return "Radius must be exactly ${kAttendanceFenceRadiusMeters.toStringAsFixed(0)} m.";
                  }
                  return null;
                },
                enabled: false,
                readOnly: true,
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isLocked) ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLocked ? Colors.grey : AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isLocked ? "Location Locked" : "Save Configuration",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}
