import 'package:flutter/material.dart';

import 'package:i_am_astudent/database/db_helper.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({required this.email, required this.role, super.key});

  final String email;
  final String role;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<List<Map<String, Object?>>> _scores;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final db = DbHelper.instance;
    _scores = switch (widget.role.toLowerCase()) {
      'parent' => db.getScoresForParent(widget.email),
      'student' => db.getScoresForStudent(widget.email),
      _ => db.getAllScores(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.role} performance')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _scores,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load scores: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final scores = snapshot.data!;
          if (scores.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No exam scores are available yet. Scores saved offline '
                  'will appear here and sync when the device is online.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final earned = scores.fold<double>(
            0,
            (sum, score) => sum + (score['score']! as num).toDouble(),
          );
          final possible = scores.fold<double>(
            0,
            (sum, score) => sum + (score['total']! as num).toDouble(),
          );
          final average = possible == 0 ? 0 : earned / possible * 100;
          return RefreshIndicator(
            onRefresh: () async => setState(_refresh),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: Text('${average.toStringAsFixed(0)}% overall'),
                    subtitle: Text('${scores.length} exams completed'),
                  ),
                ),
                const SizedBox(height: 10),
                for (final score in scores)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.assignment_turned_in_outlined),
                      title: Text(
                        (score['quiz_title'] as String?) ?? 'Practice exam',
                      ),
                      subtitle: Text(
                        [
                          if (score['student_name'] is String)
                            score['student_name']! as String,
                          _formatDate(score['completed_at']! as String),
                        ].join(' · '),
                      ),
                      trailing: Text(
                        '${(score['score']! as num).toStringAsFixed(0)} / '
                        '${(score['total']! as num).toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String isoDate) {
    final date = DateTime.tryParse(isoDate)?.toLocal();
    if (date == null) return isoDate;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
