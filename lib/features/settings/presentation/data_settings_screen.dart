import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../services/export/export_service.dart';
import 'settings_screen.dart';

/// Export, backup and re-index.
class DataSettingsScreen extends ConsumerStatefulWidget {
  const DataSettingsScreen({super.key});

  @override
  ConsumerState<DataSettingsScreen> createState() =>
      _DataSettingsScreenState();
}

class _DataSettingsScreenState extends ConsumerState<DataSettingsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportJson({bool encrypted = false}) async {
    String? passphrase;
    if (encrypted) {
      passphrase = await _askPassphrase();
      if (passphrase == null) return;
    }

    await _run(() async {
      final service = ref.read(exportServiceProvider);
      final result = await service.exportJson(passphrase: passphrase);
      if (!mounted) return;
      await result.fold(
        (file) => service.share(<File>[file], subject: 'LifeOS backup'),
        (failure) async => context.showError(failure.message),
      );
    });
  }

  Future<void> _exportCsv() => _run(() async {
        final service = ref.read(exportServiceProvider);
        final result = await service.exportCsv();
        if (!mounted) return;
        await result.fold(
          (files) => service.share(files, subject: 'LifeOS CSV export'),
          (failure) async => context.showError(failure.message),
        );
      });

  Future<void> _restore() async {
    const group = XTypeGroup(
      label: 'LifeOS backup',
      extensions: <String>['json', 'lifeos'],
    );
    final picked = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    if (picked == null) return;

    // An encrypted archive cannot be read without the passphrase, so ask for
    // it up front rather than failing after the user has waited.
    String? passphrase;
    if (picked.path.endsWith('.lifeos')) {
      passphrase = await _askPassphrase(
        title: 'Open encrypted backup',
        action: 'Restore',
      );
      if (passphrase == null) return;
    }

    await _run(() async {
      final result = await ref
          .read(exportServiceProvider)
          .importJson(File(picked.path), passphrase: passphrase);
      if (!mounted) return;

      result.fold(
        (summary) {
          if (summary.isEmpty) {
            context.showError('That backup contained nothing to restore.');
            return;
          }
          // Reminders and home-screen widgets rebuild themselves: the restore
          // wrote through the same tables `reminderSyncProvider` and
          // `homeWidgetSyncProvider` watch, and their transaction has
          // committed by the time this runs.
          context.showSnack(
            'Restored ${summary.total} records'
            '${summary.totalSkipped == 0 ? '' : ' · ${summary.totalSkipped} skipped'}',
          );
        },
        (failure) => context.showError(failure.message),
      );
    });
  }

  Future<String?> _askPassphrase({
    String title = 'Encrypt this backup',
    String action = 'Encrypt',
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
            ),
            Gap.h12,
            Text(
              action == 'Restore'
                  ? 'The passphrase you set when this backup was created.'
                  : 'There is no recovery. If you lose this passphrase the '
                      'backup cannot be opened — by you or by anyone else.',
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
            child: Text(action),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Data'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 80),
            children: <Widget>[
              SettingsGroup(
                title: 'Export',
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.data_object_rounded),
                    title: const Text('Full backup (JSON)'),
                    subtitle: const Text('Everything, re-importable'),
                    enabled: !_busy,
                    onTap: _exportJson,
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: const Text('Encrypted backup'),
                    subtitle: const Text('AES-256-GCM, passphrase protected'),
                    enabled: !_busy,
                    onTap: () => _exportJson(encrypted: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.table_chart_outlined),
                    title: const Text('Spreadsheets (CSV)'),
                    subtitle: const Text(
                      'One file per module, for your own analysis',
                    ),
                    enabled: !_busy,
                    onTap: _exportCsv,
                  ),
                ],
              ),
              Gap.h16,
              SettingsGroup(
                title: 'Restore',
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('Restore from a backup'),
                    subtitle: const Text(
                      'Merges by record id, so restoring twice is safe',
                    ),
                    enabled: !_busy,
                    onTap: _restore,
                  ),
                ],
              ),
              Gap.h16,
              SettingsGroup(
                title: 'Maintenance',
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.manage_search_rounded),
                    title: const Text('Rebuild search index'),
                    subtitle: const Text(
                      'Run this after importing a backup',
                    ),
                    enabled: !_busy,
                    onTap: () => _run(() async {
                      final result =
                          await ref.read(searchRepositoryProvider).reindex();
                      if (!mounted) return;
                      result.fold(
                        (_) => context.showSnack('Search index rebuilt'),
                        (failure) => context.showError(failure.message),
                      );
                    }),
                  ),
                ],
              ),
              Gap.h16,
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionHeader(title: 'About your exports'),
                    Text(
                      'Exports contain your records but never your API keys or '
                      'session tokens — those stay in the device keychain. '
                      'Media files are referenced by path; copy them '
                      'separately if you are moving to a new device.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_busy) ...<Widget>[
                Gap.h24,
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      );
}
