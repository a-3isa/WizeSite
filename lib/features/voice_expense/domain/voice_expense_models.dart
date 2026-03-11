class VoiceProjectOption {
  const VoiceProjectOption({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, String> toMap() => <String, String>{'id': id, 'name': name};
}

class VoiceParsedExpense {
  const VoiceParsedExpense({
    required this.amount,
    required this.currency,
    required this.category,
    required this.matchedProjectId,
    required this.matchedProjectName,
    required this.note,
  });

  final double? amount;
  final String? currency;
  final String? category;
  final String? matchedProjectId;
  final String? matchedProjectName;
  final String? note;

  VoiceParsedExpense copyWith({
    double? amount,
    String? currency,
    String? category,
    String? matchedProjectId,
    String? matchedProjectName,
    String? note,
  }) {
    return VoiceParsedExpense(
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      matchedProjectId: matchedProjectId ?? this.matchedProjectId,
      matchedProjectName: matchedProjectName ?? this.matchedProjectName,
      note: note ?? this.note,
    );
  }

  factory VoiceParsedExpense.fromMap(Map<String, dynamic> map) {
    return VoiceParsedExpense(
      amount: (map['amount'] as num?)?.toDouble(),
      currency: map['currency'] as String?,
      category: map['category'] as String?,
      matchedProjectId: map['matchedProjectId'] as String?,
      matchedProjectName: map['matchedProjectName'] as String?,
      note: map['note'] as String?,
    );
  }
}

class VoiceConfidenceScores {
  const VoiceConfidenceScores({
    required this.amount,
    required this.category,
    required this.project,
    required this.overall,
  });

  final double amount;
  final double category;
  final double project;
  final double overall;

  factory VoiceConfidenceScores.fromMap(Map<String, dynamic> map) {
    return VoiceConfidenceScores(
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      category: (map['category'] as num?)?.toDouble() ?? 0,
      project: (map['project'] as num?)?.toDouble() ?? 0,
      overall: (map['overall'] as num?)?.toDouble() ?? 0,
    );
  }
}

class VoiceExpenseParseResponse {
  const VoiceExpenseParseResponse({
    required this.transcript,
    required this.parsed,
    required this.confidence,
    required this.source,
    required this.needsConfirmation,
    required this.storagePath,
  });

  final String transcript;
  final VoiceParsedExpense parsed;
  final VoiceConfidenceScores confidence;
  final String source;
  final bool needsConfirmation;
  final String storagePath;

  factory VoiceExpenseParseResponse.fromMap(Map<String, dynamic> map) {
    return VoiceExpenseParseResponse(
      transcript: map['transcript'] as String? ?? '',
      parsed: VoiceParsedExpense.fromMap(
        (map['parsed'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      confidence: VoiceConfidenceScores.fromMap(
        (map['confidence'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      source: map['source'] as String? ?? 'rules',
      needsConfirmation: map['needsConfirmation'] as bool? ?? true,
      storagePath: map['storagePath'] as String? ?? '',
    );
  }
}
