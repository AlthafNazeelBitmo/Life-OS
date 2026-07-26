/// Compile-time configuration.
///
/// Nothing secret is ever written into source. Values arrive through
/// `--dart-define` / `--dart-define-from-file` at build time, and anything the
/// user types at runtime (their own AI key, for example) goes to the platform
/// keychain via `SecureStore` — which takes precedence over these defaults.
///
/// Every field is optional. A completely unconfigured build still runs: it uses
/// the local-only account and the on-device heuristic AI provider.
abstract final class Env {
  const Env._();

  // --- Supabase ---------------------------------------------------------
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Cloud sync and remote auth are only wired up when both values are present.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // --- AI providers -----------------------------------------------------
  static const String openAiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const String openAiModel =
      String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-4o-mini');

  static const String geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.0-flash');

  static const String anthropicKey =
      String.fromEnvironment('ANTHROPIC_API_KEY');
  static const String anthropicModel = String.fromEnvironment(
    'ANTHROPIC_MODEL',
    defaultValue: 'claude-sonnet-5',
  );

  static const String ollamaBaseUrl = String.fromEnvironment(
    'OLLAMA_BASE_URL',
    defaultValue: 'http://localhost:11434',
  );
  static const String ollamaModel =
      String.fromEnvironment('OLLAMA_MODEL', defaultValue: 'llama3.2');

  /// One of `offline`, `openai`, `gemini`, `anthropic`, `ollama`.
  static const String defaultAiProvider =
      String.fromEnvironment('DEFAULT_AI_PROVIDER', defaultValue: 'offline');

  // --- Feature flags ----------------------------------------------------
  static const bool enableOcr =
      bool.fromEnvironment('ENABLE_OCR', defaultValue: false);

  static const bool isRelease = bool.fromEnvironment('dart.vm.product');
}
