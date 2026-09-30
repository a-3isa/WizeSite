import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings danger actions use expenseSoft, not a light-only AppColors fill', () {
    final settings = File(
      'lib/features/settings/presentation/screens/settings_screen.dart',
    ).readAsStringSync();

    expect(settings, isNot(contains('AppColors.dangerLight')));
    expect(settings, isNot(contains('package:buildtrack_app/core/constants/app_colors.dart')));
    expect(settings, contains('context.tokens.expenseSoft'));
  });
}
