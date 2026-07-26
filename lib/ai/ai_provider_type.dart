import '../core/config/env.dart';

/// The AI backends LifeOS can talk to.
///
/// Adding one is a three-step change: a value here, an [LlmClient]
/// implementation, and a line in the factory. Nothing in the feature layer ever
/// names a provider — see docs/AI_PIPELINE.md.
enum AiProviderType {
  /// On-device heuristics. No network, no key, no data leaving the phone.
  /// This is the default, and it is what every other provider falls back to.
  offline(
    id: 'offline',
    label: 'On-device (no AI service)',
    needsApiKey: false,
    supportsStreaming: false,
  ),
  openai(
    id: 'openai',
    label: 'OpenAI',
    needsApiKey: true,
    supportsStreaming: true,
  ),
  gemini(
    id: 'gemini',
    label: 'Google Gemini',
    needsApiKey: true,
    supportsStreaming: true,
  ),
  anthropic(
    id: 'anthropic',
    label: 'Anthropic Claude',
    needsApiKey: true,
    supportsStreaming: true,
  ),

  /// A local model server. Private like [offline], but actually capable.
  ollama(
    id: 'ollama',
    label: 'Ollama (local model)',
    needsApiKey: false,
    supportsStreaming: true,
  );

  const AiProviderType({
    required this.id,
    required this.label,
    required this.needsApiKey,
    required this.supportsStreaming,
  });

  final String id;
  final String label;
  final bool needsApiKey;
  final bool supportsStreaming;

  /// True when the user's personal data would leave the device.
  bool get isRemote => this != offline && this != ollama;

  String get defaultModel => switch (this) {
        AiProviderType.offline => 'heuristics',
        AiProviderType.openai => Env.openAiModel,
        AiProviderType.gemini => Env.geminiModel,
        AiProviderType.anthropic => Env.anthropicModel,
        AiProviderType.ollama => Env.ollamaModel,
      };

  /// Compile-time key, used only when the user has not entered their own.
  String get envApiKey => switch (this) {
        AiProviderType.openai => Env.openAiKey,
        AiProviderType.gemini => Env.geminiKey,
        AiProviderType.anthropic => Env.anthropicKey,
        AiProviderType.offline || AiProviderType.ollama => '',
      };

  static AiProviderType fromId(String id) => values.firstWhere(
        (provider) => provider.id == id,
        orElse: () => AiProviderType.offline,
      );
}
