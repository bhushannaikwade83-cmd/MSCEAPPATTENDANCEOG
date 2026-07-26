import 'package:intl/intl.dart';

enum DateRangeType {
  oneWeek,
  oneMonth,
  threeMonths,
  sixMonths,
  custom,
}

class DateRangeFilter {
  final DateTime startDate;
  final DateTime endDate;
  final DateRangeType type;

  DateRangeFilter({
    required this.startDate,
    required this.endDate,
    required this.type,
  });

  /// Create a date range filter for 1 week from today
  static DateRangeFilter oneWeek() {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: 7));
    return DateRangeFilter(
      startDate: _startOfDay(startDate),
      endDate: _endOfDay(now),
      type: DateRangeType.oneWeek,
    );
  }

  /// Create a date range filter for 1 month from today
  static DateRangeFilter oneMonth() {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month - 1, now.day);
    return DateRangeFilter(
      startDate: _startOfDay(startDate),
      endDate: _endOfDay(now),
      type: DateRangeType.oneMonth,
    );
  }

  /// Create a date range filter for 3 months from today
  static DateRangeFilter threeMonths() {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month - 3, now.day);
    return DateRangeFilter(
      startDate: _startOfDay(startDate),
      endDate: _endOfDay(now),
      type: DateRangeType.threeMonths,
    );
  }

  /// Create a date range filter for 6 months from today
  static DateRangeFilter sixMonths() {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month - 6, now.day);
    return DateRangeFilter(
      startDate: _startOfDay(startDate),
      endDate: _endOfDay(now),
      type: DateRangeType.sixMonths,
    );
  }

  /// Create a custom date range filter
  static DateRangeFilter custom(DateTime start, DateTime end) {
    return DateRangeFilter(
      startDate: _startOfDay(start),
      endDate: _endOfDay(end),
      type: DateRangeType.custom,
    );
  }

  /// Get label for the date range
  String getLabel() {
    switch (type) {
      case DateRangeType.oneWeek:
        return '1 Week';
      case DateRangeType.oneMonth:
        return '1 Month';
      case DateRangeType.threeMonths:
        return '3 Months';
      case DateRangeType.sixMonths:
        return '6 Months';
      case DateRangeType.custom:
        return '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d').format(endDate)}';
    }
  }

  /// Check if a date is within the range
  bool isDateInRange(DateTime date) {
    final dateStart = _startOfDay(date);
    return dateStart.isAfter(startDate.subtract(Duration(seconds: 1))) &&
        dateStart.isBefore(endDate.add(Duration(seconds: 1)));
  }

  /// Helper to get start of day (00:00:00)
  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 0, 0, 0);
  }

  /// Helper to get end of day (23:59:59)
  static DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  /// Get number of days in the range
  int getDayCount() {
    return endDate.difference(startDate).inDays + 1;
  }

  /// Format range as string
  String formatRange() {
    return '${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';
  }

  @override
  String toString() => 'DateRangeFilter(${getLabel()}, $startDate - $endDate)';
}
