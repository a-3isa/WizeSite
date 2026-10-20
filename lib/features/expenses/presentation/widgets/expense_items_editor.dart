import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/app/theme/build_tokens.dart';
import 'package:buildtrack_app/core/utils/thousands_separator_input_formatter.dart';
import 'package:buildtrack_app/features/expenses/domain/expense_item_draft.dart';
import 'package:flutter/material.dart';

export 'package:buildtrack_app/features/expenses/domain/expense_item_draft.dart';

/// Maximum items per expense (matches the server CHECK, data-model.md §2).
const maxExpenseItems = 100;

/// State of an [ExpenseItemsEditor]: the ordered rows, validation marks and
/// whether the user has touched them. Never empty: there is always one row.
class ExpenseItemsEditorController extends ChangeNotifier {
  ExpenseItemsEditorController([List<ExpenseItemDraft>? initial])
    : _rows = initial == null || initial.isEmpty
          ? [ExpenseItemDraft()]
          : List.of(initial);

  List<ExpenseItemDraft> _rows;
  final _invalidIds = <String>{};
  bool _hasUserEdits = false;
  bool _blockedLastRemoval = false;

  List<ExpenseItemDraft> get items => List.unmodifiable(_rows);
  int get length => _rows.length;
  bool get hasUserEdits => _hasUserEdits;
  Set<String> get invalidIds => Set.unmodifiable(_invalidIds);
  bool get canAdd => _rows.length < maxExpenseItems;

  /// True once after a refused removal of the last row (the editor shows a
  /// message and resets it).
  bool takeBlockedLastRemoval() {
    final value = _blockedLastRemoval;
    _blockedLastRemoval = false;
    return value;
  }

  /// A single row nobody has typed into, which a proposal may replace.
  bool get isPristine => _rows.length == 1 && _rows.first.isBlank;

  /// Sum of the valid amounts, added in whole piastres.
  double get total {
    var piastres = 0;
    for (final row in _rows) {
      piastres += ((row.amount ?? 0) * 100).round();
    }
    return piastres / 100;
  }

  /// Replaces every row (edit-mode seed, duplicate seed). Not a user edit.
  void replaceAll(List<ExpenseItemDraft> rows) {
    _rows = rows.isEmpty ? [ExpenseItemDraft()] : List.of(rows);
    _invalidIds.clear();
    notifyListeners();
  }

  /// Adds proposal rows after the existing ones; a pristine single row is
  /// replaced instead of kept (research R7).
  void appendItems(List<ExpenseItemDraft> rows) {
    if (rows.isEmpty) return;
    final kept = isPristine ? <ExpenseItemDraft>[] : _rows;
    _rows = [...kept, ...rows].take(maxExpenseItems).toList();
    notifyListeners();
  }

  void add() {
    if (!canAdd) return;
    _rows = [..._rows, ExpenseItemDraft()];
    _hasUserEdits = true;
    notifyListeners();
  }

  /// Returns false (and keeps the row) when it is the last one.
  bool removeAt(int index) {
    if (_rows.length <= 1) {
      _blockedLastRemoval = true;
      notifyListeners();
      return false;
    }
    _invalidIds.remove(_rows[index].id);
    _rows = [..._rows]..removeAt(index);
    _hasUserEdits = true;
    notifyListeners();
    return true;
  }

  /// [newIndex] is the final position (already adjusted for the removal, as
  /// ReorderableListView.onReorderItem reports it).
  void reorder(int oldIndex, int newIndex) {
    final rows = [..._rows];
    final row = rows.removeAt(oldIndex);
    rows.insert(newIndex.clamp(0, rows.length), row);
    _rows = rows;
    _hasUserEdits = true;
    notifyListeners();
  }

  /// A user edit of one row: clears its review flag and validation mark.
  void updateRow(int index, ExpenseItemDraft row) {
    _rows = [..._rows]..[index] = row.copyWith(needsReview: false);
    _invalidIds.remove(row.id);
    _hasUserEdits = true;
    notifyListeners();
  }

  /// Rate × quantity for resource categories writes the single row's amount.
  void setFirstItemAmount(double amount) {
    if (_rows.length != 1) return;
    _rows = [
      _rows.first.copyWith(
        amountText: ThousandsSeparatorInputFormatter.formatInitial(
          amount.toStringAsFixed(2),
        ),
      ),
    ];
    notifyListeners();
  }

  void setFirstItemQuantity(String quantityText) {
    if (_rows.isEmpty) return;
    _rows = [..._rows]..[0] = _rows.first.copyWith(quantityText: quantityText);
    notifyListeners();
  }

  /// Marks every row missing a name or a positive amount (or still flagged by
  /// the AI); returns whether all rows are valid.
  bool validate() {
    _invalidIds
      ..clear()
      ..addAll(
        _rows.where((r) => !r.isValid || r.needsReview).map((r) => r.id),
      );
    notifyListeners();
    return _invalidIds.isEmpty;
  }

  List<Map<String, dynamic>> toItemMaps() =>
      _rows.map((r) => r.toItemMap()).toList();
}

/// Receipt line items: one row per item with name + amount (quantity and note
/// behind an expand control), add / remove / reorder, live total and inline
/// validation (spec FR-006/FR-007, research R10).
class ExpenseItemsEditor extends StatefulWidget {
  const ExpenseItemsEditor({
    required this.controller,
    required this.currency,
    this.onChanged,
    super.key,
  });

  final ExpenseItemsEditorController controller;
  final String currency;
  final ValueChanged<List<ExpenseItemDraft>>? onChanged;

  @override
  State<ExpenseItemsEditor> createState() => _ExpenseItemsEditorState();
}

class _RowFields {
  _RowFields(ExpenseItemDraft row)
    : name = TextEditingController(text: row.name),
      amount = TextEditingController(text: row.amountText),
      quantity = TextEditingController(text: row.quantityText),
      note = TextEditingController(text: row.note);

  final TextEditingController name;
  final TextEditingController amount;
  final TextEditingController quantity;
  final TextEditingController note;
  bool expanded = false;

  void sync(ExpenseItemDraft row) {
    void set(TextEditingController c, String value) {
      if (c.text != value) c.text = value;
    }

    set(name, row.name);
    set(amount, row.amountText);
    set(quantity, row.quantityText);
    set(note, row.note);
  }

  void dispose() {
    name.dispose();
    amount.dispose();
    quantity.dispose();
    note.dispose();
  }
}

class _ExpenseItemsEditorState extends State<ExpenseItemsEditor> {
  final _fields = <String, _RowFields>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncFields();
  }

  @override
  void didUpdateWidget(ExpenseItemsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _syncFields();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final fields in _fields.values) {
      fields.dispose();
    }
    super.dispose();
  }

  void _syncFields() {
    final rows = widget.controller.items;
    final ids = rows.map((r) => r.id).toSet();
    for (final id in _fields.keys.where((id) => !ids.contains(id)).toList()) {
      _fields.remove(id)!.dispose();
    }
    for (final row in rows) {
      (_fields[row.id] ??= _RowFields(row)).sync(row);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(_syncFields);
    widget.onChanged?.call(widget.controller.items);
    if (widget.controller.takeBlockedLastRemoval()) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.t('cannotRemoveLastItem'))));
    }
  }

  void _edit(int index, ExpenseItemDraft Function(ExpenseItemDraft) change) {
    widget.controller.updateRow(index, change(widget.controller.items[index]));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final controller = widget.controller;
    final rows = controller.items;
    final total = ThousandsSeparatorInputFormatter.formatInitial(
      controller.total.toStringAsFixed(2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('expenseItems'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: rows.length,
          onReorderItem: controller.reorder,
          itemBuilder: (context, index) {
            final row = rows[index];
            return _ItemRow(
              key: ValueKey(row.id),
              index: index,
              row: row,
              fields: _fields[row.id]!,
              invalid: controller.invalidIds.contains(row.id),
              onName: (v) => _edit(index, (r) => r.copyWith(name: v)),
              onAmount: (v) => _edit(index, (r) => r.copyWith(amountText: v)),
              onQuantity: (v) =>
                  _edit(index, (r) => r.copyWith(quantityText: v)),
              onNote: (v) => _edit(index, (r) => r.copyWith(note: v)),
              onRemove: () => controller.removeAt(index),
              onToggleExpanded: () => setState(() {
                final fields = _fields[row.id]!;
                fields.expanded = !fields.expanded;
              }),
            );
          },
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('qa_items_add'),
            onPressed: controller.canAdd ? controller.add : null,
            icon: const Icon(Icons.add),
            label: Text(l10n.t('addItem')),
          ),
        ),
        Container(
          key: const Key('qa_items_total'),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: t.expenseSoft,
            borderRadius: t.radiusMd,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('itemsTotal'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: t.text),
                ),
              ),
              Text(
                '$total ${widget.currency}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: t.expense,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.row,
    required this.fields,
    required this.invalid,
    required this.onName,
    required this.onAmount,
    required this.onQuantity,
    required this.onNote,
    required this.onRemove,
    required this.onToggleExpanded,
    super.key,
  });

  final int index;
  final ExpenseItemDraft row;
  final _RowFields fields;
  final bool invalid;
  final ValueChanged<String> onName;
  final ValueChanged<String> onAmount;
  final ValueChanged<String> onQuantity;
  final ValueChanged<String> onNote;
  final VoidCallback onRemove;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = context.tokens;
    final flagged = row.needsReview;
    final nameError = invalid && row.name.trim().isEmpty
        ? l10n.t('itemNameRequired')
        : null;
    final amountError = invalid && (row.amount ?? 0) <= 0
        ? l10n.t('itemAmountRequired')
        : null;
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.radiusMd,
        border: Border.all(
          color: invalid || flagged ? t.warning : t.border,
          width: invalid || flagged ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (flagged)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 16, color: t.warning),
                  const SizedBox(width: 4),
                  Text(
                    l10n.t('itemNeedsReview'),
                    key: Key('qa_item_review_$index'),
                    style: TextStyle(fontSize: 12, color: t.warning),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: 12),
                  child: Icon(Icons.drag_indicator, color: t.textFaint),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 3,
                child: TextField(
                  key: Key('qa_item_name_$index'),
                  controller: fields.name,
                  onChanged: onName,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.t('itemName'),
                    errorText: nameError,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: Key('qa_item_amount_$index'),
                  controller: fields.amount,
                  onChanged: onAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [ThousandsSeparatorInputFormatter()],
                  decoration: InputDecoration(
                    labelText: l10n.t('itemAmount'),
                    errorText: amountError,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: Key('qa_item_expand_$index'),
                tooltip: l10n.t('itemNoteOptional'),
                onPressed: onToggleExpanded,
                icon: Icon(
                  fields.expanded ? Icons.expand_less : Icons.expand_more,
                ),
              ),
              IconButton(
                key: Key('qa_item_remove_$index'),
                tooltip: l10n.t('delete'),
                onPressed: onRemove,
                icon: Icon(Icons.delete_outline, color: t.textMuted),
              ),
            ],
          ),
          if (fields.expanded)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(28, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('qa_item_quantity_$index'),
                      controller: fields.quantity,
                      onChanged: onQuantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.t('itemQuantityOptional'),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: Key('qa_item_note_$index'),
                      controller: fields.note,
                      onChanged: onNote,
                      maxLength: 200,
                      decoration: InputDecoration(
                        labelText: l10n.t('itemNoteOptional'),
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
