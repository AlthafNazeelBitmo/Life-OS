import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../core/di/core_providers.dart';
import '../core/security/secure_store.dart';
import '../core/settings/settings_controller.dart';
import '../data/repositories/repository_providers.dart';
import 'ai_provider_type.dart';
import 'ai_service.dart';
import 'clients/anthropic_client.dart';
import 'clients/gemini_client.dart';
import 'clients/ollama_client.dart';
import 'clients/openai_client.dart';
import 'context/context_builder.dart';
import 'default_ai_service.dart';
import 'llm_client.dart';
import 'offline_ai_service.dart';

/// Wiring for the AI layer.
///
/// The whole point of the abstraction lands here: changing provider is one
/// settings write, and every screen picks it up because they all watch
/// [aiServiceProvider] rather than constructing anything themselves.

final Provider<http.Client> httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final Provider<AiProviderType> aiProviderTypeProvider = Provider<AiProviderType>(
  (ref) => AiProviderType.fromId(
    ref.watch(settingsProvider.select((s) => s.aiProviderId)),
  ),
);

/// Resolves the API key for a provider.
///
/// The user's own key (platform keychain) always wins over the compile-time
/// default, so a shipped build with no key baked in is still fully usable by
/// someone who brings their own.
final FutureProviderFamily<String, AiProviderType> aiApiKeyProvider =
    FutureProvider.family<String, AiProviderType>((ref, provider) async {
  if (!provider.needsApiKey) return '';
  final stored =
      await ref.watch(secureStoreProvider).read(SecureKeys.aiKey(provider.id));
  if (stored != null && stored.isNotEmpty) return stored;
  return provider.envApiKey;
});

/// Builds the low-level client for the selected provider, or null when the app
/// should stay on the on-device path.
final FutureProvider<LlmClient?> llmClientProvider =
    FutureProvider<LlmClient?>((ref) async {
  final settings = ref.watch(settingsProvider);
  final provider = ref.watch(aiProviderTypeProvider);

  // Three separate ways the user can say "no": AI off entirely, data sharing
  // off, or the offline provider selected. All of them land here.
  if (!settings.aiEnabled ||
      provider == AiProviderType.offline ||
      (provider.isRemote && !settings.shareDataWithAi)) {
    return null;
  }

  final key = await ref.watch(aiApiKeyProvider(provider).future);
  if (provider.needsApiKey && key.isEmpty) return null;

  final model =
      settings.aiModel.isEmpty ? provider.defaultModel : settings.aiModel;
  final http = ref.watch(httpClientProvider);

  return switch (provider) {
    AiProviderType.openai =>
      OpenAiClient(apiKey: key, model: model, httpClient: http),
    AiProviderType.gemini =>
      GeminiClient(apiKey: key, model: model, httpClient: http),
    AiProviderType.anthropic =>
      AnthropicClient(apiKey: key, model: model, httpClient: http),
    AiProviderType.ollama =>
      OllamaClient(model: model, baseUrl: Env.ollamaBaseUrl, httpClient: http),
    AiProviderType.offline => null,
  };
});

const OfflineAiService _offlineService = OfflineAiService();

/// The service every feature depends on.
///
/// Synchronous by design: a screen must never wait on key lookup to render, so
/// while the client resolves — and forever, if none is configured — this hands
/// back the on-device implementation.
final Provider<AIService> aiServiceProvider = Provider<AIService>((ref) {
  final client = ref.watch(llmClientProvider).valueOrNull;
  if (client == null) return _offlineService;
  return DefaultAiService(client, fallback: _offlineService);
});

/// Whether the assistant is currently model-backed, for UI badges.
final Provider<bool> aiIsLiveProvider = Provider<bool>(
  (ref) => ref.watch(aiServiceProvider).providerId != 'offline',
);

final Provider<ContextBuilder> contextBuilderProvider = Provider<ContextBuilder>(
  (ref) => ContextBuilder(
    journal: ref.watch(journalRepositoryProvider),
    mood: ref.watch(moodRepositoryProvider),
    habits: ref.watch(habitRepositoryProvider),
    goals: ref.watch(goalRepositoryProvider),
    tasks: ref.watch(taskRepositoryProvider),
    calendar: ref.watch(calendarRepositoryProvider),
    finance: ref.watch(financeRepositoryProvider),
    health: ref.watch(healthRepositoryProvider),
    search: ref.watch(searchRepositoryProvider),
  ),
);

/// Live reachability of the configured provider, for the status dot in
/// Settings › AI.
final FutureProvider<bool> aiHealthProvider = FutureProvider<bool>((ref) async {
  final client = await ref.watch(llmClientProvider.future);
  if (client == null) return true; // on-device is always available
  return client.ping();
});
