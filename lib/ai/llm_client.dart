import 'models/llm.dart';

/// The narrow seam every AI backend implements.
///
/// This is intentionally the *only* provider-shaped abstraction in LifeOS.
/// Everything above it — prompts, grounding, parsing, retries — is written once
/// against this interface, so adding a provider never touches feature code.
abstract interface class LlmClient {
  /// Stable identifier matching `AiProviderType.id`.
  String get providerId;

  /// Model actually in use, for provenance badges in the UI.
  String get model;

  Future<LlmCompletion> complete(LlmRequest request);

  /// Token-by-token output. Providers that cannot stream fall back to emitting
  /// the whole completion as a single chunk, so callers never branch on it.
  Stream<String> stream(LlmRequest request);

  /// Cheap reachability probe used by Settings to show a live status dot.
  Future<bool> ping();
}

/// Shared plumbing for the HTTP-backed clients.
mixin LlmHttpErrors {
  /// Maps a transport/status failure onto a message worth showing a user.
  ///
  /// The distinction that matters is retryable vs not: a 429 or a 503 means
  /// "try again", a 401 means "your key is wrong" and retrying is pointless.
  String describeStatus(int status, String body) => switch (status) {
        401 || 403 => 'That API key was rejected. Check it in Settings › AI.',
        404 => 'That model is not available on your account.',
        413 => 'That request was too large. Try a shorter time range.',
        429 => 'Rate limit reached. Give it a moment and try again.',
        >= 500 => 'The AI service is having trouble. Try again shortly.',
        _ => 'The AI service returned an error ($status).',
      };

  bool isRetryable(int status) => status == 429 || status >= 500;
}
