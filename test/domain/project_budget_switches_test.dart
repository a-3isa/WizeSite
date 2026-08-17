import 'package:buildtrack_app/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the two derived switches that drive every budget- and revenue-
/// dependent widget in the app: `hasBudget` (does spending have a baseline to
/// be measured against?) and `isExpenseLedger` (does the project have a
/// contract, and therefore a revenue side?).
///
/// These getters replaced three divergent copies of the same rule that lived in
/// the project detail screen, the dashboard, and the project list. Testing them
/// here is what keeps those three surfaces from drifting apart again.
Project buildProject({double? contractValue, double? budgetLimit}) {
  return Project(
    id: 'project_1',
    workspaceId: 'workspace_1',
    name: 'Tower A',
    clientName: 'Client',
    contractValue: contractValue,
    status: 'active',
    completionPercentage: 0,
    totalExpenses: 0,
    totalPayments: 0,
    netProfit: 0,
    isArchived: false,
    budgetLimit: budgetLimit,
  );
}

void main() {
  group('Project budget baseline and expense-ledger switches', () {
    test('contract only: budget measured against the contract, revenue shown', () {
      final project = buildProject(contractValue: 50000);

      expect(project.hasContractValue, isTrue);
      expect(project.budgetBase, 50000);
      expect(project.hasBudget, isTrue);
      expect(project.isExpenseLedger, isFalse);
      // The project list card keys off this narrower rule and must NOT start
      // showing a budget bar for a contract-only project (FR-018).
      expect(project.hasBudgetLimit, isFalse);
    });

    test('budget limit overrides the contract as the spending baseline', () {
      final project = buildProject(contractValue: 50000, budgetLimit: 30000);

      expect(project.budgetBase, 30000);
      expect(project.hasBudget, isTrue);
      expect(project.isExpenseLedger, isFalse);
      expect(project.hasBudgetLimit, isTrue);
    });

    test(
      'budget limit without a contract: budget widgets shown, revenue hidden',
      () {
        final project = buildProject(budgetLimit: 30000);

        expect(project.hasContractValue, isFalse);
        expect(project.budgetBase, 30000);
        // The two switches are independent: a spending budget with no income
        // expected is a coherent, intended combination.
        expect(project.hasBudget, isTrue);
        expect(project.isExpenseLedger, isTrue);
      },
    );

    test('neither set: pure expense ledger, no baseline at all', () {
      final project = buildProject();

      expect(project.hasContractValue, isFalse);
      expect(project.budgetBase, isNull);
      expect(project.hasBudget, isFalse);
      expect(project.isExpenseLedger, isTrue);
      expect(project.hasBudgetLimit, isFalse);
    });

    test('zero is treated as absent, not as a real agreed amount', () {
      final project = buildProject(contractValue: 0, budgetLimit: 0);

      expect(project.hasContractValue, isFalse);
      expect(project.budgetBase, isNull);
      expect(project.hasBudget, isFalse);
      expect(project.isExpenseLedger, isTrue);
    });
  });

  group('Project.fromMap contract value parsing', () {
    test('a stored zero loads as null, never as a real amount', () {
      final project = Project.fromMap('project_1', {
        'workspaceId': 'workspace_1',
        'name': 'Tower A',
        'contractValue': 0,
      });

      // A `?? 0` fallback anywhere on this path would silently defeat the whole
      // feature, so this assertion is deliberately about null and not falsiness.
      expect(project.contractValue, isNull);
      expect(project.hasContractValue, isFalse);
      expect(project.isExpenseLedger, isTrue);
    });

    test('a missing contract value loads as null', () {
      final project = Project.fromMap('project_1', {
        'workspaceId': 'workspace_1',
        'name': 'Tower A',
      });

      expect(project.contractValue, isNull);
      expect(project.isExpenseLedger, isTrue);
    });

    test('a real contract value survives the round trip unchanged', () {
      final project = Project.fromMap('project_1', {
        'workspaceId': 'workspace_1',
        'name': 'Tower A',
        'contractValue': 50000,
      });

      expect(project.contractValue, 50000);
      expect(project.hasContractValue, isTrue);
      expect(project.isExpenseLedger, isFalse);
    });
  });

  group('no ratio is computed without a baseline', () {
    // FR-024: the calculation must be skipped entirely rather than guarded
    // after the fact, so a NaN or Infinity can never reach a widget.
    test('spend ratio is never derived when budgetBase is null', () {
      final project = buildProject();
      project.totalExpenses;

      expect(project.budgetBase, isNull);
      expect(project.hasBudget, isFalse);

      // Mirrors how every consumer guards: the division is unreachable while
      // hasBudget is false, so no NaN/Infinity value can be produced.
      final ratio = project.hasBudget
          ? project.totalExpenses / project.budgetBase!
          : 0.0;
      expect(ratio, 0.0);
      expect(ratio.isNaN, isFalse);
      expect(ratio.isInfinite, isFalse);
    });

    test('an over-budget verdict is impossible without a baseline', () {
      final project = Project(
        id: 'project_1',
        workspaceId: 'workspace_1',
        name: 'Tower A',
        clientName: 'Client',
        contractValue: null,
        status: 'active',
        completionPercentage: 0,
        totalExpenses: 999999,
        totalPayments: 0,
        netProfit: -999999,
        isArchived: false,
      );

      expect(project.hasBudget, isFalse);
      final overBudget =
          project.hasBudget && project.totalExpenses > project.budgetBase!;
      expect(overBudget, isFalse);
    });
  });
}
