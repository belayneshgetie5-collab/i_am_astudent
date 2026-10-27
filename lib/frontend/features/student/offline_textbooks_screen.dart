import 'package:flutter/material.dart';

import 'package:i_am_astudent/database/db_helper.dart';

class OfflineTextbooksScreen extends StatefulWidget {
  const OfflineTextbooksScreen({required this.role, super.key});

  final String role;

  @override
  State<OfflineTextbooksScreen> createState() => _OfflineTextbooksScreenState();
}

class _OfflineTextbooksScreenState extends State<OfflineTextbooksScreen> {
  late Future<List<Map<String, Object?>>> _textbooks;

  bool get _canManage => widget.role == 'teacher' || widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _textbooks = DbHelper.instance.getTextbooks();
  }

  Future<void> _addTextbook() async {
    final draft = await showDialog<_TextbookDraft>(
      context: context,
      builder: (context) => const _TextbookFormDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      await DbHelper.instance.saveTextbook(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: draft.title,
        content: draft.content,
      );
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Study topic saved on this device.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save study topic: $error')),
      );
    }
  }

  Future<void> _deleteTextbook(Map<String, Object?> textbook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove study topic?'),
        content: Text('Remove "${textbook['title']}" from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DbHelper.instance.deleteTextbook(textbook['id']! as String);
      if (mounted) setState(_refresh);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove study topic: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline textbooks')),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _addTextbook,
              icon: const Icon(Icons.add),
              label: const Text('Add topic'),
            )
          : null,
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _textbooks,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load study topics: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final textbooks = snapshot.data!;
          if (textbooks.isEmpty) {
            return const Center(
              child: Text('No study topics are saved on this device yet.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: textbooks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final textbook = textbooks[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.menu_book_outlined),
                  ),
                  title: Text(textbook['title']! as String),
                  subtitle: const Text('Available offline'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _TopicViewer(
                        title: textbook['title']! as String,
                        content: textbook['content']! as String,
                      ),
                    ),
                  ),
                  trailing: _canManage
                      ? IconButton(
                          tooltip: 'Remove topic',
                          onPressed: () => _deleteTextbook(textbook),
                          icon: const Icon(Icons.delete_outline),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TextbookDraft {
  const _TextbookDraft({required this.title, required this.content});

  final String title;
  final String content;
}

class _TextbookFormDialog extends StatefulWidget {
  const _TextbookFormDialog();

  @override
  State<_TextbookFormDialog> createState() => _TextbookFormDialogState();
}

class _TextbookFormDialogState extends State<_TextbookFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add offline study topic'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Topic title'),
                validator: (value) =>
                    value?.trim().isNotEmpty ?? false ? null : 'Enter a title.',
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contentController,
                minLines: 5,
                maxLines: 10,
                maxLength: 12000,
                decoration: const InputDecoration(
                  labelText: 'Study text',
                  alignLabelWithHint: true,
                ),
                validator: (value) => value?.trim().isNotEmpty ?? false
                    ? null
                    : 'Enter study content.',
              ),
            ],
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
            Navigator.pop(
              context,
              _TextbookDraft(
                title: _titleController.text.trim(),
                content: _contentController.text.trim(),
              ),
            );
          },
          child: const Text('Save offline'),
        ),
      ],
    );
  }
}

class _TopicViewer extends StatelessWidget {
  const _TopicViewer({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final paragraphs = content.split('\n\n');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: paragraphs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final paragraph = paragraphs[index].trim();
          if (paragraph.isEmpty) return const SizedBox.shrink();
          final isHeading = index == 0 || paragraph.length < 60;
          return SelectableText(
            paragraph,
            style: isHeading
                ? Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                : Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
          );
        },
      ),
    );
  }
}
