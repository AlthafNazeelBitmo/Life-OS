import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/ai_provider_type.dart';
import 'package:lifeos/ai/ai_providers.dart';
import 'package:lifeos/core/cache/key_value_store.dart';
import 'package:lifeos/core/di/core_providers.dart';
import 'package:lifeos/core/security/secure_store.dart';
import 'package:lifeos/core/settings/settings_controller.dart';

/// A container with the two I/O providers replaced by in-memory fakes. This is
/// the whole point of declaring them as overridable providers: a test gets a
/// fully wired settings stack in three lines.
ProviderContainer testContainer({KeyValueStore? cache, SecureStore? secure}) {
  final container = ProviderContainer(
    overrides: <Override>[
      keyValueStoreProvider.overrideWithValue(cache ?? InMemoryKeyValueStore()),
      secureStoreProvider.overrideWithValue(secure ?? InMemorySecureStore()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SettingsController', () {
    test('starts from defaults when the cache is empty', () {
      final container = testContainer();
      final settings = container.read(settingsProvider);

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.aiProviderId, 'offline');
      expect(settings.onboardingComplete, isFalse);
      expect(settings.currency, 'USD');
    });

    test('persists changes through the cache', () async {
      final cache = InMemoryKeyValueStore();
      final container = testContainer(cache: cache);

      await container
          .read(settingsProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await container.read(settingsProvider.notifier).setCurrency('EUR');

      // A fresh container reading the same cache must see the same settings.
      final reopened = testContainer(cache: cache);
      final settings = reopened.read(settingsProvider);

      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.currency, 'EUR');
    });

    test('clamps the text scale to a legible range', () async {
      final container = testContainer();
      final controller = container.read(settingsProvider.notifier);

      await controller.setTextScale(4);
      expect(container.read(settingsProvider).textScale, 1.6);

      await controller.setTextScale(0.1);
      expect(container.read(settingsProvider).textScale, 0.8);
    });

    test('reset returns everything to defaults', () async {
      final container = testContainer();
      final controller = container.read(settingsProvider.notifier);

      await controller.setBiometricLock(enabled: true);
      await controller.completeOnboarding();
      await controller.reset();

      expect(container.read(settingsProvider).biometricLock, isFalse);
      expect(container.read(settingsProvider).onboardingComplete, isFalse);
    });
  });

  group('AI provider selection', () {
    test('defaults to the on-device service with no key configured', () async {
      final container = testContainer();
      final service = container.read(aiServiceProvider);

      expect(service.providerId, 'offline');
      expect(service.isRemote, isFalse);
      expect(container.read(aiIsLiveProvider), isFalse);
    });

    test('stays on-device when the user opts out of sharing data', () async {
      final secure = InMemorySecureStore();
      await secure.write(SecureKeys.aiKey('openai'), 'sk-test');
      final container = testContainer(secure: secure);

      await container
          .read(settingsProvider.notifier)
          .setAiProvider(AiProviderType.openai.id);
      await container
          .read(settingsProvider.notifier)
          .setShareDataWithAi(enabled: false);

      // A saved key must not override an explicit privacy choice.
      final client = await container.read(llmClientProvider.future);
      expect(client, isNull);
      expect(container.read(aiServiceProvider).providerId, 'offline');
    });

    test('stays on-device when the assistant is switched off', () async {
      final secure = InMemorySecureStore();
      await secure.write(SecureKeys.aiKey('openai'), 'sk-test');
      final container = testContainer(secure: secure);

      await container
          .read(settingsProvider.notifier)
          .setAiProvider(AiProviderType.openai.id);
      await container.read(settingsProvider.notifier).setAiEnabled(enabled: false);

      expect(await container.read(llmClientProvider.future), isNull);
    });

    test('builds a client once a key is stored and sharing is allowed',
        () async {
      final secure = InMemorySecureStore();
      await secure.write(SecureKeys.aiKey('openai'), 'sk-test');
      final container = testContainer(secure: secure);

      await container
          .read(settingsProvider.notifier)
          .setAiProvider(AiProviderType.openai.id);

      final client = await container.read(llmClientProvider.future);
      expect(client, isNotNull);
      expect(client!.providerId, 'openai');
      expect(container.read(aiServiceProvider).isRemote, isTrue);
    });

    test('ollama needs no key and is reported as non-remote', () async {
      final container = testContainer();
      await container
          .read(settingsProvider.notifier)
          .setAiProvider(AiProviderType.ollama.id);

      final client = await container.read(llmClientProvider.future);
      expect(client?.providerId, 'ollama');
      expect(container.read(aiServiceProvider).isRemote, isFalse);
    });
  });

  group('AiProviderType', () {
    test('unknown ids fall back to the safe default', () {
      expect(AiProviderType.fromId('does-not-exist'), AiProviderType.offline);
    });

    test('classifies which providers send data off the device', () {
      expect(AiProviderType.offline.isRemote, isFalse);
      expect(AiProviderType.ollama.isRemote, isFalse);
      expect(AiProviderType.openai.isRemote, isTrue);
      expect(AiProviderType.anthropic.isRemote, isTrue);
      expect(AiProviderType.gemini.isRemote, isTrue);
    });
  });
}
