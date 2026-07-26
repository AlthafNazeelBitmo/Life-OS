import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../application/auth_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(authControllerProvider.notifier)
        .signInWithEmail(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isLoading;

    // Errors surface as a snackbar rather than inline: the failure is almost
    // always about the whole attempt, not one field.
    ref.listen(authControllerProvider, (previous, next) {
      final error = next.error;
      if (error != null) context.showError(error.toString());
    });

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'LifeOS',
                      style: context.text.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                    Gap.h8,
                    Text(
                      'Your life, in one place.',
                      style: context.text.bodyLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Gap.h32,
                    GlassCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const <String>[AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                              ),
                              validator: (value) =>
                                  (value ?? '').contains('@')
                                      ? null
                                      : 'Enter a valid email',
                            ),
                            Gap.h12,
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              autofillHints: const <String>[
                                AutofillHints.password,
                              ],
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? 'Show' : 'Hide',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) => (value ?? '').length >= 8
                                  ? null
                                  : 'At least 8 characters',
                            ),
                            Gap.h16,
                            FilledButton(
                              onPressed: busy ? null : _submit,
                              child: busy
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Sign in'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Gap.h16,
                    if (Env.hasSupabase) ...<Widget>[
                      const _OrDivider(),
                      Gap.h16,
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : ref
                                .read(authControllerProvider.notifier)
                                .signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                        label: const Text('Continue with Google'),
                      ),
                      if (Platform.isIOS || Platform.isMacOS) ...<Widget>[
                        Gap.h8,
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : ref
                                  .read(authControllerProvider.notifier)
                                  .signInWithApple,
                          icon: const Icon(Icons.apple_rounded),
                          label: const Text('Continue with Apple'),
                        ),
                      ],
                    ],
                    Gap.h16,
                    TextButton(
                      onPressed: () => context.go(Routes.signUp),
                      child: const Text('Create an account'),
                    ),
                    // The local account is what makes LifeOS usable with no
                    // backend at all, so it is offered as a peer, not hidden.
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => ref
                              .read(authControllerProvider.notifier)
                              .continueLocally(),
                      icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                      label: const Text('Use on this device only'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(
              'or',
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      );
}
