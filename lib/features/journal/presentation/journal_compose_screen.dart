import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/extensions/context_x.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../domain/entities/journal_entry.dart';
import '../../../services/voice/voice_input_service.dart';
import '../application/journal_controller.dart';

/// The writing surface.
///
/// Everything optional is one tap away and nothing blocks the text field: the
/// only thing that must be effortless here is writing.
class JournalComposeScreen extends ConsumerStatefulWidget {
  const JournalComposeScreen({this.entryId, super.key});

  final String? entryId;

  @override
  ConsumerState<JournalComposeScreen> createState() =>
      _JournalComposeScreenState();
}

class _JournalComposeScreenState extends ConsumerState<JournalComposeScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final List<Attachment> _attachments = <Attachment>[];
  final List<String> _tags = <String>[];

  int? _moodScore;
  GeoPoint? _location;
  String? _weather;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final id = widget.entryId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(id));
    } else {
      _loaded = true;
    }
  }

  Future<void> _load(String id) async {
    final entry = await ref.read(journalEntryProvider(id).future);
    if (entry == null || !mounted) return;
    setState(() {
      _title.text = entry.title;
      _body.text = entry.body;
      _tags
        ..clear()
        ..addAll(entry.tags);
      _attachments
        ..clear()
        ..addAll(entry.attachments);
      _moodScore = entry.moodScore;
      _location = entry.location;
      _weather = entry.weather;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // Journals accumulate hundreds of photos; full-resolution originals would
      // dominate the app's storage for no visible benefit.
      maxWidth: 2400,
      imageQuality: 88,
    );
    if (picked == null) return;
    setState(() {
      _attachments.add(
        Attachment(
          id: newId(),
          entryId: widget.entryId ?? '',
          kind: AttachmentKind.photo,
          localPath: picked.path,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'work, family, travel…'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final trimmed = tag?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return;
    setState(() => _tags.add(trimmed));
  }

  Future<void> _dictate() async {
    final notifier = ref.read(voiceInputProvider.notifier);
    await notifier.startListening();
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty && _attachments.isEmpty) {
      context.showError('Write something first.');
      return;
    }

    final now = DateTime.now();
    final entry = JournalEntry(
      id: widget.entryId ?? '',
      createdAt: now,
      updatedAt: now,
      dayKey: Fmt.dayKey(now),
      title: _title.text.trim(),
      body: _body.text.trim(),
      tags: _tags,
      attachments: _attachments,
      location: _location,
      weather: _weather,
      moodScore: _moodScore,
    );

    final result = await ref.read(journalComposerProvider.notifier).save(entry);
    if (!mounted) return;
    result.fold(
      (_) {
        context.showSnack('Saved');
        context.pop();
      },
      (failure) => context.showError(failure.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(journalComposerProvider);
    final voice = ref.watch(voiceInputProvider);

    // Dictated text lands straight in the body field.
    ref.listen(voiceInputProvider, (previous, next) {
      if (next.status == VoiceStatus.listening && next.transcript.isNotEmpty) {
        _body.text = next.transcript;
        _body.selection =
            TextSelection.collapsed(offset: _body.text.length);
      }
    });

    return AppBackdrop(
      accent: AppColors.journal,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(widget.entryId == null ? 'New entry' : 'Edit entry'),
          actions: <Widget>[
            TextButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 120),
                children: <Widget>[
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    style: context.text.titleLarge,
                    decoration: const InputDecoration(
                      hintText: 'Title (optional)',
                      border: InputBorder.none,
                      filled: false,
                    ),
                  ),
                  TextField(
                    controller: _body,
                    autofocus: widget.entryId == null,
                    minLines: 8,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: context.text.bodyLarge?.copyWith(height: 1.5),
                    decoration: const InputDecoration(
                      hintText: 'What happened today?',
                      border: InputBorder.none,
                      filled: false,
                    ),
                  ),
                  if (voice.status == VoiceStatus.listening)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: Text(
                        'Listening…',
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.error,
                        ),
                      ),
                    ),
                  Gap.h24,
                  _MoodPicker(
                    value: _moodScore,
                    onChanged: (value) => setState(() => _moodScore = value),
                  ),
                  Gap.h24,
                  if (_attachments.isNotEmpty) ...<Widget>[
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachments.length,
                        separatorBuilder: (_, __) => Gap.w8,
                        itemBuilder: (context, index) => _AttachmentThumb(
                          attachment: _attachments[index],
                          onRemove: () =>
                              setState(() => _attachments.removeAt(index)),
                        ),
                      ),
                    ),
                    Gap.h16,
                  ],
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: <Widget>[
                      for (final tag in _tags)
                        InputChip(
                          label: Text(tag),
                          onDeleted: () => setState(() => _tags.remove(tag)),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Tag'),
                        onPressed: _addTag,
                      ),
                    ],
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.sm,
              vertical: Gap.xs,
            ),
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Photo',
                  onPressed: () => _addPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_outlined),
                ),
                IconButton(
                  tooltip: 'Camera',
                  onPressed: () => _addPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                IconButton(
                  tooltip: 'Dictate',
                  onPressed: _dictate,
                  icon: const Icon(Icons.mic_none_rounded),
                ),
                IconButton(
                  tooltip: 'Add location',
                  onPressed: () => setState(
                    // Real coordinates come from geolocator once the user has
                    // granted permission; the name alone is enough for search
                    // and the travel timeline.
                    () => _location = const GeoPoint(
                      latitude: 0,
                      longitude: 0,
                      name: 'Current location',
                    ),
                  ),
                  icon: Icon(
                    _location == null
                        ? Icons.place_outlined
                        : Icons.place_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodPicker extends StatelessWidget {
  const _MoodPicker({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'How was today?',
            style: context.text.labelLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Gap.h8,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (var score = 2; score <= 10; score += 2)
                IconButton(
                  tooltip: '$score out of 10',
                  onPressed: () => onChanged(value == score ? null : score),
                  isSelected: value == score,
                  icon: Text(
                    switch (score) {
                      2 => '😣',
                      4 => '😕',
                      6 => '😐',
                      8 => '🙂',
                      _ => '😄',
                    },
                    style: TextStyle(fontSize: value == score ? 30 : 24),
                  ),
                ),
            ],
          ),
        ],
      );
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.attachment, required this.onRemove});

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Container(
              width: 92,
              height: 92,
              color: context.colors.surfaceContainerHighest,
              child: Icon(
                switch (attachment.kind) {
                  AttachmentKind.photo => Icons.image_outlined,
                  AttachmentKind.video => Icons.videocam_outlined,
                  AttachmentKind.audio => Icons.graphic_eq_rounded,
                  AttachmentKind.document => Icons.description_outlined,
                },
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filledTonal(
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      );
}
