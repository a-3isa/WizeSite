import 'dart:io';

import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/utils/app_error_messages.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/navigation/app_back_navigation.dart';
import 'package:buildtrack_app/core/providers/workspace_provider.dart';
import 'package:buildtrack_app/core/widgets/app_async_state.dart';
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
    final settings = ref.read(currentUserSettingsProvider).valueOrNull;
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
    final settingsAsync = ref.watch(currentUserSettingsProvider);

    return AppBackScope(
      fallbackRoute: AppRoutes.settings,
      child: Scaffold(
        appBar: appBackAppBar(
          context: context,
          title: l10n.t('profile'),
          fallbackRoute: AppRoutes.settings,
        ),
        body: settingsAsync.when(
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
                        backgroundImage: imageProvider,
                        child: imageProvider == null
                            ? Text(
                                _initials(
                                  settings.fullName.isEmpty
                                      ? settings.email
                                      : settings.fullName,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _saving ? null : _pickImage,
                        child: Text(l10n.t('changePhoto')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: l10n.t('fullName')),
                ),
                const SizedBox(height: 12),
                TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: l10n.t('email'),
                    hintText: settings.email,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.t('save')),
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
