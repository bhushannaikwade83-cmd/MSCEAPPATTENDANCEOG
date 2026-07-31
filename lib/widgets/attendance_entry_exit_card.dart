import 'package:flutter/material.dart';
import '../services/attendance_service.dart';
import 'package:intl/intl.dart';

class AttendanceEntryExitCard extends StatefulWidget {
  final String srNo;
  final String instituteId;

  const AttendanceEntryExitCard({
    required this.srNo,
    required this.instituteId,
    Key? key,
  }) : super(key: key);

  @override
  State<AttendanceEntryExitCard> createState() =>
      _AttendanceEntryExitCardState();
}

class _AttendanceEntryExitCardState extends State<AttendanceEntryExitCard> {
  late Future<Map<String, dynamic>> _attendanceFuture;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  void _loadAttendance() {
    _attendanceFuture = AttendanceService.getStudentAttendance(
      widget.srNo,
      widget.instituteId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _attendanceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final attendance = snapshot.data ?? {};
        final entry = attendance['entry'] as Map<String, dynamic>?;
        final exit = attendance['exit'] as Map<String, dynamic>?;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today\'s Attendance',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                // ENTRY
                Row(
                  children: [
                    const Icon(Icons.login, size: 20, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Entry',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if (entry != null)
                            Text(
                              '${entry['time'] ?? 'N/A'} (${(entry['similarity'] * 100).toStringAsFixed(1)}%)',
                              style: const TextStyle(fontSize: 12),
                            )
                          else
                            const Text(
                              'Not marked',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                        ],
                      ),
                    ),
                    if (entry != null && entry['photo_url'] != null)
                      GestureDetector(
                        onTap: () => _showPhotoPreview(
                          context,
                          entry['photo_url'],
                          'Entry Photo',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(
                            Icons.image,
                            size: 20,
                            color: Colors.blue[300],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // EXIT
                Row(
                  children: [
                    const Icon(Icons.logout, size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Exit',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if (exit != null)
                            Text(
                              '${exit['time'] ?? 'N/A'} (${(exit['similarity'] * 100).toStringAsFixed(1)}%)',
                              style: const TextStyle(fontSize: 12),
                            )
                          else
                            const Text(
                              'Not marked',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                        ],
                      ),
                    ),
                    if (exit != null && exit['photo_url'] != null)
                      GestureDetector(
                        onTap: () => _showPhotoPreview(
                          context,
                          exit['photo_url'],
                          'Exit Photo',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(
                            Icons.image,
                            size: 20,
                            color: Colors.blue[300],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPhotoPreview(BuildContext context, String photoUrl, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 300,
          height: 300,
          child: Image.network(
            photoUrl,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Text('Photo not available')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
