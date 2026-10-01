import 'package:buildtrack_app/core/services/email_auth_service.dart';
import 'package:buildtrack_app/core/services/google_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService();
});

final emailAuthServiceProvider = Provider<EmailAuthService>((ref) {
  return const EmailAuthService();
});

final googleSignInSupportedProvider = FutureProvider<bool>((ref) async {
  return ref.read(googleAuthServiceProvider).isSupported;
});
