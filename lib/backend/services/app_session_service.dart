import 'package:shared_preferences/shared_preferences.dart';

class AppSession {
  const AppSession({required this.email, required this.role});

  final String email;
  final String role;
}

class AppSessionService {
  AppSessionService._();

  static final AppSessionService instance = AppSessionService._();

  static const _isLoggedInKey = 'isLoggedIn';
  static const _emailKey = 'email';
  static const _roleKey = 'role';
  static const _roles = {'student', 'teacher', 'parent', 'admin'};

  Future<void> saveSession({
    required String email,
    required String role,
  }) async {
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

  Future<AppSession?> readSession() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_isLoggedInKey) != true) return null;

    final email = preferences.getString(_emailKey)?.trim().toLowerCase();
    final role = preferences.getString(_roleKey)?.trim().toLowerCase();
    if (email == null ||
        email.isEmpty ||
        role == null ||
        !_roles.contains(role)) {
      await clear();
      return null;
    }

    return AppSession(email: email, role: role);
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_isLoggedInKey);
    await preferences.remove(_emailKey);
    await preferences.remove(_roleKey);
  }
}
