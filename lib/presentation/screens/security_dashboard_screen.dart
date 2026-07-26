import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/security_ops_service.dart';

class SecurityDashboardScreen extends StatefulWidget {
  static const routeName = '/security-dashboard';

  const SecurityDashboardScreen({super.key});

  @override
  State<SecurityDashboardScreen> createState() => _SecurityDashboardScreenState();
}

class _SecurityDashboardScreenState extends State<SecurityDashboardScreen> {
  final SecurityOpsService _securityOps = SecurityOpsService();
  bool _loading = true;
  String? _error;
  String? _instituteId;
  Map<String, int> _summary = const {
    'open': 0,
    'high': 0,
    'critical': 0,
    'total': 0,
  };
  List<Map<String, dynamic>> _incidents = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Reuse profile context by reading the currently authenticated user's institute from incidents API path.
      // institute_id filter is required by service API, so we get it from app session profile through incidents table query side.
      // In case app session has no institute, dashboard remains unavailable.
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _error = 'Not authenticated';
        });
        return;
      }
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('institute_id')
          .eq('id', user.id)
          .maybeSingle();
      final instituteId = profile?['institute_id'] as String?;
      if (instituteId == null || instituteId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No institute mapped for this account';
        });
        return;
      }

      final summary = await _securityOps.getIncidentSummary(instituteId: instituteId);
      final incidents = await _securityOps.getRecentIncidents(instituteId: instituteId);
      if (!mounted) return;
      setState(() {
        _instituteId = instituteId;
        _summary = summary;
        _incidents = incidents;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      case 'medium':
        return Colors.amber.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Dashboard'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Failed to load: $_error'),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Institute: ${_instituteId ?? '-'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _summaryCard('Open', _summary['open'] ?? 0, Colors.orange),
                          const SizedBox(width: 8),
                          _summaryCard('High', _summary['high'] ?? 0, Colors.deepOrange),
                          const SizedBox(width: 8),
                          _summaryCard('Critical', _summary['critical'] ?? 0, Colors.red),
                          const SizedBox(width: 8),
                          _summaryCard('Total', _summary['total'] ?? 0, AppTheme.primaryBlue),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Recent Security Incidents',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      if (_incidents.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No incidents logged.'),
                          ),
                        ),
                      for (final incident in _incidents) _incidentTile(incident),
                    ],
                  ),
      ),
    );
  }

  Widget _summaryCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _incidentTile(Map<String, dynamic> i) {
    final category = (i['category'] ?? '-').toString();
    final title = (i['title'] ?? '-').toString();
    final severity = (i['severity'] ?? 'medium').toString();
    final status = (i['status'] ?? 'open').toString();
    final createdAt = (i['created_at'] ?? '').toString();
    final description = (i['description'] ?? '').toString();
    final sevColor = _severityColor(severity);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    severity.toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w700, color: sevColor, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Category: $category'),
            Text('Status: $status'),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description),
            ],
            const SizedBox(height: 6),
            Text(
              createdAt,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
