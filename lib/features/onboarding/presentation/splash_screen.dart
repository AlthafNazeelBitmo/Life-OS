import 'package:flutter/material.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';

/// Shown only while the session is being restored.
///
/// Deliberately minimal: this must not become a branded delay. The router
/// leaves it the moment auth resolves, which offline is a single cache read.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackdrop(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('LifeOS', style: context.text.displaySmall),
                Gap.h24,
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
      );
}
