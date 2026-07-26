import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists UI language: English (`en`) or Marathi (`mr`). Rebuild via [notifyListeners].
class LocaleService extends ChangeNotifier {
  LocaleService() {
    _load();
  }

  static const String _prefKey = 'app_locale_language_code';

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefKey);
      if (code == 'mr' || code == 'en') {
        _locale = Locale(code!);
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  /// Toggle between English and Marathi.
  Future<void> toggleEnMr() async {
    final next = _locale.languageCode == 'mr' ? const Locale('en') : const Locale('mr');
    await setLocale(next);
  }

  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode;
    if (code != 'en' && code != 'mr') return;
    _locale = Locale(code);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, code);
    } catch (_) {}
  }
}
