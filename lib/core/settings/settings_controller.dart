import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/key_value_store.dart';
import '../di/core_providers.dart';
import 'app_settings.dart';

/// Owns [AppSettings] and writes every change straight through to the cache.
///
/// Settings are read synchronously at startup so the very first frame already
/// has the right theme — no flash of the wrong brightness.
class SettingsController extends Notifier<AppSettings> {
  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  AppSettings build() {
    final json = ref.read(keyValueStoreProvider).getJson(CacheKeys.settings);
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }

  Future<void> _persist(AppSettings next) async {
    state = next;
    await _store.setJson(CacheKeys.settings, next.toJson());
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _persist(state.copyWith(themeMode: mode));

  Future<void> setDynamicColor({required bool enabled}) =>
      _persist(state.copyWith(useDynamicColor: enabled));

  Future<void> setHighContrast({required bool enabled}) =>
      _persist(state.copyWith(highContrast: enabled));

  Future<void> setTextScale(double scale) =>
      _persist(state.copyWith(textScale: scale.clamp(0.8, 1.6)));

  Future<void> setLocale(String code) =>
      _persist(state.copyWith(localeCode: code));

  Future<void> setAiProvider(String providerId, {String model = ''}) =>
      _persist(state.copyWith(aiProviderId: providerId, aiModel: model));

  Future<void> setAiEnabled({required bool enabled}) =>
      _persist(state.copyWith(aiEnabled: enabled));

  Future<void> setShareDataWithAi({required bool enabled}) =>
      _persist(state.copyWith(shareDataWithAi: enabled));

  Future<void> setBiometricLock({required bool enabled}) =>
      _persist(state.copyWith(biometricLock: enabled));

  Future<void> setNotificationsEnabled({required bool enabled}) =>
      _persist(state.copyWith(notificationsEnabled: enabled));

  Future<void> setSmartReminderTiming({required bool enabled}) =>
      _persist(state.copyWith(smartReminderTiming: enabled));

  Future<void> setDailyBriefingTime(TimeOfDay time) => _persist(
        state.copyWith(dailyBriefingMinutes: time.hour * 60 + time.minute),
      );

  Future<void> setEveningReflectionTime(TimeOfDay time) => _persist(
        state.copyWith(eveningReflectionMinutes: time.hour * 60 + time.minute),
      );

  Future<void> setCurrency(String code) =>
      _persist(state.copyWith(currency: code));

  Future<void> setWeekStartsMonday({required bool monday}) =>
      _persist(state.copyWith(weekStartsMonday: monday));

  Future<void> completeOnboarding() =>
      _persist(state.copyWith(onboardingComplete: true));

  Future<void> setCloudSync({required bool enabled}) =>
      _persist(state.copyWith(cloudSyncEnabled: enabled));

  Future<void> markSynced(DateTime at) =>
      _persist(state.copyWith(lastSyncAt: at));

  /// Used by "delete all local data" in Settings › Privacy.
  Future<void> reset() => _persist(const AppSettings());
}

final NotifierProvider<SettingsController, AppSettings> settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Narrow selectors — widgets watching these rebuild only when their own slice
/// changes, which keeps theme switches from rebuilding unrelated subtrees.
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider.select((s) => s.themeMode)),
);

final Provider<String> currencyProvider = Provider<String>(
  (ref) => ref.watch(settingsProvider.select((s) => s.currency)),
);
