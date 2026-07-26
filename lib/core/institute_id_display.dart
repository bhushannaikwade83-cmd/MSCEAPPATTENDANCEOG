/// Formats institute identifiers for display. Purely numeric codes are shown
/// zero-padded to 5 digits (e.g. `42` → `00042`; `3333` → `03333`). Non-numeric IDs are unchanged.
String formatInstituteIdForDisplay(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return s;
  if (RegExp(r'^\d+$').hasMatch(s)) {
    return s.padLeft(5, '0');
  }
  return s;
}
