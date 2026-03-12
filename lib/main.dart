import 'package:buildtrack_app/app/app.dart';
import 'package:buildtrack_app/core/services/firebase_initializer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await FirebaseInitializer.ensureInitialized();
  runApp(const ProviderScope(child: BuildozerApp()));
}
