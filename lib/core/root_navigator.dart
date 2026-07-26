import 'package:flutter/material.dart';

/// [SessionMonitor] wraps [MaterialApp], so it must not use its own [BuildContext]
/// for [Navigator] or [showDialog]. Attach this key to [MaterialApp.navigatorKey].
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Attach to [MaterialApp.scaffoldMessengerKey] so SnackBars show above nested [Scaffold]s
/// (e.g. main tab navigation + Student Management).
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Prefer the app-wide messenger; fallback to [context] if the key is not mounted yet.
ScaffoldMessengerState scaffoldMessengerOr(BuildContext context) {
  final root = rootScaffoldMessengerKey.currentState;
  if (root != null) return root;
  return ScaffoldMessenger.of(context);
}
