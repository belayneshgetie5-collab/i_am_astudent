import 'package:flutter/material.dart';

import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/shared/dashboard_scaffold.dart';
import 'package:i_am_astudent/frontend/shared/screens/progress_screen.dart';

class ParentDashboard extends StatelessWidget {
  const ParentDashboard({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context) {
    return DashboardScaffold(
      title: 'Parent Dashboard',
      role: 'Parent',
      email: email,
      children: [
        const DashboardWelcome(
          heading: 'Support their progress',
          description: 'Follow learning activity and exam preparation.',
        ),
        const SizedBox(height: 20),
        DashboardActionCard(
          icon: Icons.link_outlined,
          title: 'Link a student',
          description: 'Submit a student ID for administrator verification.',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _ParentLinkRequestScreen(email: email),
            ),
          ),
        ),
        DashboardActionCard(
          icon: Icons.trending_up,
          title: 'Performance overview',
          description: 'View exam results for learners linked to your account.',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProgressScreen(email: email, role: 'parent'),
            ),
          ),
        ),
        DashboardActionCard(
          icon: Icons.event_note_outlined,
          title: 'Recent activity',
          description: 'See completed practice exams and study milestones.',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProgressScreen(email: email, role: 'parent'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ParentLinkRequestScreen extends StatefulWidget {
  const _ParentLinkRequestScreen({required this.email});

  final String email;

  @override
  State<_ParentLinkRequestScreen> createState() =>
      _ParentLinkRequestScreenState();
}

class _ParentLinkRequestScreenState extends State<_ParentLinkRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _studentIdController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _studentIdController = TextEditingController();
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() => _submitting = true);
    try {
      await DbHelper.instance.createParentLinkRequest(
        parentEmail: widget.email,
        studentId: _studentIdController.text.trim(),
      );
      if (!mounted) return;
      _studentIdController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link request submitted for administrator review.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit link request: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link a student')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the student’s School ID or student ID. '
                    'An administrator will review your request.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _studentIdController,
                    decoration: const InputDecoration(
                      labelText: 'Student ID / School ID',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) => value?.trim().isNotEmpty == true
                        ? null
                        : 'Enter a student ID.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _submitting ? 'Submitting…' : 'Submit for review',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
