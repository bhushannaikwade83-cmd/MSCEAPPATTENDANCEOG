import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Dialog for manually confirming attendance when face similarity is low.
/// Shows registered photo and current capture for staff comparison.
class ManualFaceConfirmationDialog extends StatelessWidget {
  final String studentName;
  final String studentSrNo;
  final String registeredPhotoUrl;
  final String currentPhotoPath;
  final double similarityPercent;
  final double? closestOtherSimilarityPercent;
  final String? closestOtherLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool noEnrollmentStaffMode;
  final String referencePhotoHeading;
  final String currentPhotoHeading;
  final String? comparisonContextNote;

  const ManualFaceConfirmationDialog({
    super.key,
    required this.studentName,
    required this.studentSrNo,
    required this.registeredPhotoUrl,
    required this.currentPhotoPath,
    required this.similarityPercent,
    this.closestOtherSimilarityPercent,
    this.closestOtherLabel,
    required this.onConfirm,
    required this.onCancel,
    this.referencePhotoHeading = '📸 Registered Photo:',
    this.currentPhotoHeading = '📷 Current Entry Photo:',
    this.comparisonContextNote,
    this.noEnrollmentStaffMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.88;
    final photoH = (MediaQuery.sizeOf(context).height * 0.18).clamp(120.0, 180.0);
    final hasRegisteredUrl = registeredPhotoUrl.trim().isNotEmpty;

    return Dialog(
      backgroundColor: AppTheme.backgroundGrey,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW.clamp(280.0, 400.0),
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '⚠️ MANUAL CONFIRMATION REQUIRED',
                      style: TextStyle(
                        color: AppTheme.accentSaffron,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Student: $studentName (SR NO: $studentSrNo)',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textGray),
                    ),
                    if (noEnrollmentStaffMode)
                      const Text(
                        '⚠️ No neural enrollment — staff-only visual check',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.accentRed,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        'Similarity: ${similarityPercent.toStringAsFixed(1)}% (review band)',
                        style: const TextStyle(fontSize: 13, color: AppTheme.accentSaffron),
                      ),
                    if (closestOtherSimilarityPercent != null)
                      Text(
                        'Closest Other: ${(closestOtherLabel?.isNotEmpty == true ? closestOtherLabel! : 'Another student')} '
                        '(${closestOtherSimilarityPercent!.toStringAsFixed(1)}%)',
                        style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            noEnrollmentStaffMode
                                ? 'Selected profile: manual identity check'
                                : 'Selected Student: ${similarityPercent.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                          ),
                          if (closestOtherSimilarityPercent != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Closest Other: ${(closestOtherLabel?.isNotEmpty == true ? closestOtherLabel! : 'Another student')} '
                              '${closestOtherSimilarityPercent!.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            noEnrollmentStaffMode
                                ? (closestOtherSimilarityPercent != null
                                    ? 'Decision: Another enrolled student in this institute is closer; confirm you have the right profile.'
                                    : 'Decision: No strong match to other enrolled students; staff still confirm visual identity.')
                                : closestOtherSimilarityPercent != null
                                    ? 'Decision: Manual review because the selected student and another student are close in score.'
                                    : 'Decision: Manual review because the selected student is in the review band, not a strong auto-pass.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textGray,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accentSaffron, width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info, color: AppTheme.accentSaffron, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              comparisonContextNote ??
                                  'Appearance may have changed (haircut, beard, glasses). '
                                  'Compare both photos below.',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      referencePhotoHeading,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _photoBox(
                      height: photoH,
                      child: hasRegisteredUrl
                          ? Image.network(
                              registeredPhotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _photoPlaceholder(photoH),
                            )
                          : _photoPlaceholder(photoH, label: 'No registered photo'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      currentPhotoHeading,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _photoBox(
                      height: photoH,
                      child: Image.file(
                        File(currentPhotoPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _photoPlaceholder(photoH),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.compare, color: AppTheme.primaryBlue, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              noEnrollmentStaffMode
                                  ? (closestOtherSimilarityPercent != null
                                      ? 'Compare carefully against other enrolled identities in your institute.'
                                      : 'Confirm the live capture matches this roster identity before proceeding.')
                                  : closestOtherSimilarityPercent != null
                                      ? 'Compare carefully. The selected student and another student are both close matches.'
                                      : 'Same person? Tap the green Confirm & Mark button below.',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onCancel,
                    child: const Text(
                      '❌ Cancel',
                      style: TextStyle(
                        color: AppTheme.accentRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('✅ Confirm & Mark'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _photoBox({required double height, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: child,
      ),
    );
  }

  static Widget _photoPlaceholder(double height, {String? label}) {
    return Container(
      height: height,
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, size: 48),
          if (label != null) ...[
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textGray)),
          ],
        ],
      ),
    );
  }
}
