import 'dart:async';

import 'package:buildtrack_app/features/entities/data/entity_repository.dart';
import 'package:buildtrack_app/features/entities/domain/entity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EntityAutocompleteField extends ConsumerStatefulWidget {
  const EntityAutocompleteField({
    required this.workspaceId,
    required this.label,
    required this.onChanged,
    this.entityType,
    this.initialEntityId,
    this.initialEntityName,
    super.key,
  });

  final String workspaceId;
  final String label;
  final String? entityType;
  final String? initialEntityId;
  final String? initialEntityName;
  final void Function(String? entityId, String? entityName) onChanged;

  @override
  ConsumerState<EntityAutocompleteField> createState() => _EntityAutocompleteFieldState();
}

class _EntityAutocompleteFieldState extends ConsumerState<EntityAutocompleteField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<AppEntity> _suggestions = [];
  Timer? _debounce;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEntityName ?? '');
    _selectedId = widget.initialEntityId;
    _fetchSuggestions(_controller.text);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _suggestions = [];
        _selectedId = null;
      });
      widget.onChanged(null, null);
      return;
    }
    if (_selectedId != null && widget.initialEntityName != null && text != widget.initialEntityName) {
      _selectedId = null;
    }
    widget.onChanged(_selectedId, text);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(text);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        setState(() => _suggestions = []);
      }
      return;
    }

    try {
      final results = await ref
          .read(entityRepositoryProvider)
          .searchEntities(widget.workspaceId, trimmed, type: widget.entityType, limit: 10);
      if (!mounted) return;
      setState(() => _suggestions = results);
    } catch (_) {
      if (mounted) {
        setState(() => _suggestions = []);
      }
    }
  }

  void _selectSuggestion(AppEntity entity) {
    _controller.text = entity.name;
    _selectedId = entity.id;
    _focusNode.unfocus();
    setState(() {
      _suggestions = [];
    });
    widget.onChanged(entity.id, entity.name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(labelText: widget.label),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _suggestions.map((entity) {
                return ListTile(
                  title: Text(entity.name),
                  subtitle: entity.type.isNotEmpty ? Text(entity.type) : null,
                  onTap: () => _selectSuggestion(entity),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
