/// Model Training Dashboard
/// Shows model improvement and learning progress

import 'package:flutter/material.dart';
import '../../services/model_training_service.dart';

class ModelTrainingDashboard extends StatefulWidget {
  const ModelTrainingDashboard({Key? key}) : super(key: key);

  @override
  State<ModelTrainingDashboard> createState() => _ModelTrainingDashboardState();
}

class _ModelTrainingDashboardState extends State<ModelTrainingDashboard> {
  late Future<Map<String, dynamic>> _progressFuture;

  @override
  void initState() {
    super.initState();
    _progressFuture = ModelTrainingService.getTrainingProgress();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Training'),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _progressFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final progress = snapshot.data!;
          final totalSamples = progress['total_samples'] as int;
          final registrations = progress['registrations'] as int;
          final attendances = progress['attendances'] as int;
          final accuracy = progress['current_accuracy'] as double;
          final threshold = progress['current_threshold'] as double;
          final readyForTraining = progress['ready_for_training'] as bool;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade600],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Model Learning Progress',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Learning from test data to improve accuracy',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Training Data Collection
              _buildMetricCard(
                title: 'Data Collected',
                value: '$totalSamples samples',
                subtitle: 'Learning from student data',
                icon: Icons.data_usage,
                color: Colors.blue,
                children: [
                  _buildMetricRow('Registrations', '$registrations', Icons.person_add),
                  _buildMetricRow('Attendance Attempts', '$attendances', Icons.check_circle),
                ],
              ),

              const SizedBox(height: 16),

              // Training Status
              _buildMetricCard(
                title: 'Training Status',
                value: readyForTraining ? 'ACTIVE' : 'PENDING',
                subtitle: readyForTraining
                    ? 'Model is learning and improving'
                    : 'Need ${'${10 - totalSamples} more samples'.replaceAll('-', '+')}',
                icon: Icons.school,
                color: readyForTraining ? Colors.green : Colors.orange,
              ),

              const SizedBox(height: 16),

              // Accuracy
              if (accuracy > 0)
                _buildMetricCard(
                  title: 'Model Accuracy',
                  value: '${accuracy.toStringAsFixed(1)}%',
                  subtitle: 'Based on $attendances test attempts',
                  icon: Icons.trending_up,
                  color: Colors.green,
                  progress: accuracy / 100,
                ),

              const SizedBox(height: 16),

              // Adaptive Threshold
              if (accuracy > 0)
                _buildMetricCard(
                  title: 'Adaptive Threshold',
                  value: threshold.toStringAsFixed(3),
                  subtitle: 'Optimized for maximum accuracy',
                  icon: Icons.tune,
                  color: Colors.purple,
                  children: [
                    Text(
                      'This threshold is automatically tuned based on testing results. It balances matching accuracy with false positive prevention.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 24),

              // How It Works
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How Model Learning Works',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildHowItWorksItem(
                      '1',
                      'Register Student',
                      'Embedding saved for training',
                    ),
                    _buildHowItWorksItem(
                      '2',
                      'Mark Attendance',
                      'System learns from match/no-match results',
                    ),
                    _buildHowItWorksItem(
                      '3',
                      'Accumulate Data',
                      'After 10+ attempts, model retrains',
                    ),
                    _buildHowItWorksItem(
                      '4',
                      'Improve Accuracy',
                      'Threshold auto-adjusts for best results',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Clear Data Button
              ElevatedButton.icon(
                onPressed: () => _showClearDialog(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Training Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),

              const SizedBox(height: 16),

              // Refresh Button
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _progressFuture = ModelTrainingService.getTrainingProgress();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    double? progress,
    List<Widget>? children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          if (children != null) ...[
            const SizedBox(height: 12),
            ...children,
          ],
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksItem(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Training Data?'),
        content: const Text(
          'This will reset all collected learning data and metrics. The model will restart learning from scratch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ModelTrainingService.clearTrainingData().then((_) {
                Navigator.pop(context);
                setState(() {
                  _progressFuture = ModelTrainingService.getTrainingProgress();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Training data cleared')),
                );
              });
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
