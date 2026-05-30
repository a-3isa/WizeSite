enum AccountingAccessRoleType {
  owner('owner'),
  admin('admin'),
  accountingApproved('accountingApproved'),
  member('member'),
  entryOnly('entryOnly');

  const AccountingAccessRoleType(this.value);

  final String value;

  bool get canAccessAccounting {
    return switch (this) {
      AccountingAccessRoleType.owner ||
      AccountingAccessRoleType.admin ||
      AccountingAccessRoleType.accountingApproved => true,
      AccountingAccessRoleType.member ||
      AccountingAccessRoleType.entryOnly => false,
    };
  }

  static AccountingAccessRoleType fromValue(Object? raw) {
    final value = raw as String?;
    if (value == null || value.isEmpty) {
      return AccountingAccessRoleType.member;
    }
    return AccountingAccessRoleType.values.firstWhere(
      (role) => role.value == value,
      orElse: () => AccountingAccessRoleType.member,
    );
  }
}

class AccountingAccessRole {
  const AccountingAccessRole({
    required this.workspaceId,
    required this.userId,
    required this.role,
    this.grantedAt,
    this.grantedBy,
  });

  final String workspaceId;
  final String userId;
  final AccountingAccessRoleType role;
  final DateTime? grantedAt;
  final String? grantedBy;

  bool get canAccessAccounting => role.canAccessAccounting;

  factory AccountingAccessRole.fromMap(Map<String, dynamic> map) {
    return AccountingAccessRole(
      workspaceId: map['workspaceId'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      role: AccountingAccessRoleType.fromValue(map['role']),
      grantedAt: _parseDate(map['grantedAt']),
      grantedBy: (map['grantedBy'] as String?)?.isNotEmpty == true
          ? map['grantedBy'] as String?
          : null,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'workspaceId': workspaceId,
      'userId': userId,
      'role': role.value,
      if (grantedAt != null) 'grantedAt': grantedAt!.toIso8601String(),
      if (grantedBy != null && grantedBy!.isNotEmpty) 'grantedBy': grantedBy,
    };
  }
}
