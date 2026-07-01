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
    this.showAllOnEmpty = false,
    super.key,
  });

  final String workspaceId;
  final String label;
  final String? entityType;
  final String? initialEntityId;
  final String? initialEntityName;
  final bool showAllOnEmpty;
  final void Function(String? entityId, String? entityName) onChanged;

  @override
  ConsumerState<EntityAutocompleteField> createState() =>
      _EntityAutocompleteFieldState();
}

class _EntityAutocompleteFieldState
    extends ConsumerState<EntityAutocompleteField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<AppEntity> _suggestions = [];
  Timer? _debounce;
  String? _selectedId;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEntityName ?? '');
    _selectedId = widget.initialEntityId;
    _fetchSuggestions(_controller.text);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    _debounce?.cancel();
    if (text.isEmpty) {
      _requestVersion++;
      setState(() {
        _selectedId = null;
        if (!widget.showAllOnEmpty) {
          _suggestions = [];
        }
      });
      widget.onChanged(null, null);
      if (widget.showAllOnEmpty && _focusNode.hasFocus) {
        _fetchSuggestions('');
      }
      return;
    }
    if (_selectedId != null &&
        widget.initialEntityName != null &&
        text != widget.initialEntityName) {
      _selectedId = null;
    }
    widget.onChanged(_selectedId, text);
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(text);
    });
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && widget.showAllOnEmpty) {
      _fetchSuggestions(_controller.text);
    }
  }

  Future<void> _fetchSuggestions(String query) async {
    final requestVersion = ++_requestVersion;
    final trimmed = query.trim();
    if (trimmed.isEmpty && !widget.showAllOnEmpty) {
      if (mounted) {
        setState(() => _suggestions = []);
      }
      return;
    }

    try {
      final results = await ref
          .read(entityRepositoryProvider)
          .searchEntities(
            widget.workspaceId,
            trimmed,
            type: widget.entityType,
            limit: 10,
          );
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() => _suggestions = results);
    } catch (_) {
      if (mounted && requestVersion == _requestVersion) {
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
            child: Material(
              color: Theme.of(context).cardColor,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Theme.of(context).dividerColor),
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
          ),
      ],
    );
  }
}
