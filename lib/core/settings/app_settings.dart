import 'package:flutter/material.dart';

/// Everything the user can change in Settings.
///
/// Hand-serialised rather than code-generated: settings are read during
/// `main()` before any generated code is guaranteed to exist, and keeping the
/// class dependency-free makes it trivial to unit test.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = true,
    this.highContrast = false,
    this.textScale = 1.0,
    this.localeCode = 'en',
    this.aiProviderId = 'offline',
    this.aiModel = '',
    this.aiEnabled = true,
    this.shareDataWithAi = true,
    this.biometricLock = false,
    this.notificationsEnabled = true,
    this.smartReminderTiming = true,
    this.dailyBriefingMinutes = 7 * 60 + 30,
    this.eveningReflectionMinutes = 21 * 60,
    this.currency = 'USD',
    this.weekStartsMonday = true,
    this.onboardingComplete = false,
    this.cloudSyncEnabled = true,
    this.lastSyncAt,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        useDynamicColor: json['useDynamicColor'] as bool? ?? true,
        highContrast: json['highContrast'] as bool? ?? false,
        textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
        localeCode: json['localeCode'] as String? ?? 'en',
        aiProviderId: json['aiProviderId'] as String? ?? 'offline',
        aiModel: json['aiModel'] as String? ?? '',
        aiEnabled: json['aiEnabled'] as bool? ?? true,
        shareDataWithAi: json['shareDataWithAi'] as bool? ?? true,
        biometricLock: json['biometricLock'] as bool? ?? false,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        smartReminderTiming: json['smartReminderTiming'] as bool? ?? true,
        dailyBriefingMinutes: json['dailyBriefingMinutes'] as int? ?? 450,
        eveningReflectionMinutes: json['eveningReflectionMinutes'] as int? ?? 1260,
        currency: json['currency'] as String? ?? 'USD',
        weekStartsMonday: json['weekStartsMonday'] as bool? ?? true,
        onboardingComplete: json['onboardingComplete'] as bool? ?? false,
        cloudSyncEnabled: json['cloudSyncEnabled'] as bool? ?? true,
        lastSyncAt: json['lastSyncAt'] == null
            ? null
            : DateTime.tryParse(json['lastSyncAt'] as String),
      );

  final ThemeMode themeMode;
  final bool useDynamicColor;
  final bool highContrast;

  /// Extra scaling applied on top of the OS text size, 0.8–1.6.
  final double textScale;
  final String localeCode;

  /// `offline`, `openai`, `gemini`, `anthropic` or `ollama`.
  final String aiProviderId;

  /// Empty means "use the provider's default model".
  final String aiModel;
  final bool aiEnabled;

  /// When false the assistant is limited to on-device summaries — no personal
  /// data ever leaves the device.
  final bool shareDataWithAi;
  final bool biometricLock;
  final bool notificationsEnabled;

  /// Let the AI move reminders to the time the user is most likely to act.
  final bool smartReminderTiming;

  /// Minutes past midnight.
  final int dailyBriefingMinutes;
  final int eveningReflectionMinutes;
  final String currency;
  final bool weekStartsMonday;
  final bool onboardingComplete;
  final bool cloudSyncEnabled;
  final DateTime? lastSyncAt;

  TimeOfDay get dailyBriefingTime => TimeOfDay(
        hour: dailyBriefingMinutes ~/ 60,
        minute: dailyBriefingMinutes % 60,
      );

  TimeOfDay get eveningReflectionTime => TimeOfDay(
        hour: eveningReflectionMinutes ~/ 60,
        minute: eveningReflectionMinutes % 60,
      );

  Locale get locale => Locale(localeCode);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'themeMode': themeMode.name,
        'useDynamicColor': useDynamicColor,
        'highContrast': highContrast,
        'textScale': textScale,
        'localeCode': localeCode,
        'aiProviderId': aiProviderId,
        'aiModel': aiModel,
        'aiEnabled': aiEnabled,
        'shareDataWithAi': shareDataWithAi,
        'biometricLock': biometricLock,
        'notificationsEnabled': notificationsEnabled,
        'smartReminderTiming': smartReminderTiming,
        'dailyBriefingMinutes': dailyBriefingMinutes,
        'eveningReflectionMinutes': eveningReflectionMinutes,
        'currency': currency,
        'weekStartsMonday': weekStartsMonday,
        'onboardingComplete': onboardingComplete,
        'cloudSyncEnabled': cloudSyncEnabled,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      };

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? useDynamicColor,
    bool? highContrast,
    double? textScale,
    String? localeCode,
    String? aiProviderId,
    String? aiModel,
    bool? aiEnabled,
    bool? shareDataWithAi,
    bool? biometricLock,
    bool? notificationsEnabled,
    bool? smartReminderTiming,
    int? dailyBriefingMinutes,
    int? eveningReflectionMinutes,
    String? currency,
    bool? weekStartsMonday,
    bool? onboardingComplete,
    bool? cloudSyncEnabled,
    DateTime? lastSyncAt,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        useDynamicColor: useDynamicColor ?? this.useDynamicColor,
        highContrast: highContrast ?? this.highContrast,
        textScale: textScale ?? this.textScale,
        localeCode: localeCode ?? this.localeCode,
        aiProviderId: aiProviderId ?? this.aiProviderId,
        aiModel: aiModel ?? this.aiModel,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        shareDataWithAi: shareDataWithAi ?? this.shareDataWithAi,
        biometricLock: biometricLock ?? this.biometricLock,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        smartReminderTiming: smartReminderTiming ?? this.smartReminderTiming,
        dailyBriefingMinutes: dailyBriefingMinutes ?? this.dailyBriefingMinutes,
        eveningReflectionMinutes:
            eveningReflectionMinutes ?? this.eveningReflectionMinutes,
        currency: currency ?? this.currency,
        weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettings &&
          other.themeMode == themeMode &&
          other.useDynamicColor == useDynamicColor &&
          other.highContrast == highContrast &&
          other.textScale == textScale &&
          other.localeCode == localeCode &&
          other.aiProviderId == aiProviderId &&
          other.aiModel == aiModel &&
          other.aiEnabled == aiEnabled &&
          other.shareDataWithAi == shareDataWithAi &&
          other.biometricLock == biometricLock &&
          other.notificationsEnabled == notificationsEnabled &&
          other.smartReminderTiming == smartReminderTiming &&
          other.dailyBriefingMinutes == dailyBriefingMinutes &&
          other.eveningReflectionMinutes == eveningReflectionMinutes &&
          other.currency == currency &&
          other.weekStartsMonday == weekStartsMonday &&
          other.onboardingComplete == onboardingComplete &&
          other.cloudSyncEnabled == cloudSyncEnabled &&
          other.lastSyncAt == lastSyncAt);

  @override
  int get hashCode => Object.hashAll(<Object?>[
        themeMode,
        useDynamicColor,
        highContrast,
        textScale,
        localeCode,
        aiProviderId,
        aiModel,
        aiEnabled,
        shareDataWithAi,
        biometricLock,
        notificationsEnabled,
        smartReminderTiming,
        dailyBriefingMinutes,
        eveningReflectionMinutes,
        currency,
        weekStartsMonday,
        onboardingComplete,
        cloudSyncEnabled,
        lastSyncAt,
      ]);
}
