import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'dart:async';
import 'dart:io';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/microphone_permission_service.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_capture_state.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/controllers/voice_capture_controller.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_processing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoiceRecordScreen extends ConsumerStatefulWidget {
  const VoiceRecordScreen({super.key});

  @override
  ConsumerState<VoiceRecordScreen> createState() => _VoiceRecordScreenState();
}

class _VoiceRecordScreenState extends ConsumerState<VoiceRecordScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  /// Screen-level message key for permission-related failures (the controller
  /// only owns recording/playback failures).
  String? _permissionErrorKey;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  VoiceCaptureController get _controller =>
      ref.read(voiceCaptureControllerProvider.notifier);

  Future<void> _onMicPressed() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _permissionErrorKey = null);
    final granted = await _ensureMicrophonePermission(l10n);
    if (!granted) return;
    await _controller.startRecording();
  }

  Future<bool> _ensureMicrophonePermission(AppLocalizations l10n) async {
    final permissionService = ref.read(microphonePermissionServiceProvider);
    final currentStatus = await permissionService.status();
    if (currentStatus == MicrophonePermissionStatus.granted) {
      return true;
    }
    if (currentStatus == MicrophonePermissionStatus.blocked) {
      await _showMicrophoneSettingsDialog(l10n);
      return false;
    }

    if (!mounted) {
      return false;
    }
    final shouldRequest = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(l10n.t('microphonePermissionTitle')),
        content: Text(l10n.t('microphonePermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('notNow')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.t('microphonePermissionContinue')),
          ),
        ],
      ),
    );
    if (shouldRequest != true) {
      return false;
    }

    final requestedStatus = await permissionService.request();
    if (requestedStatus == MicrophonePermissionStatus.granted) {
      return true;
    }
    if (requestedStatus == MicrophonePermissionStatus.blocked) {
      await _showMicrophoneSettingsDialog(l10n);
      return false;
    }
    if (mounted) {
      setState(() => _permissionErrorKey = 'microphonePermissionDenied');
    }
    return false;
  }

  Future<void> _showMicrophoneSettingsDialog(AppLocalizations l10n) async {
    if (!mounted) {
      return;
    }
    final openSettings = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(l10n.t('microphonePermissionSettingsTitle')),
        content: Text(l10n.t('microphonePermissionSettingsMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('notNow')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.t('openSettings')),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await ref.read(microphonePermissionServiceProvider).openSettings();
    }
  }

  Future<void> _goToProcessing(
    List<VoiceProjectOption> projects,
    VoiceCaptureState captureState,
  ) async {
    final authUser = ref.read(firebaseAuthProvider).currentUser;
    final userId = authUser?.uid;
    final audioPath = captureState.recordingPath;
    final languageHint = Localizations.localeOf(context).languageCode;
    if (userId == null || userId.isEmpty) {
      ref.read(activeUserIdProvider.notifier).state = null;
      setState(() => _permissionErrorKey = 'pleaseLoginFirst');
      return;
    }
    ref.read(activeUserIdProvider.notifier).state = userId;
    if (audioPath == null || audioPath.isEmpty) {
      setState(() => _permissionErrorKey = 'recordAudioFirst');
      return;
    }
    if (!await File(audioPath).exists()) {
      setState(() => _permissionErrorKey = 'recordedFileMissing');
      return;
    }

    if (!mounted) {
      return;
    }
    _controller.markProcessing();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceProcessingScreen(
          userId: userId,
          localAudioPath: audioPath,
          projects: projects,
          currency: captureState.currencyCode,
          languageHint: languageHint,
        ),
      ),
    );
  }

  Future<void> _handleBackNavigation() async {
    final state = ref.read(voiceCaptureControllerProvider);
    if (state.isRecording || state.hasRecording || state.isPlaying) {
      await _controller.cancel();
    }
    if (!mounted) {
      return;
    }
    appNavigateBack(context, fallbackRoute: AppRoutes.dashboard);
  }

  void _syncPulse(VoiceCaptureState state) {
    if (state.isRecording) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    final captureState = ref.watch(voiceCaptureControllerProvider);

    ref.listen<VoiceCaptureState>(voiceCaptureControllerProvider, (_, next) {
      _syncPulse(next);
    });
    _syncPulse(captureState);

    final errorKey = captureState.hasError
        ? captureState.errorKey
        : _permissionErrorKey;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleBackNavigation());
      },
      child: Scaffold(
        backgroundColor: context.tokens.bg,
        appBar: AppBar(
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: _handleBackNavigation,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            l10n.t('voiceExpense'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: projectsAsync.whenStale(
          data: (projects) {
            final projectOptions = projects
                .map(
                  (project) =>
                      VoiceProjectOption(id: project.id, name: project.name),
                )
                .toList();

            return Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusLine(state: captureState),
                      const SizedBox(height: 20),
                      _MicButton(
                        isRecording: captureState.isRecording,
                        pulseController: _pulseController,
                        onPressed: captureState.isRecording
                            ? _controller.stopRecording
                            : _onMicPressed,
                      ),
                      const SizedBox(height: 24),
                      _WaveformVisualizer(
                        isRecording: captureState.isRecording,
                        amplitude: captureState.amplitude,
                      ),
                      if (captureState.hasRecording &&
                          !captureState.isRecording)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: TextButton.icon(
                            onPressed: _controller.togglePlayback,
                            icon: Icon(
                              captureState.isPlaying
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              size: 32,
                              color: AppColors.constructionOrange,
                            ),
                            label: Text(
                              l10n.t('voicePlayRecording'),
                              style: const TextStyle(
                                color: AppColors.constructionOrange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.constructionOrange
                                  .withValues(alpha: 0.1),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (errorKey != null)
                  Positioned(
                    top: 100,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.danger,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.t(errorKey),
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                    decoration: BoxDecoration(
                      color: context.tokens.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                captureState.isRecording ||
                                    captureState.hasRecording
                                ? _controller.cancel
                                : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: context.tokens.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              l10n.t('cancelRerecord'),
                              style: TextStyle(
                                color: context.tokens.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                captureState.isRecording ||
                                    !captureState.hasRecording
                                ? null
                                : () => _goToProcessing(
                                    projectOptions,
                                    captureState,
                                  ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.constructionOrange,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              l10n.t('processVoice'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const AppLoadingSkeleton(lineCount: 4),
          error: (error, _) =>
              Center(child: Text(l10n.t('somethingWentWrong'))),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final VoiceCaptureState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String label;
    if (state.isRecording) {
      label = l10n.t(
        'voiceCountdownRemaining',
        params: {'seconds': '${state.remaining.inSeconds}'},
      );
    } else if (state.isProcessing) {
      label = l10n.t('voiceProcessing');
    } else if (state.hasRecording) {
      label = l10n.t('readyToProcess');
    } else {
      label = l10n.t('tapToStart');
    }

    return Text(
      label,
      key: const Key('voiceStatusLine'),
      style: TextStyle(
        color: state.isRecording ? AppColors.danger : context.tokens.textMuted,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.isRecording,
    required this.pulseController,
    required this.onPressed,
  });

  final bool isRecording;
  final AnimationController pulseController;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final scale = 1.0 + (pulseController.value * 0.15);
        return GestureDetector(
          onTap: onPressed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isRecording)
                Container(
                  width: 120 * scale,
                  height: 120 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.constructionOrange.withValues(alpha: 0.2),
                  ),
                ),
              if (isRecording)
                Container(
                  width: 150 * scale,
                  height: 150 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.constructionOrange.withValues(alpha: 0.1),
                  ),
                ),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRecording
                      ? AppColors.danger
                      : AppColors.constructionOrange,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (isRecording
                                  ? AppColors.danger
                                  : AppColors.constructionOrange)
                              .withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Live audio-level visualizer driven by the recorder amplitude. Shows a flat
/// baseline when idle.
class _WaveformVisualizer extends StatelessWidget {
  const _WaveformVisualizer({
    required this.isRecording,
    required this.amplitude,
  });

  final bool isRecording;
  final double amplitude;

  static const int _barCount = 30;

  @override
  Widget build(BuildContext context) {
    if (!isRecording) {
      return const SizedBox(height: 40);
    }

    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (index) {
          // Symmetric envelope around the center, scaled by the live amplitude.
          final distance = (index - _barCount / 2).abs() / (_barCount / 2);
          final envelope = (1.0 - distance).clamp(0.2, 1.0);
          final height = (6.0 + amplitude.clamp(0.0, 1.0) * 32.0 * envelope)
              .clamp(4.0, 40.0);
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: AppColors.constructionOrange,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
