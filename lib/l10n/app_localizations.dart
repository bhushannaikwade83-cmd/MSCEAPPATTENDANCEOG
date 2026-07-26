import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_mr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('mr'),
  ];

  /// No description provided for @portalPrimaryLine.
  ///
  /// In en, this message translates to:
  /// **'MSCE Attendance App  |  एमएससीई उपस्थिती अॅप'**
  String get portalPrimaryLine;

  /// No description provided for @portalSecondaryLineDefault.
  ///
  /// In en, this message translates to:
  /// **'MSCE Smart Attendance Management System'**
  String get portalSecondaryLineDefault;

  /// No description provided for @officialBadge.
  ///
  /// In en, this message translates to:
  /// **'OFFICIAL'**
  String get officialBadge;

  /// No description provided for @footerOfficialUse.
  ///
  /// In en, this message translates to:
  /// **'OFFICIAL USE ONLY'**
  String get footerOfficialUse;

  /// No description provided for @footerCredit.
  ///
  /// In en, this message translates to:
  /// **'Powered by MSCE - Maharashtra State Council of Education'**
  String get footerCredit;

  /// No description provided for @mainNavSubtitleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin dashboard  |  प्रशासक डॅशबोर्ड'**
  String get mainNavSubtitleAdmin;

  /// No description provided for @mainNavSubtitleInstructor.
  ///
  /// In en, this message translates to:
  /// **'Instructor user  |  प्रशिक्षक वापरकर्ता'**
  String get mainNavSubtitleInstructor;

  /// No description provided for @mainNavSubtitleStudent.
  ///
  /// In en, this message translates to:
  /// **'Student records  |  विद्यार्थी नोंदी'**
  String get mainNavSubtitleStudent;

  /// No description provided for @mainNavSubtitleGps.
  ///
  /// In en, this message translates to:
  /// **'GPS geofence  |  स्थान सीमा सेटिंग्ज'**
  String get mainNavSubtitleGps;

  /// No description provided for @mainNavSubtitleReports.
  ///
  /// In en, this message translates to:
  /// **'Attendance reports  |  उपस्थिती अहवाल'**
  String get mainNavSubtitleReports;

  /// No description provided for @splashTitle.
  ///
  /// In en, this message translates to:
  /// **'MSCE Attendance App'**
  String get splashTitle;

  /// No description provided for @splashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'MSCE Smart Attendance Management System'**
  String get splashSubtitle;

  /// No description provided for @splashCredit.
  ///
  /// In en, this message translates to:
  /// **'Powered by MSCE - Maharashtra State Council of Education'**
  String get splashCredit;

  /// No description provided for @splashLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get splashLoading;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageMarathi.
  ///
  /// In en, this message translates to:
  /// **'मराठी'**
  String get languageMarathi;

  /// No description provided for @languageToggleHint.
  ///
  /// In en, this message translates to:
  /// **'Language  |  भाषा'**
  String get languageToggleHint;

  /// No description provided for @loginAppTitle.
  ///
  /// In en, this message translates to:
  /// **'MSCE Attendance App'**
  String get loginAppTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'MSCE Smart Attendance Management System'**
  String get loginSubtitle;

  /// No description provided for @loginCopyright.
  ///
  /// In en, this message translates to:
  /// **'© {year} MSCE Attendance App. All rights reserved.'**
  String loginCopyright(String year);

  /// No description provided for @chipEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted'**
  String get chipEncrypted;

  /// No description provided for @chipGovtPortal.
  ///
  /// In en, this message translates to:
  /// **'Govt. Portal'**
  String get chipGovtPortal;

  /// No description provided for @chipSecure.
  ///
  /// In en, this message translates to:
  /// **'Secure'**
  String get chipSecure;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'mr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'mr':
      return AppLocalizationsMr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
