import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/time_parse.dart';
import '../../core/theme/app_theme.dart';
import '../../services/storage_service.dart';
import '../widgets/secure_network_image.dart';

class _StudentPhotosSnapshot {
  final Map<String, dynamic>? student;
  final List<Map<String, dynamic>> rows;

  _StudentPhotosSnapshot({required this.student, required this.rows});
}

class StudentPhotosScreen extends StatefulWidget {
  final String studentName;
  final String studentId;
  final String rollNumber;
  final String instituteId;

  const StudentPhotosScreen({
    super.key,
    required this.studentName,
    required this.studentId,
    required this.rollNumber,
    required this.instituteId,
  });

  @override
  State<StudentPhotosScreen> createState() => _StudentPhotosScreenState();
}

class _StudentPhotosScreenState extends State<StudentPhotosScreen> {
  bool _isLoading = true;

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row, Map<String, dynamic> stud) {
    final add = row['additional'] is Map
        ? Map<String, dynamic>.from((row['additional'] as Map).cast<String, dynamic>())
        : <String, dynamic>{};
    final subject =
        add['subject'] as String? ?? stud['subject'] as String? ?? 'Unknown Subject';
    final date = row['attendance_date']?.toString() ?? '';
    final type = row['type'] as String? ?? 'entry';
    final photoUrl = (row['photo_url'] as String?) ?? '';
    final photoPath = row['photo_path'] as String?;
    final entryFromAdd = add['entryTime'];
    final exitFromAdd = add['exitTime'];
    return {
      ...row,
      'subject': subject,
      'date': date,
      'photoUrl': photoUrl,
      'photo_path': photoPath,
      'entryPhoto': type == 'entry' ? photoUrl : '',
      'exitPhoto': type == 'exit' ? photoUrl : '',
      'entryPhotoPath': type == 'entry' ? photoPath : null,
      'exitPhotoPath': type == 'exit' ? photoPath : null,
      'timestamp': entryFromAdd ?? exitFromAdd ?? row['created_at'],
      'entryTime': entryFromAdd ?? (type == 'entry' ? row['created_at'] : null),
      'exitTime': exitFromAdd ?? (type == 'exit' ? row['created_at'] : null),
    };
  }

  Future<_StudentPhotosSnapshot> _fetchSnapshot() async {
    try {
      final code = await instituteCodeForId(widget.instituteId);
      final stud = await appDb
          .from('students')
          .select()
          .eq('institute_id', widget.instituteId)
          .eq('id', widget.studentId)
          .maybeSingle();
      if (stud == null) {
        return _StudentPhotosSnapshot(student: null, rows: []);
      }
      final studMap = Map<String, dynamic>.from(stud);
      final sid = studMap['id'] as String;
      final rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', code)
          .eq('student_id', sid)
          .order('created_at', ascending: false);
      final mapped =
          rows.map((r) => _normalizeRow(Map<String, dynamic>.from(r as Map), studMap)).toList();
      return _StudentPhotosSnapshot(student: studMap, rows: mapped);
    } catch (e) {
      if (kDebugMode) debugPrint('StudentPhotos: $e');
      return _StudentPhotosSnapshot(student: null, rows: []);
    }
  }

  Stream<_StudentPhotosSnapshot> _snapshotStream() async* {
    yield await _fetchSnapshot();
    await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
      yield await _fetchSnapshot();
    }
  }

  String? _registrationPhotoUrl(Map<String, dynamic>? stud) {
    if (stud == null) return null;
    final f = stud['face_photo_url']?.toString().trim() ?? '';
    return f.isNotEmpty ? f : null;
  }

  bool _hasRegistrationPhoto(Map<String, dynamic>? stud) {
    final u = _registrationPhotoUrl(stud);
    return (u != null && u.isNotEmpty);
  }

  Widget _buildRegistrationCard(String? imageUrl, String? storagePath, bool isDark) {
    final hasUrl = imageUrl != null && imageUrl.isNotEmpty;
    final hasPath = storagePath != null && storagePath.isNotEmpty;
    if (!hasUrl && !hasPath) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registration photo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: SecureNetworkImage(
                key: ValueKey('${widget.studentName}_$imageUrl'),
                imageUrl: hasUrl ? imageUrl : null,
                storagePath: hasPath ? storagePath : null,
                fit: BoxFit.cover,
                placeholder: Container(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: Container(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Folder navigation: Subject → Date → Entry/Exit
  String? _currentSubject;
  String? _currentDate;
  String? _currentPhotoType; // 'entry' or 'exit'

  @override
  void initState() {
    super.initState();
    _clearImageCache();
    setState(() => _isLoading = false);
  }

  @override
  void didUpdateWidget(StudentPhotosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear cache if student changed to prevent photo mixing
    if (oldWidget.rollNumber != widget.rollNumber ||
        oldWidget.studentName != widget.studentName) {
      _clearImageCache();
    }
  }

  @override
  void dispose() {
    _clearImageCache();
    super.dispose();
  }

  /// Clear the cached images to prevent photo mixing between students
  Future<void> _clearImageCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      if (kDebugMode) {
        debugPrint('✓ Image cache cleared for student: ${widget.studentName}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error clearing cache: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Handle back button press
        if (_currentPhotoType != null) {
          setState(() {
            _currentPhotoType = null;
          });
        } else if (_currentDate != null) {
          setState(() {
            _currentDate = null;
          });
        } else if (_currentSubject != null) {
          setState(() {
            _currentSubject = null;
          });
        } else {
          // At root level - go back to previous screen (student management)
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _buildPhotosGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              // Navigate back in folder structure or to home
              if (_currentPhotoType != null) {
                setState(() {
                  _currentPhotoType = null;
                });
              } else if (_currentDate != null) {
                setState(() {
                  _currentDate = null;
                });
              } else if (_currentSubject != null) {
                setState(() {
                  _currentSubject = null;
                });
              } else {
                // At root level - go back to previous screen (student management)
                Navigator.pop(context);
              }
            },
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.photo_library, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Roll: ${widget.rollNumber}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  String _formatDate(String dateStr) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _getDayName(String dateStr) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateStr);
      return DateFormat('EEEE').format(date); // Full day name (Monday, Tuesday, etc.)
    } catch (e) {
      return '';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  Widget _buildPhotosGrid() {
    return StreamBuilder<_StudentPhotosSnapshot>(
      stream: _snapshotStream(),
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading photos: ${snapshot.error}',
              style: TextStyle(
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
            ),
          );
        }

        final snap = snapshot.data ?? _StudentPhotosSnapshot(student: null, rows: []);
        final regUrl = _registrationPhotoUrl(snap.student);
        final regPath = snap.student?['registration_photo_path']?.toString().trim();
        final hasReg = _hasRegistrationPhoto(snap.student);

        if (snap.student == null && snap.rows.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 80,
                  color: isDark ? Colors.white.withOpacity(0.5) : AppTheme.textGray,
                ),
                const SizedBox(height: 16),
                Text(
                  'No photos found',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.textDark,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Student or attendance data not found',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : AppTheme.textGray,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        // Keep rows that have a displayable photo (URL and/or B2 path).
        final filteredDocs = snap.rows.where((data) {
          final u = (data['photoUrl'] as String? ?? '').trim();
          final p = (data['photo_path'] as String? ?? '').trim();
          return u.isNotEmpty || p.isNotEmpty;
        }).toList();

        if (filteredDocs.isEmpty) {
          if (hasReg) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRegistrationCard(
                    regUrl,
                    regPath?.isNotEmpty == true ? regPath : null,
                    isDark,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No entry/exit attendance photos yet. They appear here after attendance is marked.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return Center(
            child: Text(
              'No photos found',
              style: TextStyle(
                color: isDark ? Colors.white70 : AppTheme.textGray,
                fontSize: 16,
              ),
            ),
          );
        }

        // Organize photos by Subject -> Date -> Entry/Exit
        final Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>> organizedData = {};

        for (final data in filteredDocs) {
          final subject = data['subject'] as String? ?? 'Unknown Subject';
          final date = data['date'] as String? ?? 'Unknown Date';
          final typ = data['type'] as String? ?? 'entry';

          organizedData.putIfAbsent(subject, () => {});
          organizedData[subject]!.putIfAbsent(date, () => {'entry': [], 'exit': []});

          if (typ == 'entry') {
            organizedData[subject]![date]!['entry']!.add(data);
          } else if (typ == 'exit') {
            organizedData[subject]![date]!['exit']!.add(data);
          }
        }

        final sortedSubjects = organizedData.keys.toList()..sort();

        if (_currentSubject == null) {
          final folder = _buildFolderList(
            folders: sortedSubjects.map((subject) {
              return {
                'name': subject,
                'type': 'subject',
                'count': organizedData[subject]!.keys.length,
                'data': organizedData[subject],
              };
            }).toList(),
            onTap: (folder) {
              setState(() {
                _currentSubject = folder['name'] as String;
                _currentDate = null;
              });
            },
          );
          if (hasReg) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRegistrationCard(
                  regUrl,
                  regPath?.isNotEmpty == true ? regPath : null,
                  isDark,
                ),
                Expanded(child: folder),
              ],
            );
          }
          return folder;
        }

        if (_currentDate == null) {
          final dates = organizedData[_currentSubject!]!;
          final sortedDates = dates.keys.toList()..sort((a, b) => b.compareTo(a));
          return Column(
            children: [
              _buildBreadcrumb(),
              Expanded(
                child: _buildFolderList(
                  folders: sortedDates.map((date) {
                    String dayName = '';
                    try {
                      final dateObj = DateFormat('yyyy-MM-dd').parse(date);
                      dayName = DateFormat('EEEE').format(dateObj);
                    } catch (e) {
                      dayName = '';
                    }
                    final entryCount = dates[date]!['entry']!.length;
                    final exitCount = dates[date]!['exit']!.length;
                    return {
                      'name': date,
                      'type': 'date',
                      'count': entryCount + exitCount,
                      'entryCount': entryCount,
                      'exitCount': exitCount,
                      'data': dates[date],
                      'dayName': dayName,
                    };
                  }).toList(),
                  onTap: (folder) {
                    setState(() {
                      _currentDate = folder['name'] as String;
                      _currentPhotoType = null;
                    });
                  },
                ),
              ),
            ],
          );
        }

        if (_currentPhotoType == null) {
          final photoTypes = organizedData[_currentSubject!]![_currentDate!]!;
          final entryCount = photoTypes['entry']!.length;
          final exitCount = photoTypes['exit']!.length;

          return Column(
            children: [
              _buildBreadcrumb(),
              Expanded(
                child: _buildFolderList(
                  folders: [
                    if (entryCount > 0)
                      {
                        'name': 'Entry Photos',
                        'type': 'entry',
                        'count': entryCount,
                        'data': photoTypes['entry'],
                        'icon': Icons.login,
                        'color': Colors.green,
                      },
                    if (exitCount > 0)
                      {
                        'name': 'Exit Photos',
                        'type': 'exit',
                        'count': exitCount,
                        'data': photoTypes['exit'],
                        'icon': Icons.logout,
                        'color': Colors.orange,
                      },
                  ],
                  onTap: (folder) {
                    setState(() {
                      _currentPhotoType = folder['type'] as String;
                    });
                  },
                ),
              ),
            ],
          );
        }

        final photos =
            organizedData[_currentSubject!]![_currentDate!]![_currentPhotoType!]!;
        return Column(
          children: [
            _buildBreadcrumb(),
            Expanded(
              child: _buildPhotosGridForDate(photos, photoType: _currentPhotoType!),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBreadcrumb() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          if (_currentSubject != null || _currentDate != null)
            IconButton(
              icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : AppTheme.textDark),
              onPressed: () {
                setState(() {
                  if (_currentPhotoType != null) {
                    _currentPhotoType = null;
                  } else if (_currentDate != null) {
                    _currentDate = null;
                  } else if (_currentSubject != null) {
                    _currentSubject = null;
                  }
                });
              },
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildBreadcrumbItem('Subjects', _currentSubject == null),
                  if (_currentSubject != null) ...[
                    Icon(Icons.chevron_right, color: isDark ? Colors.white70 : AppTheme.textGray, size: 16),
                    _buildBreadcrumbItem(_currentSubject!, _currentDate == null),
                  ],
                  if (_currentDate != null) ...[
                    Icon(Icons.chevron_right, color: isDark ? Colors.white70 : AppTheme.textGray, size: 16),
                    _buildBreadcrumbItem(_formatDate(_currentDate!), _currentPhotoType == null),
                  ],
                  if (_currentPhotoType != null) ...[
                    Icon(Icons.chevron_right, color: isDark ? Colors.white70 : AppTheme.textGray, size: 16),
                    _buildBreadcrumbItem(
                      _currentPhotoType == 'entry' ? 'Entry Photos' : 'Exit Photos',
                      true,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbItem(String label, bool isActive) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive 
            ? AppTheme.primaryBlue.withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive 
              ? (isDark ? Colors.white : AppTheme.primaryBlue)
              : (isDark ? Colors.white70 : AppTheme.textGray),
          fontSize: 14,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildFolderList({
    required List<Map<String, dynamic>> folders,
    required Function(Map<String, dynamic>) onTap,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        final name = folder['name'] as String;
        final type = folder['type'] as String;
        final count = folder['count'] as int;
        
        if (type == 'date') {
          final entryCount = folder['entryCount'] as int? ?? 0;
          final exitCount = folder['exitCount'] as int? ?? 0;
          // For date folders, show day name
          final dayName = folder['dayName'] as String? ?? '';
          
          return _buildDateFolderCard(
            date: name,
            dayName: dayName,
            entryCount: entryCount,
            exitCount: exitCount,
            onTap: () => onTap(folder),
          );
        } else if (type == 'entry' || type == 'exit') {
          final icon = folder['icon'] as IconData? ?? Icons.photo;
          final color = folder['color'] as Color? ?? AppTheme.primaryBlue;
          
          return _buildPhotoTypeFolderCard(
            name: name,
            icon: icon,
            count: count,
            color: color,
            onTap: () => onTap(folder),
          );
        }
        
        // Subject-level folder (root)
        IconData icon = Icons.book;
        String countLabel = '$count ${count == 1 ? 'Date' : 'Dates'}';
        
        return _buildFolderCard(
          name: name,
          icon: icon,
          countLabel: countLabel,
          onTap: () => onTap(folder),
        );
      },
    );
  }

  Widget _buildFolderCard({
    required String name,
    required IconData icon,
    required String countLabel,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primaryBlue, size: 32),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                name,
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                countLabel,
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoTypeFolderCard({
    required String name,
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                name,
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count ${count == 1 ? 'Photo' : 'Photos'}',
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFolderCard({
    required String date,
    required String dayName,
    required int entryCount,
    required int exitCount,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_today, color: AppTheme.primaryBlue, size: 32),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  Text(
                    _formatDate(date),
                    style: TextStyle(
                      color: isDark ? Colors.white : AppTheme.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dayName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        dayName,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : AppTheme.textGray,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, size: 12, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '$entryCount',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.logout, size: 12, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '$exitCount',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosGridForDate(List<Map<String, dynamic>> photos, {String? photoType}) {
    // Convert all photos to use automatic temporary URLs
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: StorageService.convertPhotosToTemporaryUrls(
        photos.map((data) {
          // Get the correct photo URL and path based on photo type
          String photoUrl;
          String? storagePath;
          
          if (photoType == 'entry') {
            photoUrl = data['entryPhoto'] as String? ?? data['photoUrl'] as String? ?? '';
            storagePath = data['entryPhotoPath'] as String? ?? data['photo_path'] as String?;
          } else if (photoType == 'exit') {
            photoUrl = data['exitPhoto'] as String? ?? '';
            storagePath = data['exitPhotoPath'] as String? ?? data['photo_path'] as String?;
          } else {
            photoUrl = data['photoUrl'] as String? ?? data['entryPhoto'] as String? ?? '';
            storagePath = data['photo_path'] as String? ?? data['entryPhotoPath'] as String?;
          }
          
          return {
            'data': data,
            'photoUrl': photoUrl,
            'storagePath': storagePath,
          };
        }).toList(),
      ),
      builder: (context, urlSnapshot) {
        if (!urlSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        
        final processedPhotos = urlSnapshot.data!;
        
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.8,
          ),
          itemCount: processedPhotos.length,
          itemBuilder: (context, index) {
            final item = processedPhotos[index];
            final data = item['data'] as Map<String, dynamic>;
            final photoUrl = item['photoUrl'] as String;
            final subject = data['subject'] as String? ?? 'Unknown';
            final dateStr = data['date'] as String? ?? '';
            final photoSizeBytes = data['photoSizeBytes'] as int?;

            DateTime? timestamp;
            String? storagePath;
            String photoTypeLabel;

            if (photoType == 'entry') {
              timestamp = parseAnyTimestamp(data['entryTime'] ?? data['timestamp']);
              storagePath = data['entryPhotoPath'] as String? ?? data['photo_path'] as String?;
              photoTypeLabel = 'Entry';
            } else if (photoType == 'exit') {
              timestamp = parseAnyTimestamp(data['exitTime'] ?? data['timestamp']);
              storagePath = data['exitPhotoPath'] as String? ?? data['photo_path'] as String?;
              photoTypeLabel = 'Exit';
            } else {
              timestamp = parseAnyTimestamp(data['timestamp'] ?? data['entryTime']);
              storagePath = data['photo_path'] as String? ?? data['entryPhotoPath'] as String?;
              photoTypeLabel = 'Photo';
            }

            return _buildPhotoCard(
              photoUrl: photoUrl,
              subject: subject,
              date: dateStr,
              timestamp: timestamp,
              photoSizeBytes: photoSizeBytes,
              storagePath: storagePath,
              photoType: photoTypeLabel,
            );
          },
        );
      },
    );
  }

  Widget _buildPhotoCard({
    required String photoUrl,
    required String subject,
    required String date,
    DateTime? timestamp,
    int? photoSizeBytes,
    String? storagePath,
    String photoType = 'Photo',
  }) {
    return GestureDetector(
      onTap: () => _showPhotoDetail(photoUrl, subject, date, timestamp, photoSizeBytes, storagePath, photoType),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo - Use SecureNetworkImage for automatic temporary URL generation
              // SecureNetworkImage automatically handles URL generation from photoUrl or storagePath
              SecureNetworkImage(
                imageUrl: photoUrl.isNotEmpty ? photoUrl : null,
                storagePath: storagePath,
                fit: BoxFit.cover,
                placeholder: Container(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
                errorWidget: Container(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Failed to load',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Gradient overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                      children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subject,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: photoType == 'Entry' 
                                  ? Colors.green.withValues(alpha: 0.8)
                                  : Colors.orange.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              photoType,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatDate(date),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_getDayName(date).isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getDayName(date),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (timestamp != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('HH:mm').format(timestamp.toLocal()),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (photoSizeBytes != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.storage,
                              size: 10,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatFileSize(photoSizeBytes),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhotoDetail(
    String photoUrl,
    String subject,
    String date,
    DateTime? timestamp,
    int? photoSizeBytes,
    String? storagePath,
    String photoType,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final tsLocal = timestamp?.toLocal();
        return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // Full screen photo - automatically uses temporary URL
            Center(
              child: (photoUrl.isNotEmpty || (storagePath != null && storagePath.isNotEmpty))
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: SecureNetworkImage(
                        imageUrl: photoUrl.isNotEmpty ? photoUrl : null,
                        storagePath: storagePath,
                        fit: BoxFit.contain,
                        placeholder: const Center(
                          child: CircularProgressIndicator(),
                        ),
                        errorWidget: const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 80,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
            ),
            // Info card at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(Icons.subject, 'Subject', subject),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.calendar_today, 
                      'Date', 
                      '${_formatDate(date)}${_getDayName(date).isNotEmpty ? ' (${_getDayName(date)})' : ''}'
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.label,
                      'Type',
                      photoType,
                    ),
                    if (tsLocal != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        Icons.access_time,
                        'Timestamp',
                        '${DateFormat('MMM dd, yyyy').format(tsLocal)} at ${DateFormat('HH:mm').format(tsLocal)}',
                      ),
                    ],
                    if (photoSizeBytes != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        Icons.storage,
                        'File Size',
                        _formatFileSize(photoSizeBytes),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
