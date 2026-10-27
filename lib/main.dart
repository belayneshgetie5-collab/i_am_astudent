import 'package:flutter/material.dart';

import 'package:i_am_astudent/core/services/session_service.dart';
import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/constants/app_colors.dart';
import 'package:i_am_astudent/frontend/features/admin/admin_dashboard.dart';
import 'package:i_am_astudent/frontend/features/auth/login_screen.dart';
import 'package:i_am_astudent/frontend/features/parent/parent_dashboard.dart';
import 'package:i_am_astudent/frontend/features/student/student_dashboard.dart';
import 'package:i_am_astudent/frontend/features/teacher/teacher_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbHelper.instance.initialize();
  await DbHelper.instance.database;
  await DbHelper.instance.seedInitialDataIfEmpty();
  runApp(const SaamepApp());
}

class SaamepApp extends StatelessWidget {
  const SaamepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAAMEP',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      themeMode: ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      home: const AuthGate(),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: AppColors.electricLightBlue,
            brightness: Brightness.light,
          ).copyWith(
            primary: AppColors.ink,
            onPrimary: AppColors.aliceBlue,
            secondary: AppColors.babyBlue,
            onSecondary: AppColors.ink,
            surface: AppColors.iceBlue,
            onSurface: AppColors.ink,
          ),
      scaffoldBackgroundColor: AppColors.aliceBlue,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.softSkyBlue,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(color: AppColors.iceBlue),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.babyBlue,
          foregroundColor: AppColors.ink,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.babyBlue,
          foregroundColor: AppColors.ink,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.ink),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.iceBlue,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.powderBlue),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.electricLightBlue,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<({String email, String role})?> _session;

  @override
  void initState() {
    super.initState();
    _session = _restoreSession();
  }

  Future<({String email, String role})?> _restoreSession() async {
    final session = await SessionService.instance.getSession();
    if (session == null) return null;

    await DbHelper.instance.database;
    final user = await DbHelper.instance.getUserByEmail(session.email);
    final databaseRole = user?['role']?.toString().trim().toLowerCase();
    final accountStatus = user?['account_status']?.toString();
    if (user == null ||
        databaseRole != session.role ||
        accountStatus == 'pending' ||
        accountStatus == 'rejected' ||
        accountStatus == 'blocked') {
      await SessionService.instance.clearSession();
      return null;
    }
    return session;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String email, String role})?>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not restore your session.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _session = _restoreSession();
                        });
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final session = snapshot.data;
        if (session == null) return const LoginScreen();
        return switch (session.role) {
          'student' => StudentDashboard(email: session.email),
          'teacher' => TeacherDashboard(email: session.email),
          'parent' => ParentDashboard(email: session.email),
          'admin' => AdminDashboard(email: session.email),
          _ => const LoginScreen(),
        };
      },
    );
  }
}
