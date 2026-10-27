import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();

  static const _isLoggedInKey = 'isLoggedIn';
  static const _emailKey = 'email';
  static const _roleKey = 'role';
  static const _roles = {'student', 'teacher', 'parent', 'admin'};

  Future<void> saveSession(String email, String role) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !_roles.contains(normalizedRole)) {
      throw ArgumentError('A valid email and role are required for a session.');
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_emailKey, normalizedEmail);
    await preferences.setString(_roleKey, normalizedRole);
    await preferences.setBool(_isLoggedInKey, true);
  }

  Future<({String email, String role})?> getSession() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_isLoggedInKey) == false) return null;
    final email = preferences.getString(_emailKey)?.trim().toLowerCase();
    final role = preferences.getString(_roleKey)?.trim().toLowerCase();
    if (email == null ||
        email.isEmpty ||
        role == null ||
        !_roles.contains(role)) {
      if (email != null || role != null) await clearSession();
      return null;
    }
    return (email: email, role: role);
  }

  Future<void> clearSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_isLoggedInKey);
    await preferences.remove(_emailKey);
    await preferences.remove(_roleKey);
  }
}
