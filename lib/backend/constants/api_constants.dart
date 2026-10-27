abstract final class ApiConstants {
  static const apiBaseUrl = String.fromEnvironment('SAAMEP_API_BASE_URL');
  static const supportEmail = String.fromEnvironment(
    'SAAMEP_SUPPORT_EMAIL',
    defaultValue: '',
  );
  static const grokApiUrl = String.fromEnvironment(
    'SAAMEP_GROK_API_URL',
    defaultValue: 'https://api.x.ai/v1/chat/completions',
  );
  static const grokApiKey = String.fromEnvironment('SAAMEP_GROK_API_KEY');
  static const grokModel = String.fromEnvironment(
    'SAAMEP_GROK_MODEL',
    defaultValue: 'grok-3-mini',
  );
}
