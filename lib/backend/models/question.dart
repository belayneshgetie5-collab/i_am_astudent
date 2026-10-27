import 'dart:convert';

class Question {
  const Question({
    required this.id,
    required this.quizId,
    required this.prompt,
    required this.options,
    required this.answer,
    this.explanation,
  });

  final String id;
  final String quizId;
  final String prompt;
  final List<String> options;
  final String answer;
  final String? explanation;

  factory Question.fromMap(Map<String, Object?> map) {
    final rawOptions = map['options_json'] ?? map['options'];
    final options = rawOptions is String ? jsonDecode(rawOptions) : rawOptions;
    if (options is! List || options.any((option) => option is! String)) {
      throw const FormatException(
        'Question options must be a list of strings.',
      );
    }
    return Question(
      id: map['id']! as String,
      quizId: map['quiz_id']! as String,
      prompt: map['prompt']! as String,
      options: options.cast<String>(),
      answer: map['answer']! as String,
      explanation: map['explanation'] as String?,
    );
  }

  Map<String, Object?> toMap({bool isSynced = false}) => {
    'id': id,
    'quiz_id': quizId,
    'prompt': prompt,
    'options_json': jsonEncode(options),
    'answer': answer,
    'explanation': explanation,
    'is_synced': isSynced ? 1 : 0,
  };
}
