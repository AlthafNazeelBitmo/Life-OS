import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_provider_type.dart';
import '../../../ai/ai_providers.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/extensions/context_x.dart';
import '../../../core/security/secure_store.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import 'settings_screen.dart';

/// Provider selection and key management.
///
/// Two things this screen is careful about: it never displays a stored key back
/// to the user (only whether one exists), and it states plainly what leaves the
/// device for each option.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final TextEditingController _model = TextEditingController();
  bool _hasStoredKey = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshKeyState());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _refreshKeyState() async {
    final provider = ref.read(aiProviderTypeProvider);
    final stored = await ref
        .read(secureStoreProvider)
        .read(SecureKeys.aiKey(provider.id));
    if (!mounted) return;
    setState(() => _hasStoredKey = stored != null && stored.isNotEmpty);
  }

  Future<void> _enterKey(AiProviderType provider) async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${provider.label} API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Paste your key'),
            ),
            Gap.h12,
            Text(
              'Stored in the device keychain, never in the app database and '
              'never in a backup.',
              style: dialogContext.text.labelSmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (key == null || key.trim().isEmpty) return;
    await ref
        .read(secureStoreProvider)
        .write(SecureKeys.aiKey(provider.id), key.trim());
    ref.invalidate(aiApiKeyProvider(provider));
    ref.invalidate(llmClientProvider);
    await _refreshKeyState();
  }

  Future<void> _removeKey(AiProviderType provider) async {
    await ref.read(secureStoreProvider).delete(SecureKeys.aiKey(provider.id));
    ref.invalidate(aiApiKeyProvider(provider));
    ref.invalidate(llmClientProvider);
    await _refreshKeyState();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final selected = ref.watch(aiProviderTypeProvider);
    final health = ref.watch(aiHealthProvider);

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('AI'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
          children: <Widget>[
            SettingsGroup(
              title: 'Provider',
              children: <Widget>[
                for (final provider in AiProviderType.values)
                  RadioListTile<AiProviderType>(
                    value: provider,
                    groupValue: selected,
                    onChanged: (value) async {
                      if (value == null) return;
                      await controller.setAiProvider(value.id);
                      ref.invalidate(llmClientProvider);
                      await _refreshKeyState();
                    },
                    title: Text(provider.label),
                    subtitle: Text(
                      switch (provider) {
                        AiProviderType.offline =>
                          'Nothing leaves your device. Summaries and search '
                              'only — no written answers.',
                        AiProviderType.ollama =>
                          'Runs on your own machine. Private, and needs Ollama '
                              'reachable on your network.',
                        _ => 'Sends the records needed to answer a question to '
                            '${provider.label}.',
                      },
                      style: context.text.labelSmall,
                    ),
                  ),
              ],
            ),
            Gap.h16,
            if (selected.needsApiKey)
              SettingsGroup(
                title: 'API key',
                children: <Widget>[
                  ListTile(
                    leading: Icon(
                      _hasStoredKey
                          ? Icons.key_rounded
                          : Icons.key_off_outlined,
                    ),
                    title: Text(_hasStoredKey ? 'Key saved' : 'No key saved'),
                    subtitle: Text(
                      _hasStoredKey
                          ? 'Stored securely on this device'
                          : 'Required for ${selected.label}',
                      style: context.text.labelSmall,
                    ),
                    trailing: TextButton(
                      onPressed: () => _hasStoredKey
                          ? _removeKey(selected)
                          : _enterKey(selected),
                      child: Text(_hasStoredKey ? 'Remove' : 'Add'),
                    ),
                  ),
                ],
              ),
            Gap.h16,
            SettingsGroup(
              title: 'Behaviour',
              children: <Widget>[
                SwitchListTile(
                  title: const Text('Assistant enabled'),
                  subtitle: const Text(
                    'Turn off to stop all AI features, including summaries',
                  ),
                  value: settings.aiEnabled,
                  onChanged: (value) async {
                    await controller.setAiEnabled(enabled: value);
                    ref.invalidate(llmClientProvider);
                  },
                ),
                SwitchListTile(
                  title: const Text('Share my records with the provider'),
                  subtitle: const Text(
                    'Off keeps everything on-device even with a key saved',
                  ),
                  value: settings.shareDataWithAi,
                  onChanged: (value) async {
                    await controller.setShareDataWithAi(enabled: value);
                    ref.invalidate(llmClientProvider);
                  },
                ),
                ListTile(
                  title: const Text('Model'),
                  subtitle: Text(
                    settings.aiModel.isEmpty
                        ? 'Default (${selected.defaultModel})'
                        : settings.aiModel,
                    style: context.text.labelSmall,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      _model.text = settings.aiModel;
                      final value = await showDialog<String>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Model'),
                          content: TextField(
                            controller: _model,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: selected.defaultModel,
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(''),
                              child: const Text('Use default'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(dialogContext)
                                  .pop(_model.text.trim()),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                      if (value == null) return;
                      await controller.setAiProvider(selected.id, model: value);
                      ref.invalidate(llmClientProvider);
                    },
                    child: const Text('Change'),
                  ),
                ),
              ],
            ),
            Gap.h16,
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(title: 'Status'),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: health.when(
                            data: (ok) => ok
                                ? context.theme.colorScheme.primary
                                : context.colors.error,
                            loading: () => context.colors.outline,
                            error: (_, __) => context.colors.error,
                          ),
                        ),
                      ),
                      Gap.w12,
                      Expanded(
                        child: Text(
                          health.when(
                            data: (ok) => ok
                                ? 'Reachable — using ${ref.watch(aiServiceProvider).model}'
                                : 'Not reachable. LifeOS is using on-device mode.',
                            loading: () => 'Checking…',
                            error: (_, __) => 'Could not check the connection.',
                          ),
                          style: context.text.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Re-check',
                        onPressed: () => ref.invalidate(aiHealthProvider),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
