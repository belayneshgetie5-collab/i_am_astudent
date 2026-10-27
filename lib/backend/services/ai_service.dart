import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:i_am_astudent/backend/constants/api_constants.dart';

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  static final AiService instance = AiService();
  final http.Client _client;

  Future<String> getQuestionExplanation({
    required String question,
    String? studentAttempt,
  }) async {
    final apiKey = ApiConstants.grokApiKey;
    if (apiKey.isEmpty) {
      throw StateError(
        'Grok is not configured. Provide SAAMEP_GROK_API_KEY at build time '
        'or call a secured backend proxy.',
      );
    }
    if (question.trim().isEmpty) {
      throw ArgumentError.value(question, 'question', 'Question is required.');
    }

    final attemptText = studentAttempt == null || studentAttempt.trim().isEmpty
        ? ''
        : '\nThe student tried: ${studentAttempt.trim()}';
    final response = await _client
        .post(
          Uri.parse(ApiConstants.grokApiUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': ApiConstants.grokModel,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are a patient exam-preparation tutor. Explain the '
                    'solution accurately in numbered steps, show the reasoning, '
                    'and finish with the answer.',
              },
              {
                'role': 'user',
                'content':
                    'Explain this question step by step:\n'
                    '${question.trim()}$attemptText',
              },
            ],
            'temperature': 0.2,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Grok request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Grok returned an invalid response.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Grok response did not include an answer.');
    }
    final choice = choices.first;
    final message = choice is Map<String, dynamic> ? choice['message'] : null;
    final content = message is Map<String, dynamic> ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Grok returned an empty explanation.');
    }
    return content.trim();
  }

  void dispose() => _client.close();
}
