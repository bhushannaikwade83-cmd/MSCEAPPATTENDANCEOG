import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/app_db.dart';
import '../../core/time_parse.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/error_logger.dart';
import '../../services/geofence_service.dart';
import '../../config/admin_portal_url.dart';

class CoderDashboardScreen extends StatefulWidget {
  static const routeName = '/coder-dashboard';
  const CoderDashboardScreen({super.key});

  @override
  State<CoderDashboardScreen> createState() => _CoderDashboardScreenState();
}

class _CoderDashboardScreenState extends State<CoderDashboardScreen> {
  String _selectedFilter = 'all'; // all, unresolved, resolved
  String _searchQuery = '';
  String? _selectedContext;
  final TextEditingController _searchController = TextEditingController();
  final GeofenceService _geofenceService = GeofenceService();

  Stream<List<Map<String, dynamic>>> _errorLogsStream() async* {
    Future<List<Map<String, dynamic>>> load() async {
      return await appDb
          .from('error_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
    }

    yield await load();
    yield* Stream.periodic(const Duration(seconds: 4), (_) => null).asyncMap((_) async => load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Super Admin Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business),
            onPressed: () async {
              final ok = await AdminPortalUrl.launch();
              if (ok) return;
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AdminPortalUrl.isConfigured
                        ? 'Could not open the admin portal.'
                        : 'Set ADMIN_PORTAL_URL in app_config.env to the deployed React admin portal (e.g. https://admin.example.com).',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            },
            tooltip: 'Open web admin portal (institutes & approvals)',
          ),
          IconButton(
            icon: const Icon(Icons.location_on),
            onPressed: () => _showGeofenceManager(),
            tooltip: 'Manage Geofences',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await appDb.auth.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/coder-login');
              }
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters and Search
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search errors',
                    hintText: 'Search by error message, code, or context...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
                const SizedBox(height: 12),

                // Filter Chips
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          _buildFilterChip('all', 'All Errors'),
                          _buildFilterChip('unresolved', 'Unresolved'),
                          _buildFilterChip('resolved', 'Resolved'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Error List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _errorLogsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final errors = snapshot.data!.where((data) {
                  final resolved = data['resolved'] as bool? ?? false;
                  final errorContext = data['context'] as String? ?? '';
                  final errorMessage =
                      (data['error_message'] ?? data['errorMessage']) as String? ?? '';
                  final errorCode =
                      (data['error_code'] ?? data['errorCode']) as String? ?? '';

                  if (_selectedFilter == 'unresolved' && resolved) return false;
                  if (_selectedFilter == 'resolved' && !resolved) return false;

                  if (_searchQuery.isNotEmpty) {
                    final query = _searchQuery.toLowerCase();
                    if (!errorMessage.toLowerCase().contains(query) &&
                        !errorCode.toLowerCase().contains(query) &&
                        !errorContext.toLowerCase().contains(query)) {
                      return false;
                    }
                  }

                  return true;
                }).toList();

                if (errors.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: AppTheme.textGray),
                        const SizedBox(height: 16),
                        Text(
                          'No errors found',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppTheme.textGray,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: errors.length,
                  itemBuilder: (context, index) {
                    final data = errors[index];
                    final id = data['id']?.toString() ?? '$index';
                    return _buildErrorCard(id, data);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedFilter = value);
      },
      selectedColor: AppTheme.primaryGreen.withValues(alpha: 0.2),
      checkmarkColor: AppTheme.primaryGreen,
    );
  }

  Widget _buildErrorCard(String errorId, Map<String, dynamic> data) {
    final resolved = data['resolved'] as bool? ?? false;
    final errorType = (data['error_type'] ?? data['errorType']) as String? ?? 'Unknown';
    final errorCode = (data['error_code'] ?? data['errorCode']) as String? ?? '';
    final errorMessage =
        (data['error_message'] ?? data['errorMessage']) as String? ?? 'Unknown error';
    final errorContext = data['context'] as String? ?? 'unknown';
    final timestamp = parseAnyTimestamp(data['created_at'] ?? data['timestamp']);
    final userEmail = (data['user_email'] ?? data['userEmail']) as String?;
    final instituteId = (data['institute_id'] ?? data['instituteId']) as String?;
    final appType = (data['app_type'] ?? data['appType']) as String? ?? 'admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: resolved ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: resolved
              ? Colors.grey.shade300
              : (errorCode == 'permission-denied'
                  ? Colors.orange.shade300
                  : Colors.red.shade300),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: resolved
                ? Colors.grey.shade200
                : (errorCode == 'permission-denied'
                    ? Colors.orange.shade100
                    : Colors.red.shade100),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            resolved ? Icons.check_circle : Icons.error_outline,
            color: resolved
                ? Colors.grey
                : (errorCode == 'permission-denied'
                    ? Colors.orange
                    : Colors.red),
            size: 24,
          ),
        ),
        title: Text(
          errorCode.isNotEmpty ? errorCode : errorType,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: resolved ? Colors.grey : AppTheme.textDark,
            decoration: resolved ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              errorMessage.length > 100
                  ? '${errorMessage.substring(0, 100)}...'
                  : errorMessage,
              style: TextStyle(
                color: resolved ? Colors.grey : AppTheme.textGray,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildChip(errorContext, AppTheme.primaryGreen),
                const SizedBox(width: 4),
                _buildChip(appType, AppTheme.accentOrange),
                if (timestamp != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM dd, HH:mm').format(timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textGray,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: resolved
            ? const Icon(Icons.check, color: Colors.grey)
            : PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'resolve',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 20),
                        SizedBox(width: 8),
                        Text('Mark as Resolved'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'resolve') {
                    ErrorLogger.markErrorResolved(
                      errorId,
                      appDb.auth.currentUser?.email ?? 'Unknown',
                    );
                  } else if (value == 'delete') {
                    ErrorLogger.deleteError(errorId);
                  }
                },
              ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Error Details
                _buildDetailRow('Error Type', errorType),
                if (errorCode.isNotEmpty) _buildDetailRow('Error Code', errorCode),
                _buildDetailRow('Context', errorContext),
                _buildDetailRow('App Type', appType),
                if (userEmail != null) _buildDetailRow('User Email', userEmail),
                if (instituteId != null) _buildDetailRow('Institute ID', instituteId),
                if (timestamp != null)
                  _buildDetailRow(
                    'Timestamp',
                    DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
                  ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // Error Message
                Text(
                  'Error Message:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),

                // Stack Trace
                if (data['stackTrace'] != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Stack Trace:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        data['stackTrace'] as String,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],

                // Additional Data
                if (data['additionalData'] != null &&
                    (data['additionalData'] as Map).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Additional Data:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      data['additionalData'].toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textGray,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  void _showGeofenceManager() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Geofence Lock Manager',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _geofenceService.getLockedGeofences(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final lockedLocations = snapshot.data!;

                    if (lockedLocations.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No locked geofences found'),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: lockedLocations.length,
                      itemBuilder: (context, index) {
                        final data = lockedLocations[index];
                        final instituteId = data['instituteId'] ?? 'Unknown';
                        final adminId = data['adminId'] ?? 'Unknown';
                        final lat = data['latitude'] ?? 0.0;
                        final lng = data['longitude'] ?? 0.0;
                        final radius = data['radius'] ?? 0.0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.lock, color: Colors.orange),
                            title: Text('Institute: $instituteId'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Admin: ${adminId.length > 8 ? '${adminId.substring(0, 8)}...' : adminId}',
                                ),
                                Text('Location: $lat, $lng'),
                                Text('Radius: ${radius}m'),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _unlockGeofence(
                                instituteId: instituteId,
                                adminId: adminId,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreen,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Unlock'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlockGeofence({
    required String instituteId,
    required String adminId,
  }) async {
    final result = await _geofenceService.unlockGeofence(
      instituteId: instituteId,
      adminId: adminId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: result['success']
              ? AppTheme.primaryGreen
              : AppTheme.accentRed,
        ),
      );
    }
  }
}
