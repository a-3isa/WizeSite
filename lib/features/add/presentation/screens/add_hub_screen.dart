import 'package:buildtrack_app/app/localization/app_localizations.dart';
import 'package:buildtrack_app/core/constants/app_colors.dart';
import 'package:buildtrack_app/core/constants/app_routes.dart';
import 'package:buildtrack_app/core/prefetch/app_prefetcher.dart';
import 'package:buildtrack_app/core/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddHubScreen extends ConsumerStatefulWidget {
  const AddHubScreen({super.key});

  @override
  ConsumerState<AddHubScreen> createState() => _AddHubScreenState();
}

class _AddHubScreenState extends ConsumerState<AddHubScreen> {
  bool _launching = false;

  Future<void> _open(String route, VoidCallback warm) async {
    if (_launching) return;
    setState(() => _launching = true);
    warm();
    await context.push(route);
    if (mounted) setState(() => _launching = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefetcher = ref.read(appPrefetcherProvider);
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Text(
                  l10n.t('quickAdd'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),
                  SectionHeader(title: l10n.t('expenses')),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_expense'),
                    icon: Icons.receipt_long_outlined,
                    title: l10n.t('addExpense'),
                    subtitle: l10n.t('addExpenseSubtitle'),
                    color: AppColors.danger,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(AppRoutes.addExpense, prefetcher.warmAddEntry);
                    },
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: l10n.t('payments')),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_payment'),
                    icon: Icons.payments_outlined,
                    title: l10n.t('addPayment'),
                    subtitle: l10n.t('addPaymentSubtitle'),
                    color: AppColors.success,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(AppRoutes.addPayment, prefetcher.warmAddEntry);
                    },
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: l10n.t('workers')),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_worker'),
                    icon: Icons.person_add_outlined,
                    title: l10n.t('addWorkerTitle'),
                    subtitle: l10n.t('addWorkerSubtitle'),
                    color: AppColors.constructionOrange,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(AppRoutes.addWorker, prefetcher.warmAddEntry);
                    },
                  ),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_workers'),
                    icon: Icons.engineering_outlined,
                    title: l10n.t('workerList'),
                    subtitle: l10n.t('workerListSubtitle'),
                    color: AppColors.constructionOrange,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(AppRoutes.workers, prefetcher.warmProjects);
                    },
                  ),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_worker_entry'),
                    icon: Icons.assignment_ind_outlined,
                    title: l10n.t('addWorkerEntry'),
                    subtitle: l10n.t('addWorkerEntrySubtitle'),
                    color: AppColors.constructionOrange,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open('/worker-entry/new', prefetcher.warmAddEntry);
                    },
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: l10n.t('voiceExpense')),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_voice_expense'),
                    icon: Icons.mic_outlined,
                    title: l10n.t('voiceExpense'),
                    subtitle: l10n.t('voiceExpenseSubtitle'),
                    color: AppColors.constructionOrange,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(AppRoutes.voiceExpense, prefetcher.warmAddEntry);
                    },
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(title: l10n.t('resources')),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_workers_directory'),
                    icon: Icons.engineering_outlined,
                    title: l10n.t('workerDirectory'),
                    subtitle: l10n.t('workerDirectorySubtitle'),
                    color: AppColors.constructionOrange,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(AppRoutes.workers, prefetcher.warmProjects);
                    },
                  ),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_contractors_directory'),
                    icon: Icons.groups_2_outlined,
                    title: l10n.t('contractorsDirectory'),
                    subtitle: l10n.t('contractorsDirectorySubtitle'),
                    color: AppColors.textDark,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(
                        AppRoutes.contractorsDirectory,
                        prefetcher.warmProjects,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_equipment_directory'),
                    icon: Icons.precision_manufacturing_outlined,
                    title: l10n.t('equipmentDirectory'),
                    subtitle: l10n.t('equipmentDirectorySubtitle'),
                    color: AppColors.warning,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(
                        AppRoutes.equipmentDirectory,
                        prefetcher.warmProjects,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _ActionCard(
                    qaKey: const Key('qa_add_hub_transport_directory'),
                    icon: Icons.local_shipping_outlined,
                    title: l10n.t('transportDirectory'),
                    subtitle: l10n.t('transportDirectorySubtitle'),
                    color: AppColors.success,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _open(
                        AppRoutes.transportProvidersDirectory,
                        prefetcher.warmProjects,
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    this.qaKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final Key? qaKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      button: true,
      excludeSemantics: true,
      child: Material(
        key: qaKey,
        color: AppColors.surfaceSolid,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textBody,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textBody.withValues(alpha: 0.6),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
