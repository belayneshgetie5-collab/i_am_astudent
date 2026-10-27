import 'dart:async';

import 'package:flutter/material.dart';

import 'package:i_am_astudent/backend/services/auth_service.dart';
import 'package:i_am_astudent/backend/services/sync_service.dart';
import 'package:i_am_astudent/core/services/session_service.dart';
import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/constants/app_colors.dart';
import 'package:i_am_astudent/frontend/features/admin/admin_dashboard.dart';
import 'package:i_am_astudent/frontend/features/parent/parent_dashboard.dart';
import 'package:i_am_astudent/frontend/features/student/student_dashboard.dart';
import 'package:i_am_astudent/frontend/features/teacher/teacher_dashboard.dart';
import 'package:i_am_astudent/frontend/features/auth/required_password_reset_dialog.dart';
import 'package:i_am_astudent/frontend/shared/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _signInRoles = {
    'student': 'Student',
    'teacher': 'Teacher',
    'parent': 'Parent',
    'admin': 'Admin',
  };

  static const _signUpRoles = {
    'student': 'Student',
    'teacher': 'Teacher',
    'parent': 'Parent',
  };

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _schoolIdController;
  late final TextEditingController _subjectsController;
  late final TextEditingController _studentUsernameController;
  String _selectedRole = 'student';
  String _selectedSection = 'Section A';
  String _selectedGender = 'Male';
  bool _passwordVisible = false;
  bool _signingIn = false;
  bool _isSigningUp = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _schoolIdController = TextEditingController();
    _subjectsController = TextEditingController();
    _studentUsernameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _schoolIdController.dispose();
    _subjectsController.dispose();
    _studentUsernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_signingIn || !mounted) return;
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    final email = _emailController.text.trim();
    setState(() => _signingIn = true);
    try {
      if (_isSigningUp) {
        final registeredRole = _selectedRole;
        await AuthService.instance.register(
          email: email,
          displayName: _nameController.text.trim(),
          password: _passwordController.text,
          role: registeredRole,
          schoolId: registeredRole == 'student'
              ? _schoolIdController.text.trim()
              : null,
          section: registeredRole == 'student' ? _selectedSection : null,
          gender: registeredRole == 'student' ? _selectedGender : null,
          assignedSubjects: registeredRole == 'teacher'
              ? _subjectsController.text.trim()
              : null,
          studentUsername: registeredRole == 'student'
              ? _studentUsernameController.text.trim()
              : null,
        );
        if (!mounted) return;
        _toggleFormMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              registeredRole == 'student'
                  ? 'Registration submitted. Sign in after an administrator approves your account.'
                  : 'Account created successfully! Please sign in with your credentials.',
            ),
          ),
        );
        return;
      }

      final user = await AuthService.instance.signIn(
        email: email,
        password: _passwordController.text,
        role: _selectedRole,
      );
      if (user.forcePasswordReset) {
        if (!mounted) return;
        final newPassword = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const RequiredPasswordResetDialog(),
        );
        if (newPassword == null || !mounted) return;
        await DbHelper.instance.completeTeacherPasswordReset(
          userId: user.id,
          email: user.email,
          password: newPassword,
        );
      }
      await SessionService.instance.saveSession(user.email, user.role);
      final dashboard = switch (user.role) {
        'student' => StudentDashboard(email: user.email),
        'teacher' => TeacherDashboard(email: user.email),
        'parent' => ParentDashboard(email: user.email),
        'admin' => AdminDashboard(email: user.email),
        _ => throw StateError('Unsupported role: ${user.role}'),
      };
      if (!mounted) return;
      if (!_isSigningUp && !DbHelper.instance.isDemoAccount(user.email)) {
        unawaited(
          SyncService.instance.start(email: user.email).catchError((
            Object error,
          ) {
            debugPrint('Background sync could not start: $error');
          }),
        );
      }

      Navigator.of(context)
          .pushReplacement(MaterialPageRoute<void>(builder: (_) => dashboard));
    } catch (error) {
      if (!mounted) return;
      final isInvalidSignIn =
          error is AuthException &&
          (error.message == AuthService.invalidCredentialsMessage ||
              error.message == AuthService.accountNotFoundMessage);
      final message = isInvalidSignIn
          ? AuthService.accountNotFoundMessage
          : error is AuthException
          ? error.message
          : '${_isSigningUp ? 'Sign-up' : 'Sign-in'} failed: $error';
      final canOfferSignUp = !_isSigningUp && isInvalidSignIn;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: canOfferSignUp
                ? SnackBarAction(
                    label: 'Create account',
                    onPressed: _openSignUp,
                  )
                : null,
          ),
        );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _toggleFormMode() {
    setState(() {
      _isSigningUp = !_isSigningUp;
      _selectedRole = 'student';
      _selectedSection = 'Section A';
      _selectedGender = 'Male';
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _schoolIdController.clear();
      _subjectsController.clear();
      _studentUsernameController.clear();
      _formKey.currentState?.reset();
    });
  }

  void _openSignUp() {
    if (_isSigningUp || !mounted) return;
    _toggleFormMode();
  }

  @override
  Widget build(BuildContext context) {
    final roleOptions = _isSigningUp ? _signUpRoles : _signInRoles;
    final selectedRole = roleOptions.containsKey(_selectedRole)
        ? _selectedRole
        : roleOptions.keys.first;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 3,
                color: AppColors.iceBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: const BorderSide(color: AppColors.powderBlue),
                ),
                shadowColor: Colors.black.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.powderBlue,
                          child: Icon(
                            Icons.school_outlined,
                            color: AppColors.ink,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'SAAMEP',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Smart preparation for ministry examinations',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 28),
                        DropdownButtonFormField<String>(
                          initialValue: selectedRole,
                          decoration: InputDecoration(
                            labelText: _isSigningUp
                                ? 'Sign up as'
                                : 'Sign in as',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                          ),
                          items: roleOptions.entries
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role.key,
                                  child: Text(role.value),
                                ),
                              )
                              .toList(),
                          onChanged: _signingIn
                              ? null
                              : (role) {
                                  if (role != null) {
                                    setState(() => _selectedRole = role);
                                  }
                                },
                        ),
                        const SizedBox(height: 16),
                        if (_isSigningUp) ...[
                          TextFormField(
                            key: const ValueKey('nameField'),
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: 'Enter your name',
                              prefixIcon: Icon(Icons.person_outline),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                            ),
                            validator: (value) =>
                                value?.trim().isNotEmpty ?? false
                                ? null
                                : 'Enter your name.',
                          ),
                          const SizedBox(height: 16),
                          if (_selectedRole == 'student') ...[
                            TextFormField(
                              key: const ValueKey('studentUsernameField'),
                              controller: _studentUsernameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Student username',
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                              validator: (value) {
                                if (_selectedRole != 'student') return null;
                                return RegExp(r'^[a-zA-Z0-9._-]{3,32}$')
                                        .hasMatch(value?.trim() ?? '')
                                    ? null
                                    : 'Use 3–32 letters, numbers, dots, underscores, or hyphens.';
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey('schoolIdField'),
                              controller: _schoolIdController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'School ID / proof reference',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              validator: (value) =>
                                  _selectedRole != 'student' ||
                                      (value?.trim().isNotEmpty ?? false)
                                  ? null
                                  : 'Enter your School ID or proof reference.',
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSection,
                              decoration: const InputDecoration(
                                labelText: 'Grade 8 section',
                              ),
                              items:
                                  const ['Section A', 'Section B', 'Section C']
                                      .map(
                                        (section) => DropdownMenuItem(
                                          value: section,
                                          child: Text(section),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (section) {
                                if (section != null) {
                                  setState(() => _selectedSection = section);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedGender,
                              decoration: const InputDecoration(
                                labelText: 'Gender',
                              ),
                              items: const ['Male', 'Female']
                                  .map(
                                    (gender) => DropdownMenuItem(
                                      value: gender,
                                      child: Text(gender),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (gender) {
                                if (gender != null) {
                                  setState(() => _selectedGender = gender);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_selectedRole == 'teacher') ...[
                            TextFormField(
                              key: const ValueKey('subjectsField'),
                              controller: _subjectsController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Assigned subjects (optional)',
                                prefixIcon: Icon(Icons.menu_book_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                        TextFormField(
                          key: const ValueKey('emailField'),
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText:
                                _selectedRole == 'student' && !_isSigningUp
                                ? 'Enter your email or student username'
                                : 'Enter your email',
                            prefixIcon: Icon(Icons.email_outlined),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (_selectedRole == 'student' &&
                                !_isSigningUp &&
                                RegExp(r'^[a-zA-Z0-9._-]{3,32}$')
                                    .hasMatch(email)) {
                              return null;
                            }
                            if (email.isEmpty ||
                                !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(email)) {
                              return 'Enter a valid email address or student username.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('passwordField'),
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _passwordVisible
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 8) {
                              return 'Password must be at least 8 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: _isSigningUp ? 'Sign up' : 'Sign in',
                          onPressed: _submit,
                          isLoading: _signingIn,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _signingIn ? null : _toggleFormMode,
                          child: Text(
                            _isSigningUp
                                ? 'Already have an account? Sign in'
                                : "Don't have an account? Sign up",
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
