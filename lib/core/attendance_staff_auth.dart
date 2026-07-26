/// Synthetic Supabase credentials for institute instructors (`attendance_user`).
/// Login in the app is Institute ID + PIN only; Auth email is unique per instructor
/// (resolved server-side via `resolve_attendance_staff_email`).
/// Password format must stay in sync with Edge Function `create-institute-attendance-user`.
class AttendanceStaffAuth {
  static const String _passwordSuffix = 'msceStaffV2';

  /// Supabase Auth password (not shown to user). User only enters Institute ID + PIN.
  static String authPasswordFor({
    required String canonicalInstituteId,
    required String pin,
  }) {
    return '${pin.trim()}|${canonicalInstituteId.trim()}|$_passwordSuffix';
  }
}
