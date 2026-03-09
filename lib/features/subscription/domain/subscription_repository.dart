import 'package:buildtrack_app/features/subscription/domain/subscription_models.dart';

abstract interface class SubscriptionRepository {
  Stream<SubscriptionState> watchSubscription(String workspaceId);
  Future<SubscriptionState> getSubscription(String workspaceId);
}
