import 'package:flutter/material.dart';

import 'package:i_am_astudent/backend/services/secure_session_service.dart';
import 'package:i_am_astudent/backend/services/sync_service.dart';
import 'package:i_am_astudent/core/services/session_service.dart';
import 'package:i_am_astudent/frontend/constants/app_colors.dart';
import 'package:i_am_astudent/frontend/features/auth/login_screen.dart';
import 'package:i_am_astudent/frontend/shared/screens/about_and_contact_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({required this.role, required this.email, super.key});

  final String role;
  final String email;

  void _openSection(BuildContext context, CommonPageSection section) {
    Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AboutAndContactScreen(section: section, role: role, email: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: AppColors.softSkyBlue),
              accountName: Text(role),
              accountEmail: Text(email),
              currentAccountPicture: CircleAvatar(
                backgroundColor: AppColors.aliceBlue,
                child: Text(
                  email.isEmpty ? '?' : email.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              onDetailsPressed: () =>
                  _openSection(context, CommonPageSection.profile),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard Home'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile / Account Info'),
              onTap: () => _openSection(context, CommonPageSection.profile),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About SAAMEP'),
              onTap: () => _openSection(context, CommonPageSection.about),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Help & Contact Us'),
              onTap: () => _openSection(context, CommonPageSection.support),
            ),
            ListTile(
              leading: const Icon(Icons.sync_outlined),
              title: const Text('Sync Status & Settings'),
              onTap: () => _openSection(context, CommonPageSection.settings),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                try {
                  await SessionService.instance.clearSession();
                  await SyncService.instance.stop();
                  await SecureSessionService.instance.clear();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not sign out: $error')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
