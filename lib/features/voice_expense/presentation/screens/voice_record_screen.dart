import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/firebase_providers.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/services/microphone_permission_service.dart';
import 'package:buildtrack_app/core/services/voice_recorder_service.dart';
import 'package:buildtrack_app/features/projects/presentation/screens/projects_screen.dart';
import 'package:buildtrack_app/features/voice_expense/domain/voice_expense_models.dart';
import 'package:buildtrack_app/features/voice_expense/presentation/screens/voice_processing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceRecordScreen extends ConsumerStatefulWidget {
  const VoiceRecordScreen({super.key});

  @override
  ConsumerState<VoiceRecordScreen> createState() => _VoiceRecordScreenState();
}

class _VoiceRecordScreenState extends ConsumerState<VoiceRecordScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  bool _isRecording = false;
  int _elapsedSeconds = 0;
  String? _recordingPath;
  String? _readyFilePath;
  String? _error;
  late AnimationController _pulseController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

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
    _timer?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error = null;
      _readyFilePath = null;
      _elapsedSeconds = 0;
    });

    try {
      final hasPermission = await _ensureMicrophonePermission(l10n);
      if (!hasPermission) {
        return;
      }

      final path = await ref.read(voiceRecorderServiceProvider).start();
      _pulseController.repeat(reverse: true);
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
      setState(() => _error = l10n.t('microphonePermissionDenied'));
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

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseController.stop();
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
    _pulseController.stop();
    await _audioPlayer.stop();
    await ref.read(voiceRecorderServiceProvider).cancel();
    setState(() {
      _isRecording = false;
      _isPlaying = false;
      _elapsedSeconds = 0;
      _recordingPath = null;
      _readyFilePath = null;
      _error = null;
    });
  }

  Future<void> _playRecording() async {
    final path = _readyFilePath;
    if (path == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() => _isPlaying = false);
      } else {
        await _audioPlayer.play(DeviceFileSource(path));
        setState(() => _isPlaying = true);

        _audioPlayer.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isPlaying = false);
          }
        });
      }
    } catch (e) {
      setState(() => _error = "Play error: $e");
    }
  }

  Future<void> _goToProcessing(List<VoiceProjectOption> projects) async {
    final l10n = AppLocalizations.of(context);
    final authUser = ref.read(firebaseAuthProvider).currentUser;
    final userId = authUser?.uid;
    final audioPath = _readyFilePath;
    final languageHint = Localizations.localeOf(context).languageCode;
    if (userId == null || userId.isEmpty) {
      ref.read(activeUserIdProvider.notifier).state = null;
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }
    ref.read(activeUserIdProvider.notifier).state = userId;
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

  Future<void> _handleBackNavigation() async {
    if (_isRecording || _readyFilePath != null || _isPlaying) {
      await _cancelRecording();
    }
    if (!mounted) {
      return;
    }
    appNavigateBack(context, fallbackRoute: AppRoutes.add);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(projectsProvider);

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleBackNavigation());
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceGrey,
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
        body: projectsAsync.when(
          data: (projects) {
            final projectOptions = projects
                .map(
                  (project) =>
                      VoiceProjectOption(id: project.id, name: project.name),
                )
                .toList();

            return Stack(
              children: [
                // Column(
                //   children: [
                //     const SizedBox(height: 40),
                //     // Padding(
                //     //   padding: const EdgeInsets.symmetric(horizontal: 40),
                //     //   child: Text(
                //     //     l10n.t('recordShortNote'),
                //     //     textAlign: TextAlign.center,
                //     //     style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                //     //       color: AppColors.textDark,
                //     //       fontWeight: FontWeight.w600,
                //     //       letterSpacing: -0.5,
                //     //     ),
                //     //   ),
                //     // ),
                //     const SizedBox(height: 12),
                //     Text(
                //       _isRecording
                //           ? l10n.t(
                //               'recording',
                //               params: {'seconds': '$_elapsedSeconds'},
                //             )
                //           : (_readyFilePath == null
                //                 ? l10n.t('tapToStart')
                //                 : l10n.t('readyToProcess')),
                //       style: TextStyle(
                //         color: _isRecording
                //             ? AppColors.danger
                //             : AppColors.textBody,
                //         fontWeight: FontWeight.w500,
                //       ),
                //     ),
                //     const Spacer(),
                //     _WaveformVisualizer(isRecording: _isRecording),
                //     const Spacer(flex: 2),
                //   ],
                // ),
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MicButton(
                        isRecording: _isRecording,
                        pulseController: _pulseController,
                        onPressed: _isRecording
                            ? _stopRecording
                            : _startRecording,
                      ),
                      if (kDebugMode &&
                          _readyFilePath != null &&
                          !_isRecording) ...[
                        const SizedBox(height: 24),
                        TextButton.icon(
                          onPressed: _playRecording,
                          icon: Icon(
                            _isPlaying ? Icons.pause_circle : Icons.play_circle,
                            size: 32,
                            color: AppColors.constructionOrange,
                          ),
                          label: Text(
                            _isPlaying ? "Pause Test" : "Play Test",
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
                      ],
                    ],
                  ),
                ),
                if (_error != null)
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
                              _error!,
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
                      color: AppColors.surfaceSolid,
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
                            onPressed: _isRecording || _readyFilePath != null
                                ? _cancelRecording
                                : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: AppColors.borderGrey),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              l10n.t('cancelRerecord'),
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isRecording || _readyFilePath == null
                                ? null
                                : () => _goToProcessing(projectOptions),
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
        ),
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

class _WaveformVisualizer extends StatefulWidget {
  const _WaveformVisualizer({required this.isRecording});

  final bool isRecording;

  @override
  State<_WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<_WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _heights = List.generate(
    30,
    (index) => 4.0 + math.Random().nextDouble() * 20.0,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRecording) {
      return const SizedBox(height: 40);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(30, (index) {
            final animatedHeight =
                _heights[index] * (0.5 + _controller.value * 0.5);
            return Container(
              width: 3,
              height: animatedHeight,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: AppColors.constructionOrange,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
