import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'dart:async';

import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/services/cloud_function_service.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/utils/callable_error_message.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_expense_repository.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_review_screen.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  bool _requiresLogin = false;
  bool _hasStartedProcessing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStartedProcessing) {
      return;
    }
    _hasStartedProcessing = true;
    unawaited(_process());
  }

  Future<void> _process() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _uploadProgress = 0;
      _stage = l10n.t('uploadingAudio');
      _error = null;
      _requiresLogin = false;
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
        _error = _messageForError(e, l10n);
        _stage = l10n.t('failed');
        _requiresLogin = _shouldRouteToLogin(e);
      });
    }
  }

  bool _isUnauthenticatedError(Object error) {
    if (error is CloudFunctionServiceException) {
      return error.code == 'unauthenticated';
    }
    if (error is CallableClientException) {
      return error.code == 'unauthenticated';
    }
    return false;
  }

  bool _shouldRouteToLogin(Object error) {
    if (!_isUnauthenticatedError(error)) {
      return false;
    }

    return ref.read(firebaseAuthProvider).currentUser == null;
  }

  String _messageForError(Object error, AppLocalizations l10n) {
    if (error is CloudFunctionServiceException) {
      if (error.code == 'unauthenticated') {
        final message = error.message.trim();
        if (message.isNotEmpty) {
          return message;
        }
        if (ref.read(firebaseAuthProvider).currentUser == null) {
          return l10n.t('pleaseLoginFirst');
        }
        return l10n.t('unexpectedErrorTryAgain');
      }
      final message = error.message.trim();
      return message.isEmpty ? l10n.t('unexpectedErrorTryAgain') : message;
    }
    if (error is CallableClientException) {
      return callableErrorMessage(error, l10n);
    }
    return appErrorMessage(l10n, error);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasError = _error != null;
    return AppBackScope(
      fallbackRoute: AppRoutes.voiceExpense,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('processingVoice'),
          fallbackRoute: AppRoutes.voiceExpense,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 48,
              ),
              child: Center(
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
                      Text(_stage, textAlign: TextAlign.center),
                    ] else ...[
                      Icon(
                        Icons.error_outline,
                        color: context.tokens.expense,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: context.tokens.expense),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _requiresLogin
                            ? () => context.go(AppRoutes.login)
                            : _process,
                        child: Text(
                          _requiresLogin ? l10n.t('login') : l10n.t('retry'),
                        ),
                      ),
                    ],
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
