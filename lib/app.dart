import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/strings.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_controller.dart';
import 'core/theme/app_theme.dart';

/// Root widget.
///
/// Deliberately thin: it wires theme, locale, accessibility overrides and the
/// router together and nothing else. All behaviour lives behind providers.
class LifeOsApp extends ConsumerWidget {
  const LifeOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings.useDynamicColor;
        return MaterialApp.router(
          title: 'LifeOS',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          themeMode: settings.themeMode,
          theme: AppTheme.light(
            dynamicScheme: useDynamic ? lightDynamic?.harmonized() : null,
            highContrast: settings.highContrast,
          ),
          darkTheme: AppTheme.dark(
            dynamicScheme: useDynamic ? darkDynamic?.harmonized() : null,
            highContrast: settings.highContrast,
          ),
          locale: settings.locale,
          supportedLocales: Strings.supported,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            StringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            // The user's in-app text-size preference multiplies the OS setting
            // instead of replacing it, so system accessibility settings are
            // always respected.
            final systemScaler = MediaQuery.textScalerOf(context);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: systemScaler.clamp(
                  minScaleFactor: 0.85,
                  maxScaleFactor: 2.0,
                ),
              ),
              child: _TextScaleOverlay(
                scale: settings.textScale,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

class _TextScaleOverlay extends StatelessWidget {
  const _TextScaleOverlay({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;
    final current = MediaQuery.textScalerOf(context).scale(14) / 14;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(current * scale),
      ),
      child: child,
    );
  }
}
