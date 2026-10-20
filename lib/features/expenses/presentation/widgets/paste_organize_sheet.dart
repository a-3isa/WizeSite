import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/providers/connectivity_provider.dart';
import 'package:buildtrack_app/core/services/callable_client.dart';
import 'package:buildtrack_app/features/expenses/data/expense_text_organizer.dart';
import 'package:buildtrack_app/features/voice_expense/data/voice_ai_disclosure_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Pasted receipt text not yet saved: survives closing and reopening the
/// sheet, and is cleared once the expense is saved (FR-010c).
final pasteDraftTextProvider = StateProvider<String>((ref) => '');

const maxPasteTextLength = 4000;

/// Opens the "Paste text" sheet; returns the AI proposal, or null when the
/// user cancelled.
Future<ExpenseTextOrganizeResult?> showPasteOrganizeSheet(
  BuildContext context, {
  required String workspaceId,
  required String currency,
}) {
  return showModalBottomSheet<ExpenseTextOrganizeResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        PasteOrganizeSheet(workspaceId: workspaceId, currency: currency),
  );
}

/// Paste receipt text and "Organize with AI" (spec Story 2b).
class PasteOrganizeSheet extends ConsumerStatefulWidget {
  const PasteOrganizeSheet({
    required this.workspaceId,
    required this.currency,
    super.key,
  });

  final String workspaceId;
  final String currency;

  @override
  ConsumerState<PasteOrganizeSheet> createState() => _PasteOrganizeSheetState();
}

class _PasteOrganizeSheetState extends ConsumerState<PasteOrganizeSheet> {
  late final _textController = TextEditingController(
    text: ref.read(pasteDraftTextProvider),
  );
  bool _running = false;
  String? _error;

  /// Bumped on cancel so a late response is ignored.
  int _attempt = 0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _organize() async {
    final l10n = AppLocalizations.of(context);
    final accepted = await ensureAiDisclosureAccepted(
      context,
      ref.read(voiceAiDisclosureStoreProvider),
    );
    if (!accepted || !mounted) return;
    final attempt = ++_attempt;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(expenseTextOrganizerProvider)
          .organize(
            workspaceId: widget.workspaceId,
            text: _textController.text.trim(),
            currency: widget.currency,
          );
      if (!mounted || attempt != _attempt) return;
      if (result.proposal.items.isEmpty) {
        setState(() {
          _running = false;
          _error = l10n.t('organizeNoItemsFound');
        });
        return;
      }
      Navigator.of(context).pop(result);
    } on CallableClientException catch (error) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _running = false;
        _error = error.message.trim().isEmpty
            ? l10n.t('unexpectedErrorTryAgain')
            : error.message;
      });
    } catch (_) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _running = false;
        _error = l10n.t('unexpectedErrorTryAgain');
      });
    }
  }

  void _cancel() {
    _attempt++;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final offline = ref.watch(isOfflineProvider);
    final hasText = _textController.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('pasteText'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('qa_paste_text'),
            controller: _textController,
            enabled: !_running,
            minLines: 4,
            maxLines: 10,
            maxLength: maxPasteTextLength,
            keyboardType: TextInputType.multiline,
            onChanged: (value) {
              ref.read(pasteDraftTextProvider.notifier).state = value;
              setState(() => _error = null);
            },
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          if (offline) ...[
            const SizedBox(height: 4),
            Text(
              l10n.t('organizeOfflineHint'),
              key: const Key('qa_organize_offline'),
              style: TextStyle(fontSize: 13, color: t.warning),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              key: const Key('qa_organize_error'),
              style: TextStyle(fontSize: 13, color: t.expense),
            ),
          ],
          const SizedBox(height: 12),
          if (_running)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.t('organizing'))),
                TextButton(
                  key: const Key('qa_organize_cancel'),
                  onPressed: _cancel,
                  child: Text(l10n.t('cancel')),
                ),
              ],
            )
          else
            FilledButton.icon(
              key: const Key('qa_organize_ai'),
              onPressed: hasText && !offline ? _organize : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.t('organizeWithAi')),
            ),
        ],
      ),
    );
  }
}
