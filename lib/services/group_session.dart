import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in user's remembered group, and which mode the app runs in.
///
/// Student Affairs (and users with no group) get the classic attendance
/// experience: roster verification, photos, SONIS-bound events. Any other
/// group — e.g. Admissions — gets prospect mode: their own scan lists, any
/// badge accepted without roster lookup, notes, and email-to-group.
class GroupSession {
  static String? groupId;
  static String? groupName;
  static String? upn;

  static bool get groupMode =>
      groupId != null &&
      (groupName ?? '').toLowerCase() != 'student affairs';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    groupId = prefs.getString('selected_group_id');
    groupName = prefs.getString('selected_group_name');
    upn = prefs.getString('signed_in_upn');
  }

  static Future<void> clearGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_group_id');
    await prefs.remove('selected_group_name');
    groupId = null;
    groupName = null;
  }
}
