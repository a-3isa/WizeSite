import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void appNavigateBack(
  BuildContext context, {
  required String fallbackRoute,
  Object? result,
}) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop(result);
    return;
  }
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop(result);
    return;
  }
  context.go(fallbackRoute);
}

class AppBackScope extends StatelessWidget {
  const AppBackScope({
    required this.fallbackRoute,
    required this.child,
    super.key,
  });

  final String fallbackRoute;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        appNavigateBack(context, fallbackRoute: fallbackRoute, result: result);
      },
      child: child,
    );
  }
}

class AppBackButton extends StatelessWidget {
  const AppBackButton({required this.fallbackRoute, super.key});

  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const BackButtonIcon(),
      onPressed: () => appNavigateBack(context, fallbackRoute: fallbackRoute),
    );
  }
}

PreferredSizeWidget appBackAppBar({
  required BuildContext context,
  required String title,
  required String fallbackRoute,
  List<Widget>? actions,
  bool centerTitle = false,
  Color? backgroundColor,
  double? elevation,
}) {
  return AppBar(
    leading: AppBackButton(fallbackRoute: fallbackRoute),
    title: Text(title),
    actions: actions,
    centerTitle: centerTitle,
    backgroundColor: backgroundColor,
    elevation: elevation,
  );
}
