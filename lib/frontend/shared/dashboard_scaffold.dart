import 'package:flutter/material.dart';

import 'package:i_am_astudent/frontend/constants/app_colors.dart';
import 'package:i_am_astudent/frontend/shared/app_bar.dart';
import 'package:i_am_astudent/frontend/shared/custom_drawer.dart';

class DashboardScaffold extends StatelessWidget {
  const DashboardScaffold({
    required this.title,
    required this.role,
    required this.email,
    required this.children,
    super.key,
  });

  final String title;
  final String role;
  final String email;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SaamepAppBar(title: title),
      drawer: AppDrawer(role: role, email: email),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardWelcome extends StatelessWidget {
  const DashboardWelcome({
    required this.heading,
    required this.description,
    super.key,
  });

  final String heading;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.babyBlue, AppColors.powderBlue],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

class DashboardActionCard extends StatelessWidget {
  const DashboardActionCard({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.iceBlue,
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: CircleAvatar(
          backgroundColor: AppColors.powderBlue,
          foregroundColor: AppColors.ink,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(description),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
