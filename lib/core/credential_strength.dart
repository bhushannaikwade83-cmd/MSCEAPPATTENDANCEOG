import '../services/validation_service.dart';

/// Visual hint tier for passwords / PINs (does not replace server-side checks).
enum CredentialStrengthLevel {
  empty,
  weak,
  medium,
  strong,
}

class CredentialStrengthAnalysis {
  const CredentialStrengthAnalysis({
    required this.level,
    this.hint,
  });

  final CredentialStrengthLevel level;
  final String? hint;

  /// Password: reuse [ValidationService.validatePassword] so labels match submit errors.
  static CredentialStrengthAnalysis analyzePassword(String password) {
    if (password.isEmpty) {
      return const CredentialStrengthAnalysis(level: CredentialStrengthLevel.empty);
    }

    final registrationError =
        ValidationService.validatePassword(password, isRegistration: true);
    if (registrationError == null) {
      return const CredentialStrengthAnalysis(level: CredentialStrengthLevel.strong);
    }

    final basicError =
        ValidationService.validatePassword(password, isRegistration: false);
    if (password.length < 8 || basicError != null) {
      return CredentialStrengthAnalysis(
        level: CredentialStrengthLevel.weak,
        hint: basicError ?? registrationError,
      );
    }

    return CredentialStrengthAnalysis(
      level: CredentialStrengthLevel.medium,
      hint: registrationError,
    );
  }

  /// Four-digit PIN: shown only when [pin.length] == 4.
  static CredentialStrengthAnalysis analyzePinFour(String pin) {
    if (pin.isEmpty) {
      return const CredentialStrengthAnalysis(level: CredentialStrengthLevel.empty);
    }
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      return const CredentialStrengthAnalysis(level: CredentialStrengthLevel.empty);
    }

    const weakPins = <String>{
      '0000',
      '1111',
      '2222',
      '3333',
      '4444',
      '5555',
      '6666',
      '7777',
      '8888',
      '9999',
      '1234',
      '4321',
      '1212',
      '6969',
      '0123',
      '9876',
    };

    if (weakPins.contains(pin)) {
      return const CredentialStrengthAnalysis(
        level: CredentialStrengthLevel.weak,
        hint: 'This PIN is too easy to guess',
      );
    }

    if (_allSameDigits(pin)) {
      return const CredentialStrengthAnalysis(
        level: CredentialStrengthLevel.weak,
        hint: 'Avoid repeating the same digit',
      );
    }

    if (_isSequential(pin)) {
      return const CredentialStrengthAnalysis(
        level: CredentialStrengthLevel.weak,
        hint: 'Avoid simple counting sequences',
      );
    }

    final distinct = pin.split('').toSet().length;
    if (distinct <= 2) {
      return const CredentialStrengthAnalysis(
        level: CredentialStrengthLevel.medium,
        hint: 'Mix digits more for a stronger PIN',
      );
    }

    return const CredentialStrengthAnalysis(level: CredentialStrengthLevel.strong);
  }

  static bool _allSameDigits(String pin) {
    if (pin.length < 2) return false;
    final first = pin[0];
    for (var i = 1; i < pin.length; i++) {
      if (pin[i] != first) return false;
    }
    return true;
  }

  /// Ascending or descending by 1 (wrapping), e.g. 3456, 6543.
  static bool _isSequential(String pin) {
    if (pin.length < 4) return false;
    var asc = true;
    var desc = true;
    for (var i = 0; i < pin.length - 1; i++) {
      final a = int.tryParse(pin[i]) ?? -1;
      final b = int.tryParse(pin[i + 1]) ?? -1;
      if (a < 0 || b < 0) return false;
      final up = (a + 1) % 10 == b;
      final down = (a - 1 + 10) % 10 == b;
      if (!up) asc = false;
      if (!down) desc = false;
      if (!asc && !desc) return false;
    }
    return asc || desc;
  }

  static String label(CredentialStrengthLevel level) {
    switch (level) {
      case CredentialStrengthLevel.empty:
        return '';
      case CredentialStrengthLevel.weak:
        return 'Weak';
      case CredentialStrengthLevel.medium:
        return 'Medium';
      case CredentialStrengthLevel.strong:
        return 'Strong';
    }
  }
}
