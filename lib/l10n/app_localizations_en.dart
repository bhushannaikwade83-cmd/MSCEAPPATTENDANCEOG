// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get portalPrimaryLine =>
      'MSCE Attendance App  |  एमएससीई उपस्थिती अॅप';

  @override
  String get portalSecondaryLineDefault =>
      'MSCE Smart Attendance Management System';

  @override
  String get officialBadge => 'OFFICIAL';

  @override
  String get footerOfficialUse => 'OFFICIAL USE ONLY';

  @override
  String get footerCredit =>
      'Powered by MSCE - Maharashtra State Council of Education';

  @override
  String get mainNavSubtitleAdmin => 'Admin dashboard  |  प्रशासक डॅशबोर्ड';

  @override
  String get mainNavSubtitleInstructor =>
      'Instructor user  |  प्रशिक्षक वापरकर्ता';

  @override
  String get mainNavSubtitleStudent => 'Student records  |  विद्यार्थी नोंदी';

  @override
  String get mainNavSubtitleGps => 'GPS geofence  |  स्थान सीमा सेटिंग्ज';

  @override
  String get mainNavSubtitleReports => 'Attendance reports  |  उपस्थिती अहवाल';

  @override
  String get splashTitle => 'MSCE Attendance App';

  @override
  String get splashSubtitle => 'MSCE Smart Attendance Management System';

  @override
  String get splashCredit =>
      'Powered by MSCE - Maharashtra State Council of Education';

  @override
  String get splashLoading => 'Loading…';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageMarathi => 'मराठी';

  @override
  String get languageToggleHint => 'Language  |  भाषा';

  @override
  String get loginAppTitle => 'MSCE Attendance App';

  @override
  String get loginSubtitle => 'MSCE Smart Attendance Management System';

  @override
  String loginCopyright(String year) {
    return '© $year MSCE Attendance App. All rights reserved.';
  }

  @override
  String get chipEncrypted => 'Encrypted';

  @override
  String get chipGovtPortal => 'Govt. Portal';

  @override
  String get chipSecure => 'Secure';
}
