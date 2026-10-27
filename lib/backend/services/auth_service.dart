import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'package:i_am_astudent/backend/constants/api_constants.dart';
import 'package:i_am_astudent/database/db_helper.dart';

import 'secure_session_service.dart';

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.parentEmail,
    this.forcePasswordReset = false,
  });

  final String id;
  final String email;
  final String displayName;
  final String role;
  final String? parentEmail;
  final bool forcePasswordReset;
}

class AuthService {
  AuthService({http.Client? client}) : _client = client ?? http.Client();

  static final AuthService instance = AuthService();
  static const roles = {'student', 'teacher', 'parent', 'admin'};
  static const invalidCredentialsMessage =
      'Invalid email, password, or role. Please check your credentials or '
      'Sign Up.';
  static const accountNotFoundMessage =
      'Incorrect email, password, or role. Please Sign Up first.';
  static const pendingApprovalMessage =
      'Your student registration is awaiting administrator approval.';
  static const blockedAccountMessage =
      'This account has been blocked. Contact an administrator for help.';
  static const rejectedAccountMessage =
      'This registration was not approved. Contact an administrator for help.';

  final http.Client _client;

  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
    required String role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Enter your email and password.');
    }
    final localUser = await DbHelper.instance.authenticateLocalUser(
      email: normalizedEmail,
      password: password,
      role: normalizedRole,
    );

    if (localUser != null) {
      _ensureAccountCanSignIn(localUser['account_status']);
      if (DbHelper.instance.isDemoAccount(normalizedEmail) ||
          localUser['is_synced'] == 0 ||
          ApiConstants.apiBaseUrl.trim().isEmpty) {
        return _fromRecord(localUser);
      }
      final connection = await Connectivity().checkConnectivity();
      final accessToken = await SecureSessionService.instance.getAccessToken(
        email: normalizedEmail,
      );
      if (accessToken != null ||
          !connection.any((result) => result != ConnectivityResult.none) ||
          ApiConstants.apiBaseUrl.trim().isEmpty) {
        return _fromRecord(localUser);
      }
      try {
        return await _signInCloud(normalizedEmail, password, role);
      } on http.ClientException {
        return _fromRecord(localUser);
      } on TimeoutException {
        return _fromRecord(localUser);
      }
    }
    if (kDebugMode) {
      debugPrint(
        'Local sign-in did not match credentials '
        '(role=$normalizedRole, email=${_maskEmail(normalizedEmail)}).',
      );
    }
    final cachedUser = await DbHelper.instance.getUserByEmail(normalizedEmail);
    if (cachedUser != null) {
      _ensureAccountCanSignIn(cachedUser['account_status']);
    }
    if (cachedUser != null &&
        (cachedUser['role'] as String).trim().toLowerCase() != normalizedRole) {
      throw const AuthException(accountNotFoundMessage);
    }
    final hasLocalCredential = await DbHelper.instance.hasLocalCredential(
      email: normalizedEmail,
      role: normalizedRole,
    );
    if (cachedUser != null && hasLocalCredential) {
      if (ApiConstants.apiBaseUrl.trim().isEmpty) {
        throw const AuthException(invalidCredentialsMessage);
      }
    }
    if (ApiConstants.apiBaseUrl.trim().isEmpty) {
      if (cachedUser == null) {
        throw const AuthException(accountNotFoundMessage);
      }
      throw const AuthException(
        'This account has no offline password. Configure cloud sign-in or '
        'connect to the internet to authenticate.',
      );
    }
    final connection = await Connectivity().checkConnectivity();
    if (!connection.any((result) => result != ConnectivityResult.none)) {
      if (cachedUser != null && hasLocalCredential) {
        throw const AuthException(invalidCredentialsMessage);
      }
      if (cachedUser == null) {
        throw const AuthException(accountNotFoundMessage);
      }
      throw const AuthException(invalidCredentialsMessage);
    }

    return _signInCloud(normalizedEmail, password, normalizedRole);
  }

  String _maskEmail(String email) {
    final separator = email.indexOf('@');
    if (separator <= 0) return '<invalid>';
    return '${email[0]}***${email.substring(separator)}';
  }

  void _ensureAccountCanSignIn(Object? status) {
    switch (status) {
      case 'pending':
        throw const AuthException(pendingApprovalMessage);
      case 'rejected':
        throw const AuthException(rejectedAccountMessage);
      case 'blocked':
        throw const AuthException(blockedAccountMessage);
    }
  }

  Future<AuthenticatedUser> _signInCloud(
    String email,
    String password,
    String role,
  ) async {
    final baseUrl = ApiConstants.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'role': role.trim().toLowerCase(),
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AuthException(invalidCredentialsMessage);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        'Cloud sign-in failed (${response.statusCode}). Please try again.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Sign-in returned an invalid response.');
    }
    final profile = decoded['user'] is Map<String, dynamic>
        ? decoded['user'] as Map<String, dynamic>
        : decoded;
    final session = decoded['session'];
    final accessToken =
        decoded['access_token'] ??
        decoded['accessToken'] ??
        (session is Map<String, dynamic> ? session['access_token'] : null);
    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException(
        'Sign-in response must include an access token.',
      );
    }
    final user = _fromRecord(profile);
    if (user.role != role.trim().toLowerCase()) {
      throw const AuthException(invalidCredentialsMessage);
    }
    await DbHelper.instance.cacheUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      role: user.role,
      parentEmail: user.parentEmail,
    );
    await DbHelper.instance.saveLocalCredential(
      email: user.email,
      password: password,
      userId: user.id,
    );
    await SecureSessionService.instance.saveAccessToken(
      accessToken,
      email: user.email,
    );
    return user;
  }

  Future<AuthenticatedUser> register({
    required String email,
    required String displayName,
    required String password,
    required String role,
    String? schoolId,
    String? section,
    String? gender,
    String? assignedSubjects,
    String? studentUsername,
  }) async {
    try {
      await DbHelper.instance.registerUser(
        email: email,
        displayName: displayName,
        password: password,
        role: role,
        schoolId: schoolId,
        section: section,
        gender: gender,
        assignedSubjects: assignedSubjects,
        studentUsername: studentUsername,
      );
      final record = await DbHelper.instance.getUserByEmail(email);
      if (record == null) {
        throw StateError('Registered account could not be loaded.');
      }
      return _fromRecord(record);
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const AuthException(
          'An account with this email address already exists.',
        );
      }
      rethrow;
    }
  }

  AuthenticatedUser _fromRecord(Map<dynamic, dynamic> record) {
    final id = record['id']?.toString().trim() ?? '';
    final email = (record['email'] ?? '').toString().trim().toLowerCase();
    final name = (record['display_name'] ?? record['displayName'] ?? email)
        .toString()
        .trim();
    final role = (record['role'] ?? '').toString().trim().toLowerCase();
    if (id.isEmpty || email.isEmpty || name.isEmpty || !roles.contains(role)) {
      throw const FormatException(
        'The account response must include id, email, display name, and a '
        'valid role (student, teacher, parent, or admin).',
      );
    }
    return AuthenticatedUser(
      id: id,
      email: email,
      displayName: name,
      role: role,
      parentEmail: (record['parent_email'] ?? record['parentEmail'])
          ?.toString(),
      forcePasswordReset:
          record['force_password_reset'] == 1 ||
          record['force_password_reset'] == '1' ||
          record['forcePasswordReset'] == true,
    );
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
