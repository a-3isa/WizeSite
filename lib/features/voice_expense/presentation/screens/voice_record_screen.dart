import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'dart:async';
import 'dart:io';

import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/voice_recorder_service.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_processing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoiceRecordScreen extends ConsumerStatefulWidget {
  const VoiceRecordScreen({super.key});

  @override
  ConsumerState<VoiceRecordScreen> createState() => _VoiceRecordScreenState();
}

class _VoiceRecordScreenState extends ConsumerState<VoiceRecordScreen> {
  Timer? _timer;
  bool _isRecording = false;
  int _elapsedSeconds = 0;
  String? _recordingPath;
  String? _readyFilePath;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      _error = null;
      _readyFilePath = null;
      _elapsedSeconds = 0;
    });

    try {
      final path = await ref.read(voiceRecorderServiceProvider).start();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          return;
        }
        setState(() => _elapsedSeconds += 1);
        if (_elapsedSeconds >= 20) {
          unawaited(_stopRecording());
        }
      });
      setState(() {
        _recordingPath = path;
        _isRecording = true;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    try {
      final path = await ref.read(voiceRecorderServiceProvider).stop();
      setState(() {
        _isRecording = false;
        _readyFilePath = path ?? _recordingPath;
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    await ref.read(voiceRecorderServiceProvider).cancel();
    setState(() {
      _isRecording = false;
      _elapsedSeconds = 0;
      _recordingPath = null;
      _readyFilePath = null;
      _error = null;
    });
  }

  Future<void> _goToProcessing(List<VoiceProjectOption> projects) async {
    final l10n = AppLocalizations.of(context);
    final userId = ref.read(activeUserIdProvider);
    final audioPath = _readyFilePath;
    final languageHint = Localizations.localeOf(context).languageCode;
    if (userId == null || userId.isEmpty) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    if (audioPath == null || audioPath.isEmpty) {
      setState(() => _error = l10n.t('recordAudioFirst'));
      return;
    }
    if (!await File(audioPath).exists()) {
      setState(() => _error = l10n.t('recordedFileMissing'));
      return;
    }

    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceProcessingScreen(
          userId: userId,
          localAudioPath: audioPath,
          projects: projects,
          currency: 'EGP',
          languageHint: languageHint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('voiceExpense'))),
      body: projectsAsync.when(
        data: (projects) {
          final projectOptions = projects
              .map(
                (project) =>
                    VoiceProjectOption(id: project.id, name: project.name),
              )
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.t('recordShortNote')),
              const SizedBox(height: 16),
              Center(
                child: IconButton.filledTonal(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  iconSize: 40,
                  style: IconButton.styleFrom(minimumSize: const Size(88, 88)),
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _isRecording
                      ? l10n.t(
                          'recording',
                          params: {'seconds': '$_elapsedSeconds'},
                        )
                      : (_readyFilePath == null
                            ? l10n.t('notRecording')
                            : l10n.t('readyToProcess')),
                ),
              ),
              if (_readyFilePath != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.t(
                    'file',
                    params: {
                      'name': _readyFilePath!.split(Platform.pathSeparator).last,
                    },
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isRecording ? _cancelRecording : null,
                      child: Text(l10n.t('cancelRerecord')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isRecording || _readyFilePath == null
                          ? null
                          : () => _goToProcessing(projectOptions),
                      child: Text(l10n.t('processVoice')),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }
}
