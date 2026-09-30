import 'dart:io';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
import 'package:buildtrack_app/core/widgets/async_content.dart';
import 'package:buildtrack_app/core/widgets/ds/ds.dart';
import 'package:buildtrack_app/features/settings/data/profile_repository.dart';
import 'package:buildtrack_app/features/settings/data/user_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _nameController = TextEditingController();
  String? _localPhotoPath;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (image != null && mounted) {
      setState(() => _localPhotoPath = image.path);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final userId = ref.read(activeUserIdProvider);
    final settings = ref.read(currentUserSettingsProvider).value;
    if (userId == null || userId.isEmpty || settings == null) {
      setState(() => _error = l10n.t('pleaseLoginFirst'));
      return;
    }

    final fullName = _nameController.text.trim();
    if (fullName.isEmpty) {
      setState(() => _error = l10n.t('fillRequiredFields'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      String? photoUrl = settings.photoUrl;
      if (_localPhotoPath != null && _localPhotoPath!.isNotEmpty) {
        photoUrl = await ref
            .read(profileRepositoryProvider)
            .uploadProfilePhoto(
              userId: userId,
              localFilePath: _localPhotoPath!,
            );
      }

      await ref
          .read(profileRepositoryProvider)
          .updateProfile(fullName: fullName, photoUrl: photoUrl);
      await ref
          .read(userSettingsRepositoryProvider)
          .cacheProfileUpdate(
            userId: userId,
            fullName: fullName,
            photoUrl: photoUrl,
          );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = appErrorMessage(l10n, error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final settingsAsync = ref.watch(currentUserSettingsProvider);

    return AppBackScope(
      fallbackRoute: AppRoutes.settings,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('profile'),
          fallbackRoute: AppRoutes.settings,
        ),
        body: settingsAsync.whenStale(
          data: (settings) {
            if (_nameController.text.isEmpty) {
              _nameController.text = settings.fullName.isEmpty
                  ? settings.email.split('@').first
                  : settings.fullName;
            }

            final ImageProvider<Object>? imageProvider = _localPhotoPath != null
                ? FileImage(File(_localPhotoPath!))
                : (settings.photoUrl.isNotEmpty
                      ? NetworkImage(settings.photoUrl)
                      : null);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: t.accentSoft,
                        backgroundImage: imageProvider,
                        child: imageProvider == null
                            ? Text(
                                _initials(
                                  settings.fullName.isEmpty
                                      ? settings.email
                                      : settings.fullName,
                                ),
                                style: TextStyle(
                                  color: t.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 28,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      BuildButton(
                        label: l10n.t('changePhoto'),
                        variant: BuildButtonVariant.outline,
                        size: BuildButtonSize.sm,
                        onPressed: _saving ? null : _pickImage,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                BuildCard(
                  child: BuildTextField(
                    label: l10n.t('fullName'),
                    controller: _nameController,
                    enabled: !_saving,
                    textInputAction: TextInputAction.done,
                  ),
                ),
                const SizedBox(height: 12),
                BuildCard(
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline, color: t.textMuted, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.t('email'),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: t.textMuted,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              settings.email,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 24),
                if (_saving)
                  const Center(child: CircularProgressIndicator())
                else
                  BuildButton(
                    label: l10n.t('save'),
                    size: BuildButtonSize.lg,
                    full: true,
                    onPressed: _save,
                  ),
              ],
            );
          },
          error: (error, _) =>
              Center(child: Text(appErrorMessage(l10n, error))),
          loading: () => const AppLoadingSkeleton(lineCount: 8),
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'U';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.expenseSoft, borderRadius: t.radiusMd),
      child: Text(message, style: TextStyle(color: t.expense, fontSize: 13.5)),
    );
  }
}
