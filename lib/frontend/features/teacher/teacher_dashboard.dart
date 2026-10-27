import 'package:flutter/material.dart';

import 'package:i_am_astudent/frontend/features/student/offline_textbooks_screen.dart';
import 'package:i_am_astudent/frontend/shared/dashboard_scaffold.dart';
import 'package:i_am_astudent/frontend/shared/screens/progress_screen.dart';

import 'create_quiz_screen.dart';

class TeacherDashboard extends StatelessWidget {
  const TeacherDashboard({required this.email, super.key});

  final String email;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return DashboardScaffold(
      title: 'Teacher Dashboard',
      role: 'Teacher',
      email: email,
      children: [
        const DashboardWelcome(
          heading: 'Teaching resources',
          description: 'Prepare quizzes and share learning materials.',
        ),
        const SizedBox(height: 20),
        DashboardActionCard(
          icon: Icons.edit_note,
          title: 'Quiz library',
          description: 'Create quizzes and manage multiple-choice questions.',
          onTap: () => _open(context, CreateQuizScreen(teacherEmail: email)),
        ),
        DashboardActionCard(
          icon: Icons.upload_file_outlined,
          title: 'Textbook library',
          description: 'Add or remove locally available study topics.',
          onTap: () =>
              _open(context, const OfflineTextbooksScreen(role: 'teacher')),
        ),
        DashboardActionCard(
          icon: Icons.insights_outlined,
          title: 'Class progress',
          description: 'Review practice scores available on this device.',
          onTap: () =>
              _open(context, ProgressScreen(email: email, role: 'teacher')),
        ),
      ],
    );
  }
}
