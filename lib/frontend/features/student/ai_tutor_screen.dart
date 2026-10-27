import 'package:flutter/material.dart';

import 'package:i_am_astudent/backend/services/ai_service.dart';

class AiTutorScreen extends StatefulWidget {
  const AiTutorScreen({super.key});

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen> {
  late final TextEditingController _questionController;
  late final TextEditingController _attemptController;
  Future<String>? _answer;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController();
    _attemptController = TextEditingController();
  }

  @override
  void dispose() {
    _questionController.dispose();
    _attemptController.dispose();
    super.dispose();
  }

  void _ask() {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a question for the tutor.')),
      );
      return;
    }
    setState(() {
      _answer = AiService.instance.getQuestionExplanation(
        question: question,
        studentAttempt: _attemptController.text,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI tutor')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Ask about a practice question or topic. The AI tutor needs an '
            'internet connection.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _questionController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Question or topic',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _attemptController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Your attempt (optional)',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _ask,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Explain step by step'),
          ),
          if (_answer case final answer?) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: FutureBuilder<String>(
                  future: answer,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        'Could not get an explanation: ${snapshot.error}',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return SelectableText(snapshot.data!);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
