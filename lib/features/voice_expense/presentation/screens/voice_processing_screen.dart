import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'dart:async';

import 'package:buildtrack_app/features/voice_expense/data/voice_expense_repository.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoiceProcessingScreen extends ConsumerStatefulWidget {
  const VoiceProcessingScreen({
    required this.userId,
    required this.localAudioPath,
    required this.projects,
    required this.currency,
    required this.languageHint,
    super.key,
  });

  final String userId;
  final String localAudioPath;
  final List<VoiceProjectOption> projects;
  final String currency;
  final String languageHint;

  @override
  ConsumerState<VoiceProcessingScreen> createState() =>
      _VoiceProcessingScreenState();
}

class _VoiceProcessingScreenState extends ConsumerState<VoiceProcessingScreen> {
  double _uploadProgress = 0;
  String _stage = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_process());
  }

  Future<void> _process() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _uploadProgress = 0;
      _stage = l10n.t('uploadingAudio');
      _error = null;
    });

    try {
      final response = await ref
          .read(voiceExpenseRepositoryProvider)
          .processVoiceRecording(
            userId: widget.userId,
            localAudioPath: widget.localAudioPath,
            projects: widget.projects,
            currency: widget.currency,
            languageHint: widget.languageHint,
            onUploadProgress: (progress) {
              if (!mounted) {
                return;
              }
              setState(() => _uploadProgress = progress);
            },
          );

      if (!mounted) {
        return;
      }
      setState(() => _stage = l10n.t('parsingExpense'));
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              VoiceReviewScreen(response: response, projects: widget.projects),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _stage = l10n.t('failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasError = _error != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('processingVoice'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasError) ...[
                CircularProgressIndicator(
                  value: _uploadProgress > 0 && _uploadProgress < 1
                      ? _uploadProgress
                      : null,
                ),
                const SizedBox(height: 16),
                Text(_stage),
              ] else ...[
                const Icon(Icons.error_outline, color: Colors.red, size: 42),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _process, child: Text(l10n.t('retry'))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
