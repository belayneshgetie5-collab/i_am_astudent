import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:i_am_astudent/database/db_helper.dart';

class CreateQuizScreen extends StatefulWidget {
  const CreateQuizScreen({required this.teacherEmail, super.key});

  final String teacherEmail;

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  late Future<List<Map<String, Object?>>> _quizzes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => _quizzes = DbHelper.instance.getQuizzes();

  Future<void> _createQuiz() async {
    final form = await showDialog<_QuizDraft>(
      context: context,
      builder: (context) => const _QuizFormDialog(),
    );
    if (form == null || !mounted) return;
    try {
      final quizId = DateTime.now().microsecondsSinceEpoch.toString();
      await DbHelper.instance.createQuizWithQuestion(
        id: quizId,
        title: form.title,
        description: form.description,
        createdBy: widget.teacherEmail,
        question: {
          'id': '$quizId-question-1',
          'prompt': form.prompt,
          'options': form.options,
          'answer': form.answer,
          'explanation': form.explanation,
        },
      );
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create quiz: $error')));
    }
  }

  Future<void> _editQuiz(Map<String, Object?> quiz) async {
    final form = await showDialog<_QuizDraft>(
      context: context,
      builder: (context) => _QuizFormDialog(existingQuiz: quiz),
    );
    if (form == null || !mounted) return;
    try {
      await DbHelper.instance.updateQuiz(quiz['id']! as String, {
        'title': form.title,
        'description': form.description,
      });
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update quiz: $error')));
    }
  }

  Future<void> _deleteQuiz(Map<String, Object?> quiz) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quiz?'),
        content: Text('Delete "${quiz['title']}" and its questions?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await DbHelper.instance.deleteQuiz(quiz['id']! as String);
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete quiz: $error')));
    }
  }

  Future<void> _openQuiz(Map<String, Object?> quiz) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => QuizQuestionEditor(quiz: quiz)),
    );
    if (mounted) setState(_refresh);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createQuiz,
        icon: const Icon(Icons.add),
        label: const Text('Create quiz'),
      ),
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
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Create your first practice quiz.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final quiz = snapshot.data![index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.quiz_outlined)),
                  title: Text(quiz['title']! as String),
                  subtitle: Text(
                    (quiz['description'] as String?) ?? 'No description',
                  ),
                  onTap: () => _openQuiz(quiz),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'edit') _editQuiz(quiz);
                      if (action == 'delete') _deleteQuiz(quiz);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit details')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete quiz'),
                      ),
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

class _QuizDraft {
  const _QuizDraft({
    required this.title,
    required this.description,
    required this.prompt,
    required this.options,
    required this.answer,
    required this.explanation,
  });

  final String title;
  final String description;
  final String prompt;
  final List<String> options;
  final String answer;
  final String explanation;
}

class _QuizFormDialog extends StatefulWidget {
  const _QuizFormDialog({this.existingQuiz});

  final Map<String, Object?>? existingQuiz;

  @override
  State<_QuizFormDialog> createState() => _QuizFormDialogState();
}

class _QuizFormDialogState extends State<_QuizFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _prompt;
  late final TextEditingController _options;
  late final TextEditingController _answer;
  late final TextEditingController _explanation;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.existingQuiz?['title'] as String? ?? '',
    );
    _description = TextEditingController(
      text: widget.existingQuiz?['description'] as String? ?? '',
    );
    _prompt = TextEditingController();
    _options = TextEditingController();
    _answer = TextEditingController();
    _explanation = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _prompt.dispose();
    _options.dispose();
    _answer.dispose();
    _explanation.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value?.trim().isNotEmpty ?? false ? null : 'This field is required.';

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final options = _options.text
        .split('\n')
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toList();
    if (widget.existingQuiz == null &&
        (options.length < 2 || !options.contains(_answer.text.trim()))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least two answer choices and enter the correct choice '
            'exactly as written.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _QuizDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        prompt: _prompt.text.trim(),
        options: options,
        answer: _answer.text.trim(),
        explanation: _explanation.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingQuiz != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit quiz details' : 'Create a practice quiz'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Quiz title'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _description,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                if (!isEditing) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _prompt,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Question'),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _options,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Answer choices (one per line)',
                    ),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _answer,
                    decoration: const InputDecoration(
                      labelText: 'Correct answer (exact choice)',
                    ),
                    validator: _required,
                  ),
                  TextFormField(
                    controller: _explanation,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Answer explanation (optional)',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class QuizQuestionEditor extends StatefulWidget {
  const QuizQuestionEditor({required this.quiz, super.key});

  final Map<String, Object?> quiz;

  @override
  State<QuizQuestionEditor> createState() => _QuizQuestionEditorState();
}

class _QuizQuestionEditorState extends State<QuizQuestionEditor> {
  late Future<List<Map<String, Object?>>> _questions;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _questions = DbHelper.instance.getCachedQuestions(
      widget.quiz['id']! as String,
    );
  }

  Future<void> _addQuestion() async {
    final draft = await showDialog<_QuestionDraft>(
      context: context,
      builder: (context) => const _QuestionFormDialog(),
    );
    if (draft == null || !mounted) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      await DbHelper.instance.createQuestion({
        'id': id,
        'quiz_id': widget.quiz['id'],
        'prompt': draft.prompt,
        'options': draft.options,
        'answer': draft.answer,
        'explanation': draft.explanation,
      });
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add question: $error')));
    }
  }

  Future<void> _deleteQuestion(String id) async {
    try {
      await DbHelper.instance.deleteQuestion(id);
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete question: $error')),
      );
    }
  }

  Future<void> _editQuestion(Map<String, Object?> question) async {
    final draft = await showDialog<_QuestionDraft>(
      context: context,
      builder: (context) => _QuestionFormDialog(question: question),
    );
    if (draft == null || !mounted) return;
    try {
      await DbHelper.instance.updateQuestion(question['id']! as String, {
        'prompt': draft.prompt,
        'options_json': jsonEncode(draft.options),
        'answer': draft.answer,
        'explanation': draft.explanation,
      });
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update question: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.quiz['title']! as String)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuestion,
        icon: const Icon(Icons.add),
        label: const Text('Add question'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _questions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load questions: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final question = snapshot.data![index];
              final options = (jsonDecode(
                question['options_json']! as String,
              ) as List).cast<String>();
              return Card(
                child: ExpansionTile(
                  title: Text(question['prompt']! as String),
                  subtitle: Text('${options.length} choices'),
                  children: [
                    for (final option in options)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          option == question['answer']
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                        ),
                        title: Text(option),
                      ),
                    if ((question['explanation'] as String?)?.isNotEmpty ??
                        false)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(question['explanation']! as String),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        children: [
                          TextButton.icon(
                            onPressed: () => _editQuestion(question),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit question'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _deleteQuestion(question['id']! as String),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove question'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _QuestionDraft {
  const _QuestionDraft({
    required this.prompt,
    required this.options,
    required this.answer,
    required this.explanation,
  });

  final String prompt;
  final List<String> options;
  final String answer;
  final String explanation;
}

class _QuestionFormDialog extends StatefulWidget {
  const _QuestionFormDialog({this.question});

  final Map<String, Object?>? question;

  @override
  State<_QuestionFormDialog> createState() => _QuestionFormDialogState();
}

class _QuestionFormDialogState extends State<_QuestionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _prompt;
  late final TextEditingController _options;
  late final TextEditingController _answer;
  late final TextEditingController _explanation;

  @override
  void initState() {
    super.initState();
    final question = widget.question;
    final choices = question == null
        ? const <String>[]
        : (jsonDecode(question['options_json']! as String) as List)
              .cast<String>();
    _prompt = TextEditingController(text: question?['prompt'] as String? ?? '');
    _options = TextEditingController(text: choices.join('\n'));
    _answer = TextEditingController(text: question?['answer'] as String? ?? '');
    _explanation = TextEditingController(
      text: question?['explanation'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _prompt.dispose();
    _options.dispose();
    _answer.dispose();
    _explanation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.question == null ? 'Add question' : 'Edit question'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _prompt,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Question'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _options,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Answer choices (one per line)',
                  ),
                  validator: _required,
                ),
                TextFormField(
                  controller: _answer,
                  decoration: const InputDecoration(
                    labelText: 'Correct answer (exact choice)',
                  ),
                  validator: _required,
                ),
                TextFormField(
                  controller: _explanation,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Explanation (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final options = _options.text
                .split('\n')
                .map((option) => option.trim())
                .where((option) => option.isNotEmpty)
                .toList();
            if (options.length < 2 || !options.contains(_answer.text.trim())) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Add at least two choices and select a valid '
                    'correct answer.',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _QuestionDraft(
                prompt: _prompt.text.trim(),
                options: options,
                answer: _answer.text.trim(),
                explanation: _explanation.text.trim(),
              ),
            );
          },
          child: const Text('Save question'),
        ),
      ],
    );
  }
}

String? _required(String? value) =>
    value?.trim().isNotEmpty ?? false ? null : 'This field is required.';
