import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:i_am_astudent/backend/services/secure_session_service.dart';
import 'package:i_am_astudent/backend/services/sync_service.dart';
import 'package:i_am_astudent/core/services/session_service.dart';
import 'package:i_am_astudent/database/db_helper.dart';
import 'package:i_am_astudent/frontend/constants/app_colors.dart';
import 'package:i_am_astudent/frontend/features/auth/login_screen.dart';
import 'package:i_am_astudent/frontend/shared/screens/progress_screen.dart';

import 'offline_textbooks_screen.dart';
import 'practice_exam_screen.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({required this.email, super.key});

  final String email;

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  late Future<_DashboardData> _dashboard;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _dashboard = _loadDashboard();
  }

  @override
  void didUpdateWidget(covariant StudentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email != widget.email) _dashboard = _loadDashboard();
  }

  Future<_DashboardData> _loadDashboard() async {
    final user = await DbHelper.instance.getUserByEmail(widget.email);
    if (user == null || user['id'] == null) {
      throw StateError(
        'Your student profile could not be found on this device.',
      );
    }
    final userId = user['id']! as String;
    final stats = await DbHelper.instance.getStudentStats(userId);
    final attempts = await DbHelper.instance.getRecentExamAttempts(userId);
    return _DashboardData(
      userId: userId,
      displayName: (user['display_name'] as String?)?.trim().isNotEmpty == true
          ? user['display_name']! as String
          : 'Student',
      stats: stats,
      attempts: attempts,
    );
  }

  Future<void> _refresh() async {
    final updated = _loadDashboard();
    setState(() => _dashboard = updated);
    await updated;
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await SessionService.instance.clearSession();
      await SyncService.instance.stop();
      await SecureSessionService.instance.clear();
      if (!mounted) return;
      await Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not securely sign out: $error')),
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _showNotifications() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: const Text('You are all caught up.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openPracticeExams() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeExamScreen(email: widget.email),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _resumeAttempt() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeExamScreen(email: widget.email),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _showNotifications,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.deepOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Secure logout',
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<_DashboardData>(
            future: _dashboard,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    const Icon(Icons.cloud_off_outlined, size: 42),
                    const SizedBox(height: 12),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Could not load your dashboard: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _dashboard = _loadDashboard()),
                        child: const Text('Try again'),
                      ),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth > 1000
                      ? 1000.0
                      : constraints.maxWidth;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                    children: [
                      Center(
                        child: SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _WelcomeHeader(name: data.displayName),
                              if (data.inProgressAttempt != null) ...[
                                const SizedBox(height: 16),
                                _ResumeBanner(
                                  attempt: data.inProgressAttempt!,
                                  onResume: _resumeAttempt,
                                ),
                              ],
                              const SizedBox(height: 24),
                              Text(
                                'Your progress',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              _StatsGrid(stats: data.stats),
                              const SizedBox(height: 24),
                              Text(
                                'What would you like to do?',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              _ActionGrid(
                                onTakeExam: _openPracticeExams,
                                onSubjects: () => _open(
                                  const OfflineTextbooksScreen(role: 'student'),
                                ),
                                onAnalytics: () => _open(
                                  ProgressScreen(
                                    email: widget.email,
                                    role: 'student',
                                  ),
                                ),
                                onHistory: () => _open(
                                  _StudentHistoryScreen(
                                    email: widget.email,
                                    userId: data.userId,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _RecentAttempts(
                                attempts: data.attempts,
                                userId: data.userId,
                                email: widget.email,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.userId,
    required this.displayName,
    required this.stats,
    required this.attempts,
  });

  final String userId;
  final String displayName;
  final Map<String, Object?> stats;
  final List<Map<String, Object?>> attempts;

  Map<String, Object?>? get inProgressAttempt {
    for (final attempt in attempts) {
      if (attempt['status'] == 'in_progress') return attempt;
    }
    return null;
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.babyBlue, AppColors.powderBlue],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.aliceBlue,
            child: Icon(Icons.school_outlined, color: AppColors.ink, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, $firstName!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Grade 12 - Natural Science',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final Map<String, Object?> stats;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 680 ? 3 : 2;
    final total = stats['total_exams_taken']! as num;
    final average = stats['average_score']! as num;
    final streak = stats['study_streak']! as num;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: columns == 3 ? 1.65 : 1.2,
      children: [
        _StatCard(
          label: 'Total Exams Taken',
          value: total.toString(),
          icon: Icons.edit_note_rounded,
          color: AppColors.ink,
        ),
        _StatCard(
          label: 'Average Score',
          value: '${average.toStringAsFixed(1)}%',
          icon: Icons.track_changes_outlined,
          color: const Color(0xFF00897B),
        ),
        _StatCard(
          label: 'Study Streak',
          value: '${streak.toString()} days',
          icon: Icons.local_fire_department_outlined,
          color: const Color(0xFFE66A24),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.iceBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE9EAF1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.onTakeExam,
    required this.onSubjects,
    required this.onAnalytics,
    required this.onHistory,
  });

  final VoidCallback onTakeExam;
  final VoidCallback onSubjects;
  final VoidCallback onAnalytics;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _ActionCard(
        icon: Icons.quiz_outlined,
        title: 'Take Practice Exam',
        description: 'Select Subject & Year (2012–2015 E.C.) to start timed Ministry Practice Test.',
        buttonText: 'Start Exam',
        onPressed: onTakeExam,
      ),
      _ActionCard(
        icon: Icons.menu_book_outlined,
        title: 'Subject-wise Practice',
        description:
            'Chapter-by-Chapter study with instant answer explanations.',
        buttonText: 'Explore Subjects',
        onPressed: onSubjects,
      ),
      _ActionCard(
        icon: Icons.insights_outlined,
        title: 'Performance Analytics',
        description:
            'Detailed score breakdown and AI recommendations for weak topics.',
        buttonText: 'View Analytics',
        onPressed: onAnalytics,
      ),
      _ActionCard(
        icon: Icons.history_rounded,
        title: 'Exam History & Review',
        description:
            'Review past test attempts, correct answers, and explanations.',
        buttonText: 'Review Answers',
        onPressed: onHistory,
      ),
    ];
    final columns = MediaQuery.sizeOf(context).width >= 720 ? 2 : 1;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: columns == 2 ? 1.5 : 1.55,
      children: cards,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.iceBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE9EAF1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: onPressed,
                child: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.attempt, required this.onResume});

  final Map<String, Object?> attempt;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFFFF5E6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFD89A)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(
          Icons.play_circle_outline_rounded,
          color: Color(0xFF9A5B00),
        ),
        title: const Text(
          'Resume Unfinished Test',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          (attempt['subject'] as String?)?.isNotEmpty == true
              ? attempt['subject']! as String
              : 'Continue where you left off',
        ),
        trailing: FilledButton(
          onPressed: onResume,
          child: const Text('Resume'),
        ),
      ),
    );
  }
}

class _RecentAttempts extends StatelessWidget {
  const _RecentAttempts({
    required this.attempts,
    required this.userId,
    required this.email,
  });

  final List<Map<String, Object?>> attempts;
  final String userId;
  final String email;

  @override
  Widget build(BuildContext context) {
    final completed = attempts
        .where((attempt) => attempt['status'] == 'completed')
        .take(3)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent exams',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _StudentHistoryScreen(email: email, userId: userId),
                ),
              ),
              child: const Text('View all'),
            ),
          ],
        ),
        if (completed.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Complete a practice exam to see your history here.'),
            ),
          )
        else
          for (final attempt in completed)
            Card(
              elevation: 0,
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.assignment_turned_in_outlined),
                ),
                title: Text(
                  (attempt['subject'] as String?)?.isNotEmpty == true
                      ? attempt['subject']! as String
                      : 'Practice exam',
                ),
                subtitle: Text(_formatAttemptDate(attempt['completed_at'])),
                trailing: Text(
                  '${_number(attempt['score']).toStringAsFixed(0)} / '
                  '${_number(attempt['total_questions']).toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ExamAttemptReviewScreen(attempt: attempt),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _StudentHistoryScreen extends StatefulWidget {
  const _StudentHistoryScreen({required this.email, required this.userId});

  final String email;
  final String userId;

  @override
  State<_StudentHistoryScreen> createState() => _StudentHistoryScreenState();
}

class _StudentHistoryScreenState extends State<_StudentHistoryScreen> {
  late Future<List<Map<String, Object?>>> _attempts;

  @override
  void initState() {
    super.initState();
    _attempts = DbHelper.instance.getRecentExamAttempts(
      widget.userId,
      limit: 50,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam history & review')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _attempts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load exam history: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final attempts = snapshot.data!;
          if (attempts.isEmpty) {
            return const Center(
              child: Text(
                'Your completed and unfinished exams will appear here.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: attempts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final attempt = attempts[index];
              final inProgress = attempt['status'] == 'in_progress';
              return Card(
                child: ListTile(
                  leading: Icon(
                    inProgress
                        ? Icons.pending_actions_outlined
                        : Icons.assignment_turned_in_outlined,
                  ),
                  title: Text(
                    (attempt['subject'] as String?)?.isNotEmpty == true
                        ? attempt['subject']! as String
                        : 'Practice exam',
                  ),
                  subtitle: Text(
                    '${inProgress ? 'In progress' : 'Completed'} · '
                    '${_formatAttemptDate(attempt['completed_at'])}',
                  ),
                  trailing: inProgress
                      ? const Icon(Icons.play_arrow)
                      : Text(
                          '${_number(attempt['score']).toStringAsFixed(0)} / '
                          '${_number(attempt['total_questions']).toStringAsFixed(0)}',
                        ),
                  onTap: () {
                    final screen = inProgress
                        ? PracticeExamScreen(email: widget.email)
                        : _ExamAttemptReviewScreen(attempt: attempt);
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => screen));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ExamAttemptReviewScreen extends StatefulWidget {
  const _ExamAttemptReviewScreen({required this.attempt});

  final Map<String, Object?> attempt;

  @override
  State<_ExamAttemptReviewScreen> createState() =>
      _ExamAttemptReviewScreenState();
}

class _ExamAttemptReviewScreenState extends State<_ExamAttemptReviewScreen> {
  late final Future<List<Map<String, Object?>>> _questions = _loadQuestions();

  Future<List<Map<String, Object?>>> _loadQuestions() async {
    final quizId = widget.attempt['quiz_id'] as String?;
    if (quizId == null) return const [];
    return DbHelper.instance.getCachedQuestions(quizId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review answers')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _questions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load answer review: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final questions = snapshot.data!;
          if (questions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Answer review is unavailable for this older exam attempt.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final decodedAnswers = jsonDecode(
            widget.attempt['answers_json'] as String? ?? '[]',
          );
          if (decodedAnswers is! List ||
              decodedAnswers.any(
                (answer) => answer != null && answer is! String,
              )) {
            return const Center(
              child: Text('Saved answer data for this attempt is invalid.'),
            );
          }
          final answers = decodedAnswers.cast<String?>();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: questions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final question = questions[index];
              final selected = index < answers.length ? answers[index] : null;
              final answer = question['answer']! as String;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Question ${index + 1}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        question['prompt']! as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Text('Your answer: ${selected ?? 'Not answered'}'),
                      const SizedBox(height: 4),
                      Text(
                        'Correct answer: $answer',
                        style: const TextStyle(
                          color: Color(0xFF197245),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ((question['explanation'] as String?)?.isNotEmpty ??
                          false) ...[
                        const SizedBox(height: 8),
                        Text(question['explanation']! as String),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

double _number(Object? value) => value is num ? value.toDouble() : 0;

String _formatAttemptDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Date unavailable';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
