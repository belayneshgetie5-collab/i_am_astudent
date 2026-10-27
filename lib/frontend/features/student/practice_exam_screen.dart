import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:i_am_astudent/backend/services/ai_service.dart';
import 'package:i_am_astudent/database/db_helper.dart';

class PracticeExamScreen extends StatefulWidget {
  const PracticeExamScreen({
    required this.email,
    this.resumeAttempt,
    super.key,
  });

  final String email;
  final Map<String, dynamic>? resumeAttempt;

  @override
  State<PracticeExamScreen> createState() => _PracticeExamScreenState();
}

class _PracticeExamScreenState extends State<PracticeExamScreen> {
  Future<List<Map<String, Object?>>>? _quizzes;
  bool _resumeLoading = false;
  String? _resumeError;

  @override
  void initState() {
    super.initState();
    if (widget.resumeAttempt == null) {
      _quizzes = DbHelper.instance.getQuizzes();
    } else {
      _resumeLoading = true;
      _resumeExam();
    }
  }

  Future<void> _resumeExam() async {
    try {
      final quizId = widget.resumeAttempt?['quiz_id'];
      if (quizId is! String || quizId.isEmpty) {
        throw const FormatException(
          'This unfinished attempt is missing its quiz information.',
        );
      }
      final quiz = await DbHelper.instance.getQuiz(quizId);
      if (quiz == null) {
        throw StateError(
          'The quiz for this unfinished attempt is unavailable.',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => _ExamScreen(
            quiz: quiz,
            studentEmail: widget.email,
            resumeAttempt: Map<String, Object?>.from(widget.resumeAttempt!),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resumeError = error.toString();
        _resumeLoading = false;
      });
    }
  }

  void _openQuiz(
    Map<String, Object?> quiz, {
    Map<String, Object?>? resumeAttempt,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ExamScreen(
          quiz: quiz,
          studentEmail: widget.email,
          resumeAttempt: resumeAttempt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.resumeAttempt != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Resume practice exam')),
        body: Center(
          child: _resumeLoading
              ? const CircularProgressIndicator()
              : Text('Could not resume this exam: $_resumeError'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Practice exams')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _quizzes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load quizzes: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final quizzes = snapshot.data!;
          if (quizzes.isEmpty) {
            return const Center(child: Text('No quizzes are available yet.'));
          }
          return FutureBuilder<Map<String, Object?>?>(
            future: _latestUnfinishedAttempt(),
            builder: (context, attemptSnapshot) {
              if (attemptSnapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load unfinished exam: ${attemptSnapshot.error}',
                  ),
                );
              }
              if (!attemptSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final attempt = attemptSnapshot.data;
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: quizzes.length + (attempt == null ? 0 : 1),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (attempt != null && index == 0) {
                    return Card(
                      color: const Color(0xFFFFF5E6),
                      child: ListTile(
                        leading: const Icon(Icons.play_circle_outline),
                        title: const Text('Resume unfinished test'),
                        subtitle: Text(
                          (attempt['subject'] as String?)?.isNotEmpty == true
                              ? attempt['subject']! as String
                              : 'Continue where you left off',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          final quiz = quizzes.where(
                            (quiz) => quiz['id'] == attempt['quiz_id'],
                          );
                          if (quiz.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'The quiz for this unfinished attempt is unavailable.',
                                ),
                              ),
                            );
                            return;
                          }
                          _openQuiz(quiz.first, resumeAttempt: attempt);
                        },
                      ),
                    );
                  }
                  final quizIndex = index - (attempt == null ? 0 : 1);
                  final quiz = quizzes[quizIndex];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.quiz_outlined),
                      ),
                      title: Text(quiz['title']! as String),
                      subtitle: Text(
                        (quiz['description'] as String?) ??
                            'Ready to take offline',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openQuiz(quiz),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<Map<String, Object?>?> _latestUnfinishedAttempt() async {
    final user = await DbHelper.instance.getUserByEmail(widget.email);
    final userId = user?['id'];
    if (userId is! String || userId.isEmpty) {
      throw StateError('Your student profile could not be found.');
    }
    final attempts = await DbHelper.instance.getRecentExamAttempts(
      userId,
      limit: 50,
    );
    for (final attempt in attempts) {
      if (attempt['status'] == 'in_progress') return attempt;
    }
    return null;
  }
}

class _ExamScreen extends StatefulWidget {
  const _ExamScreen({
    required this.quiz,
    required this.studentEmail,
    this.resumeAttempt,
  });

  final Map<String, Object?> quiz;
  final String studentEmail;
  final Map<String, Object?>? resumeAttempt;

  @override
  State<_ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<_ExamScreen> {
  List<Map<String, Object?>> _questions = const [];
  List<String?> _answers = const [];
  Timer? _timer;
  int _questionIndex = 0;
  int _secondsRemaining = 0;
  bool _loading = true;
  bool _saving = false;
  bool _finished = false;
  String? _loadError;
  String? _userId;
  int? _attemptId;
  Future<void> _progressSave = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
      final user = await DbHelper.instance.getUserByEmail(widget.studentEmail);
      final userId = user?['id'];
      if (userId is! String || userId.isEmpty) {
        throw StateError('Your student profile could not be found.');
      }
      final rows = await DbHelper.instance.getCachedQuestions(
        widget.quiz['id']! as String,
      );
      for (final question in rows) {
        final options = _optionsFor(question);
        if (options.length < 2 ||
            !options.contains(question['answer']) ||
            (question['prompt'] as String?)?.trim().isEmpty != false) {
          throw const FormatException(
            'Quiz contains a malformed multiple-choice question.',
          );
        }
      }
      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _questions = rows;
          _answers = const [];
          _loading = false;
        });
        return;
      }

      final resumeAttempt = widget.resumeAttempt;
      var questionIndex = 0;
      var secondsRemaining = rows.length * 60;
      List<String?> answers = List<String?>.filled(rows.length, null);
      if (resumeAttempt != null) {
        if (resumeAttempt['user_id'] != userId ||
            resumeAttempt['quiz_id'] != widget.quiz['id'] ||
            resumeAttempt['status'] != 'in_progress' ||
            resumeAttempt['id'] is! int) {
          throw const FormatException(
            'This unfinished exam does not match the signed-in student.',
          );
        }
        final savedAnswers = jsonDecode(
          resumeAttempt['answers_json'] as String? ?? '[]',
        );
        if (savedAnswers is! List ||
            savedAnswers.length != rows.length ||
            savedAnswers.any((answer) => answer != null && answer is! String)) {
          throw const FormatException(
            'Saved answers for this unfinished exam are invalid.',
          );
        }
        answers = savedAnswers.cast<String?>();
        final savedIndex = resumeAttempt['question_index'];
        final savedSeconds = resumeAttempt['seconds_remaining'];
        if (savedIndex is! int ||
            savedIndex < 0 ||
            savedIndex >= rows.length ||
            savedSeconds is! int ||
            savedSeconds < 0) {
          throw const FormatException(
            'Saved progress for this unfinished exam is invalid.',
          );
        }
        questionIndex = savedIndex;
        secondsRemaining = savedSeconds;
        _attemptId = resumeAttempt['id']! as int;
      }
      if (!mounted) return;
      setState(() {
        _userId = userId;
        _questions = rows;
        _answers = answers;
        _questionIndex = questionIndex;
        _secondsRemaining = secondsRemaining;
        _loading = false;
      });
      if (resumeAttempt == null) {
        await _persistProgress();
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _finished) return;
        if (_secondsRemaining <= 1) {
          timer.cancel();
          setState(() => _secondsRemaining = 0);
          unawaited(_finish());
        } else {
          setState(() => _secondsRemaining--);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error.toString();
        });
      }
    }
  }

  Future<void> _persistProgress({String status = 'in_progress', int? score}) {
    final operation = _progressSave.then((_) async {
      final userId = _userId;
      if (userId == null || _questions.isEmpty) {
        throw StateError('Exam progress cannot be saved before loading.');
      }
      final savedId = await DbHelper.instance.saveExamAttempt({
        if (_attemptId != null) 'id': _attemptId,
        'user_id': userId,
        'subject': widget.quiz['title'] as String? ?? 'Practice exam',
        'year': widget.quiz['year'] as String? ?? '',
        'score': score ?? 0,
        'total_questions': _questions.length,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'status': status,
        'quiz_id': widget.quiz['id']! as String,
        'answers_json': jsonEncode(_answers),
        'question_index': _questionIndex,
        'seconds_remaining': _secondsRemaining,
      });
      _attemptId = savedId;
    });
    _progressSave = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  void _persistProgressInBackground() {
    _persistProgress().catchError((Object error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save exam progress: $error')),
      );
    });
  }

  Future<void> _finish() async {
    if (_finished || _saving || _questions.isEmpty) return;
    _timer?.cancel();
    setState(() => _saving = true);
    final score = _questions.indexed
        .where((entry) => _answers[entry.$1] == entry.$2['answer'])
        .length;
    try {
      await _persistProgress(status: 'completed', score: score);
      await DbHelper.instance.logStudentScore(
        studentEmail: widget.studentEmail,
        quizId: widget.quiz['id']! as String,
        score: score.toDouble(),
        total: _questions.length.toDouble(),
      );
      if (!mounted) return;
      setState(() {
        _finished = true;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your score: $error')),
      );
    }
  }

  void _selectAnswer(String option) {
    setState(() => _answers[_questionIndex] = option);
    _persistProgressInBackground();
  }

  void _advanceQuestion() {
    setState(() => _questionIndex++);
    _persistProgressInBackground();
  }

  List<String> _optionsFor(Map<String, Object?> question) {
    final decoded = jsonDecode(question['options_json']! as String);
    if (decoded is! List || decoded.any((option) => option is! String)) {
      throw const FormatException('This question has invalid answer choices.');
    }
    return decoded.cast<String>();
  }

  Future<void> _explain(Map<String, Object?> question) async {
    final answer = question['answer']! as String;
    final selected = _answers[_questionIndex] ?? 'No answer selected';
    final prompt =
        '${question['prompt']}\n'
        'Answer choices: ${_optionsFor(question).join('; ')}\n'
        'Correct answer: $answer';
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _ExplanationDialog(question: prompt, attempt: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Practice exam')),
        body: Center(child: Text('Could not open this quiz: $_loadError')),
      );
    }
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Practice exam')),
        body: const Center(
          child: Text('This quiz does not contain any questions yet.'),
        ),
      );
    }
    if (_finished) return _resultView();

    final question = _questions[_questionIndex];
    final options = _optionsFor(question);
    final selected = _answers[_questionIndex];
    final correctAnswer = question['answer']! as String;
    final answered = selected != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quiz['title']! as String),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Text(
                '${_secondsRemaining ~/ 60}:'
                '${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LinearProgressIndicator(
              value: (_questionIndex + 1) / _questions.length,
            ),
            const SizedBox(height: 18),
            Text(
              'Question ${_questionIndex + 1} of ${_questions.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            Text(
              question['prompt']! as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            for (final option in options)
              Card(
                color: answered && option == correctAnswer
                    ? const Color(0xFFE6F5EA)
                    : answered && option == selected
                    ? const Color(0xFFFFE8E8)
                    : Colors.white,
                child: ListTile(
                  leading: Icon(
                    selected == option
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(option),
                  onTap: answered ? null : () => _selectAnswer(option),
                ),
              ),
            if (answered) ...[
              const SizedBox(height: 12),
              Text(
                selected == correctAnswer
                    ? 'Correct!'
                    : 'Not quite. The correct answer is $correctAnswer.',
                style: TextStyle(
                  color: selected == correctAnswer
                      ? Colors.green.shade800
                      : Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((question['explanation'] as String?)?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(question['explanation']! as String),
                ),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => _explain(question),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Explain question with AI'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving
                  ? null
                  : !answered
                  ? null
                  : _questionIndex == _questions.length - 1
                  ? _finish
                  : _advanceQuestion,
              child: _saving
                  ? const CircularProgressIndicator()
                  : Text(
                      _questionIndex == _questions.length - 1
                          ? 'Finish exam'
                          : 'Next question',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultView() {
    final score = _questions.indexed
        .where((entry) => _answers[entry.$1] == entry.$2['answer'])
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('Exam complete')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'Your score: $score / ${_questions.length}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Saved on this device. It will sync when online.'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to quizzes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExplanationDialog extends StatefulWidget {
  const _ExplanationDialog({required this.question, required this.attempt});

  final String question;
  final String attempt;

  @override
  State<_ExplanationDialog> createState() => _ExplanationDialogState();
}

class _ExplanationDialogState extends State<_ExplanationDialog> {
  late final Future<String> _explanation = AiService.instance
      .getQuestionExplanation(
        question: widget.question,
        studentAttempt: widget.attempt,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Step-by-step explanation'),
      content: SizedBox(
        width: 500,
        child: FutureBuilder<String>(
          future: _explanation,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not get an AI explanation: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(child: Text(snapshot.data!));
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
