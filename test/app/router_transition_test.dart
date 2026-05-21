import 'package:buildtrack_app/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('smoothAppPage creates a short transition page', () {
    final CustomTransitionPage<void> page = smoothAppPage<void>(
      key: const ValueKey('home'),
      child: const Text('Home'),
    );

    expect(page, isA<CustomTransitionPage<void>>());
    expect(
      page.transitionDuration,
      lessThanOrEqualTo(const Duration(milliseconds: 180)),
    );
  });
}
