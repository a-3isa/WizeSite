import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const supportedLocales = <Locale>[Locale('ar'), Locale('en')];

  static Map<String, Map<String, String>> get localizedValues => _localized;

  static Set<String> get requiredKeys => _en.keys.toSet();

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return value ?? AppLocalizations(const Locale('en'));
  }

  static final _en = <String, String>{
    'appName': 'Buildozer',
    'tagline': 'Smart Construction Management',
    'home': 'Home',
    'projects': 'Projects',
    'add': 'Add',
    'reports': 'Reports',
    'reportAccessDenied':
        'You do not have permission to view financial reports, balances, or attachments.',
    'reportExportFailed':
        'Could not create the PDF. Check your connection and try again.',
    'settings': 'Settings',
    'subscription': 'Subscription',
    'upgradeToPro': 'Upgrade to Pro',
    'freePlan': 'Free Plan',
    'proPlan': 'Pro Plan',
    'monthlyUsage': 'Monthly Usage',
    'activeProjects': 'Active Projects',
    'expenses': 'Expenses',
    'payments': 'Payments',
    'workerEntries': 'Worker Entries',
    'planAndBilling': 'Plan & Billing',
    'manageSubscription': 'Manage Subscription',
    'restorePurchases': 'Restore Purchases',
    'logout': 'Logout',
    'profile': 'Profile',
    'editProfile': 'Edit Profile',
    'changePhoto': 'Change Photo',
    'manageTeam': 'Manage Team',
    'teamManagement': 'Team Management',
    'teamMembersTitle': 'Team Members',
    'noTeamMembersYet': 'No team members yet.',
    'inviteMember': 'Invite Member',
    'inviteByEmail': 'Invite by email',
    'role': 'Role',
    'memberRole': 'Member',
    'ownerRole': 'Owner',
    'adminRole': 'Admin',
    'accountingApprovedRole': 'Accounting approved',
    'entryOnlyRole': 'Entry only',
    'workspaceCrewTitle': 'Workspace Crew',
    'allProjectsOption': 'All Projects',
    'all': 'All',
    'allStatuses': 'All statuses',
    'projectSortRecent': 'Recent',
    'projectSortName': 'Name',
    'projectSortHighestExpense': 'Highest expense',
    'projectSortHighestIncome': 'Highest income',
    'projectSortHighestNet': 'Highest net',
    'projectFinancialAccessRestricted':
        'Financial project details are restricted for your role.',
    'confirmArchiveProject': 'Archive this project?',
    'selectProject': 'Select a Project',
    'allProjects': 'All Projects',
    'searchProjects': 'Search projects',
    'noProjectsMatchSearch': 'No projects match your search.',
    'showingDataForProject': 'Showing data for {project} only',
    'selectProjectToViewReport': 'Please select a project to view its report.',
    'projectReport': 'Project Report',
    'generatedByBuildozer': 'Generated securely by Buildozer',
    'notificationTargetedFeed': 'Recent workspace alerts for you',
    'workerTypeCarpenter': 'Carpenter',
    'workerTypeElectrician': 'Electrician',
    'workerTypePlumber': 'Plumber',
    'workerTypeMason': 'Mason',
    'workerTypePainter': 'Painter',
    'workerTypeLaborer': 'Laborer',
    'workerTypeOperator': 'Operator',
    'workerTypeOther': 'Other',
    'search': 'Search',
    'queuedForSync':
        'Saved offline. It will sync automatically when you reconnect.',
    'offlineSyncPending': '{count} offline actions are waiting to sync.',
    'offlineSyncFailed': '{count} offline actions failed and need attention.',
    'offlineSyncFailureQuota':
        'Queued action was rejected because your plan limit has been reached.',
    'offlineSyncFailureUnauthenticated':
        'Queued sync requires sign-in. Please log in again.',
    'offlineSyncFailureInvalidTarget':
        'Queued action is no longer valid because the target item was archived, removed, or is no longer available.',
    'offlineSyncFailurePermission':
        'Queued action was rejected because it no longer has permission to sync.',
    'offlineSyncFailureGeneric': 'A queued action failed to sync.',
    'confirmArchiveExpense': 'Archive this expense?',
    'confirmArchivePayment': 'Archive this payment?',
    'confirmArchiveWorkerEntry': 'Archive this worker entry?',
    'confirmDeleteProjectCascade':
        'Delete this project and all linked expenses, payments, worker entries, metrics, and notifications?',
    'deleteProjectTypeNameToConfirm':
        'To confirm, type the project name below.',
    'budgetUsed': 'Budget used',
    'overBudget': 'Over budget',
    'archivedProjects': 'Archived Projects',
    'unarchive': 'Unarchive',
    'noArchivedProjects': 'No archived projects found.',
    'limitReached': 'Limit Reached',
    'continue': 'Continue',
    'confirm': 'Confirm',
    'notNow': 'Not now',
    'openSettings': 'Open Settings',
    'save': 'Save',
    'cancel': 'Cancel',
    'delete': 'Delete',
    'workerAccounting': 'Worker accounting',
    'contractorAccounting': 'Contractor accounting',
    'equipmentAccounting': 'Equipment accounting',
    'transportAccounting': 'Transport accounting',
    'accessibilityAttachmentControl': 'Attachment control',
    'accessibilityFilterControl': 'Filter control',
    'accessibilityGroupControl': 'Group control',
    'accessibilitySummaryCard': 'Summary card',
    'accessibilityExportControl': 'Export control',
    'freeTrial': '7-day free trial',
    'startTrial': 'Start Trial',
    'language': 'Language',
    'currency': 'Currency',
    'notifications': 'Notifications',
    'riskAlerts': 'Risk Alerts',
    'voiceExpense': 'Voice Expense',
    'welcome': 'Welcome to Buildozer',
    'getStarted': 'Get Started',
    'remaining': 'Remaining',
    'status': 'Status',
    'addExpense': 'Add Expense',
    'addPayment': 'Add Payment',
    'addWorkerEntry': 'Add Worker Entry',
    'createProject': 'Create Project',
    'login': 'Login',
    'signup': 'Sign Up',
    'forgotPassword': 'Forgot Password',
    'email': 'Email',
    'password': 'Password',
    'loginEmailRequired': 'Enter your email.',
    'loginPasswordRequired': 'Enter your password.',
    'skip': 'Skip',
    'next': 'Next',
    'loading': 'Loading...',
    'loadingShort': '...',
    'retry': 'Retry',
    'edit': 'Edit',
    'archive': 'Archive',
    'none': '-',
    'whatYouGet': 'What you get',
    'chooseLanguageTitle': 'Choose your language',
    'chooseLanguageSubtitle':
        'Pick your preferred language. You can change it later in Settings.',
    'englishLanguage': 'English',
    'arabicLanguage': 'Arabic',
    'onboardingTrackProjectsTitle': 'Track projects',
    'onboardingTrackProjectsSubtitle':
        'Create and monitor construction projects instantly from site.',
    'onboardingAddExpensesTitle': 'Add expenses quickly',
    'onboardingAddExpensesSubtitle':
        'Log expenses in seconds with smart defaults and recent values.',
    'onboardingKnowProfitTitle': 'Know profit instantly',
    'onboardingKnowProfitSubtitle':
        'See real-time project health, risk, and expected final cost.',
    'featureMobileFirstTitle': 'Mobile-first operation',
    'featureMobileFirstSubtitle': 'Manage projects and expenses from the field',
    'featureVoiceExpenseTitle': 'Voice expense entry',
    'featureVoiceExpenseSubtitle': 'Log costs hands-free with speech',
    'featureProfitabilityTitle': 'Real-time profitability',
    'featureProfitabilitySubtitle': 'See project health and margins live',
    'featureLocalizationTitle': 'Arabic / English + RTL',
    'featureLocalizationSubtitle': 'Full localization and layout support',
    'featurePdfReportsTitle': 'PDF reports',
    'featurePdfReportsSubtitle': 'Export and share professional reports',
    'featureOfflineTitle': 'Offline-safe actions',
    'featureOfflineSubtitle': 'Work without connection, sync when back',
    'welcomeBack': 'Welcome Back',
    'signInToContinue': 'Sign in to your account to continue',
    'continueWithGoogle': 'Continue with Google',
    'setupWorkspaceTitle': 'Set up your workspace',
    'setupWorkspaceSubtitle':
        'Choose the workspace name and currency you will use for projects.',
    'dontHaveAccount': "Don't have an account?",
    'alreadyHaveAccount': 'Already have an account?',
    'fullName': 'Full Name',
    'confirmPassword': 'Confirm Password',
    'companyNameOptional': 'Company Name (optional)',
    'phoneNumberOptional': 'Phone Number (optional)',
    'phoneNumber': 'Phone Number',
    'pickFromContacts': 'Pick from Contacts',
    'contactsPermissionDenied':
        'Contacts access is needed to import a worker name and phone number.',
    'contactsNoPhoneNumber':
        'The selected contact does not have a phone number.',
    'sendResetLink': 'Send reset link',
    'resetLinkSent': 'Reset link sent to your email.',
    'signUpToContinue': 'Create an account to get started',
    'resetPasswordSubtitle':
        'Enter your email and we will send you a link to reset your password.',
    'backToSignIn': 'Back to sign in',
    'orContinueWith': 'or',
    'authNameRequired': 'Enter your name.',
    'verifyEmailTitle': 'Verify your email',
    'verifyEmailSubtitle':
        'We sent a verification link to {email}. Open it, then continue.',
    'verificationEmailSent': 'Verification email sent.',
    'emailNotVerifiedYet':
        'Not verified yet. Open the link in your email, then try again.',
    'iVerifiedContinue': "I've verified — Continue",
    'resendVerificationEmail': 'Resend email',
    'resendInSeconds': 'Resend in {seconds}s',
    'signInCancelled': 'Sign-in was cancelled or could not complete.',
    'pleaseEnterEmailAndPassword': 'Please enter your email and password.',
    'authNoAccountFound':
        'No account found with this email. Check the address or sign up.',
    'authIncorrectPassword': 'Incorrect password. Please try again.',
    'authInvalidEmail': 'Please enter a valid email address.',
    'authAccountDisabled': 'This account has been disabled. Contact support.',
    'authTooManyAttempts': 'Too many attempts. Please try again later.',
    'authNetworkError': 'Network error. Check your connection and try again.',
    'authDifferentProvider':
        'An account already exists with this email. Try signing in with email and password.',
    'authSignInFailed':
        'Sign-in failed. Please check your email and password and try again.',
    'authGoogleConfigError':
        'Google Sign-In is temporarily unavailable for this app version. '
        'Please try again in a few minutes.',
    'actionNotAllowed': 'You are not allowed to perform this action.',
    'featureTemporarilyUnavailable':
        'This feature is temporarily unavailable. Please try again later.',
    'serviceUnavailable':
        'Service is temporarily unavailable. Please try again.',
    'unexpectedErrorTryAgain': 'Something went wrong. Please try again.',
    'authInvalidEmailFormat': 'Invalid email format',
    'authPasswordMinLength': 'Password must be at least 8 characters',
    'authPasswordsDoNotMatch': 'Passwords do not match',
    'authEmailAlreadyInUse': 'An account with this email already exists.',
    'authWeakPassword': 'Password is too weak. Use at least 8 characters.',
    'authOperationNotAllowed': 'Email sign-up is not enabled. Contact support.',
    'authSignUpFailed': 'Sign-up failed. Check your connection and try again.',
    'pleaseLoginFirst': 'Please login first.',
    'overview': 'Overview',
    'quickActions': 'Quick Actions',
    'chooseWorkspace': 'Choose workspace',
    'totalExpenses': 'Total Expenses',
    'totalIncome': 'Total Income',
    'netProfit': 'Net Profit',
    'unlockHigherLimits': 'Unlock higher limits and team scaling',
    'profit': 'Profit',
    'loss': 'Loss',
    'noWorkspaceSelected': 'No workspace selected yet.',
    'noInternetConnection': 'No internet connection',
    'quickAdd': 'Quick Add',
    'expenseList': 'Expense List',
    'paymentList': 'Payment List',
    'addExpenseSubtitle': 'Record a new project expense in seconds.',
    'expenseListSubtitle': 'View, edit, and archive expenses.',
    'addPaymentSubtitle': 'Record client payment and update balance.',
    'paymentListSubtitle': 'View, edit, and archive payments.',
    'addWorkerEntrySubtitle': 'Capture labor days and auto-calculate cost.',
    'createProjectSubtitle': 'Create a new project with contract details.',
    'voiceExpenseSubtitle':
        'Speak naturally, confirm parsed result, then save.',
    'newProject': 'New Project',
    'editProjectTitle': 'Edit Project',
    'noProjectsYet': 'No projects yet.',
    'projectDetails': 'Project Details',
    'projectNotFound': 'Project not found.',
    'projectName': 'Project Name',
    'clientName': 'Client Name',
    'contractValue': 'Contract Value',
    'location': 'Location',
    'description': 'Description',
    'purpose': 'Purpose',
    'paymentStatus': 'Payment status',
    'paymentStatusUnpaid': 'Unpaid',
    'paymentStatusPartial': 'Partial',
    'paymentStatusPaid': 'Paid',
    'paymentStatusRefunded': 'Refunded',
    'paymentStatusCancelled': 'Cancelled',
    'attachmentOpenDenied':
        'You do not have permission to open this attachment.',
    'attachmentMissing': 'Attachment file is missing.',
    'attachmentPending': 'Attachment upload is pending.',
    'attachmentCannotOpen': 'Attachment cannot be opened.',
    'previewAttachment': 'Preview attachment',
    'openAttachment': 'Open attachment',
    'downloadAttachment': 'Download attachment',
    'closePreview': 'Close preview',
    'budgetLimit': 'Budget Limit',
    'filters': 'Filters',
    'clearFilters': 'Clear filters',
    'supplierName': 'Supplier name',
    'entityName': 'Entity name',
    'entityNameOptional': 'Entity name (optional)',
    'startDate': 'Start Date',
    'expectedEndDate': 'Expected End Date',
    'expectedEndDateOptional': 'Expected End Date: Optional',
    'startDateWithValue': 'Start Date: {value}',
    'expectedEndDateWithValue': 'Expected End Date: {value}',
    'completion': 'Completion',
    'saveProject': 'Save Project',
    'updateProject': 'Update Project',
    'fillRequiredFields': 'Please fill required fields.',
    'contractValueLabel': 'Contract Value: {value}',
    'totalExpensesLabel': 'Total Expenses: {value}',
    'totalIncomeLabel': 'Total Income: {value}',
    'netLabel': 'Net: {value}',
    'completionLabel': 'Completion: {value}%',
    'generateReport': 'Generate Report',
    'noExpensesYet': 'No expenses yet.',
    'expenseDetails': 'Expense Details',
    'expenseNotFound': 'Expense not found.',
    'project': 'Project',
    'category': 'Category',
    'amount': 'Amount',
    'date': 'Date',
    'supplierNameOptional': 'Supplier Name (optional)',
    'notes': 'Notes',
    'saveExpense': 'Save Expense',
    'updateExpense': 'Update Expense',
    'selectProjectAndValidAmount': 'Select project and enter valid amount.',
    'currencyLabel': 'Currency',
    'inputLabel': 'Input',
    'sourceLabel': 'Source',
    'addExpenseTitle': 'Add Expense',
    'editExpenseTitle': 'Edit Expense',
    'noPaymentsYet': 'No payments yet.',
    'paymentDetails': 'Payment Details',
    'paymentNotFound': 'Payment not found.',
    'paymentMethod': 'Payment method',
    'savePayment': 'Save Payment',
    'updatePayment': 'Update Payment',
    'addPaymentTitle': 'Add Payment',
    'editPaymentTitle': 'Edit Payment',
    'workers': 'Workers',
    'noWorkersYet': 'No workers yet.',
    'workerDetails': 'Worker Details',
    'workerNotFound': 'Worker not found.',
    'workerName': 'Worker Name',
    'dailyWage': 'Daily Wage',
    'workerType': 'Worker Type',
    'billingType': 'Billing Type',
    'billingTypeDaily': 'Paid by Day',
    'billingTypeProject': 'Paid by Project',
    'billingTypeWithValue': 'Billing: {value}',
    'dailyWageUsedForEntries':
        'This daily wage will be used when adding worker days.',
    'dailyWageNotRequiredForProjectBilling':
        'Not required for project-based workers.',
    'saveWorker': 'Save Worker',
    'updateWorker': 'Update Worker',
    'addWorkerTitle': 'Add Worker',
    'editWorkerTitle': 'Edit Worker',
    'workerList': 'Workers List',
    'workerListSubtitle': 'View and manage your workers.',
    'resources': 'Resources',
    'workerDirectory': 'Worker directory',
    'workerDirectorySubtitle': 'Open worker profiles and accounting.',
    'contractorsDirectory': 'Contractors',
    'contractorsDirectorySubtitle': 'Browse contractor profiles and records.',
    'equipmentDirectory': 'Equipment providers',
    'equipmentDirectorySubtitle': 'Browse equipment providers and records.',
    'transportDirectory': 'Transport providers',
    'transportDirectorySubtitle': 'Browse transport providers and records.',
    'noContractorsYet': 'No contractors yet.',
    'noEquipmentProvidersYet': 'No equipment providers yet.',
    'noTransportProvidersYet': 'No transport providers yet.',
    'searchResources': 'Search resources',
    'lastUsedAtLabel': 'Last used: {value}',
    'defaultRate': 'Default rate',
    'rateUnit': 'Rate unit',
    'manualInput': 'Manual input',
    'chooseSavedResource': 'Choose saved',
    'quantity': 'Quantity',
    'deleteResourceConfirm':
        'Delete {name}? Historical expenses keep their saved names.',
    'addWorkerSubtitle': 'Add a new worker profile to your workspace.',
    'addWorkerEntryTitle': 'Add Worker Entry',
    'editWorkerEntryTitle': 'Edit Worker Entry',
    'daysWorked': 'Days Worked',
    'saveWorkerEntry': 'Save Worker Entry',
    'updateWorkerEntry': 'Update Worker Entry',
    'nameAndValidWageRequired': 'Name and valid daily wage are required.',
    'fillWorkerProjectDaysWage': 'Fill worker, project, days, and wage.',
    'fillWorkerProjectTotalWage': 'Fill worker, project, and total wage.',
    'totalWage': 'Total Wage',
    'calculatedTotalWageWithValue': 'Calculated Total Wage: {value}',
    'recentEntries': 'Recent Entries',
    'noEntriesYet': 'No entries yet.',
    'totalLaborCost': 'Total Labor Cost',
    'editWorker': 'Edit Worker',
    'buildozerFinancialReport': 'Buildozer Financial Report',
    'workspace': 'Workspace',
    'generated': 'Generated',
    'projectFinancialReport': 'Project Financial Report',
    'projectFinancialReportSubtitle':
        'Contract, expenses, payments, net profit/loss',
    'expenseReport': 'Expense Report',
    'expenseReportSubtitle': 'Breakdown by category and period',
    'workerCostReport': 'Worker Cost Report',
    'workerCostReportSubtitle': 'Labor totals and worker entries',
    'currentSnapshot': 'Current Snapshot',
    'expenseBreakdown': 'Expense Breakdown',
    'monthlyCashFlow': 'Monthly Cash Flow',
    'cashFlowTrend': 'Net Cash Flow Trend',
    'recentExpenses': 'Recent Expenses',
    'recentPayments': 'Recent Payments',
    'topWorkers': 'Top Workers',
    'topEntities': 'Top Entities',
    'groupBy': 'Group by',
    'groupByDate': 'Group by date',
    'groupByCategory': 'Group by category',
    'groupByPaymentMethod': 'Group by payment method',
    'groupByEntity': 'Group by entity',
    'ungroup': 'Ungroup',
    'unassigned': 'Unassigned',
    'saveAndAddAnother': 'Save & add another',
    'weeklyInsights': 'Weekly insights',
    'weeklySummary': 'Weekly summary',
    'topEntity': 'Top entity',
    'topCategory': 'Top category',
    'laborExpenses': 'Labor expenses',
    'equipmentExpenses': 'Equipment expenses',
    'laborSummary': 'Labor',
    'equipmentSummary': 'Equipment',
    'paymentBreakdown': 'Payment breakdown',
    'recentTransactions': 'Recent transactions',
    'combinedReport': 'Combined report',
    'paymentSummary': 'Payment summary',
    'recentWeeklyTransactions': 'Recent weekly transactions',
    'entityType': 'Entity type',
    'allTypes': 'All types',
    'entitySummary': 'Entity summary',
    'exportExpenses': 'Export expenses',
    'exportPayments': 'Export payments',
    'exportEntitySummary': 'Export entity summary',
    'exportWeeklyReport': 'Export weekly report',
    'exportCombinedReport': 'Export combined report',
    'exportPdf': 'Export PDF',
    'dateRange': 'Date range',
    'filtersApplied': 'Filters applied',
    'duplicate': 'Duplicate',
    'buildCustomReport': 'Build custom report',
    'dailyBreakdown': 'Daily breakdown',
    'operationsCount': '{count} operations',
    'usagePeriod': 'Usage period: {period} | expenses {count}/{limit}',
    'totalProjects': 'Total Projects: {value}',
    'activeProjectsCount': 'Active Projects: {value}',
    'netProfitLoss': 'Net Profit/Loss: {value}',
    'totalPayments': 'Total Payments',
    'transactions': 'Transactions',
    'todayExpenses': 'Today expenses',
    'weeklyExpenses': 'Weekly expenses',
    'monthlyExpenses': 'Monthly expenses',
    'transactionCount': 'Transactions',
    'groupByRelativeDate': 'Group by relative date',
    'noFilterResults': 'No matching results.',
    'attachments': 'Attachments',
    'attachment': 'Attachment',
    'selectAttachments': 'Select attachments',
    'notificationsTitle': 'Notifications',
    'noNotificationsYet': 'No notifications yet.',
    'recordShortNote':
        'Record a short note (5 to 20 seconds), then review before saving.',
    'tapToStart': 'Tap the microphone to start',
    'recording': 'Recording... {seconds} s',
    'notRecording': 'Not recording',
    'readyToProcess': 'Ready to process',
    'file': 'File: {name}',
    'cancelRerecord': 'Cancel / Re-record',
    'processVoice': 'Process Voice',
    'processingVoice': 'Processing Voice',
    'uploadingAudio': 'Uploading audio...',
    'parsingExpense': 'Parsing expense...',
    'failed': 'Failed',
    'reviewVoiceExpense': 'Review Voice Expense',
    'transcript': 'Transcript',
    'voiceConfidenceSummary':
        'Confidence - amount {amount}%, category {category}%, project {project}%, overall {overall}%',
    'confirmAndSave': 'Confirm & Save',
    'detectedProjectName': 'Detected project name: {name}',
    'recordAudioFirst': 'Record audio first.',
    'recordedFileMissing': 'Recorded file is missing, please record again.',
    'microphonePermissionTitle': 'Allow microphone access',
    'microphonePermissionMessage':
        'Buildozer needs microphone access to record your voice expense note and turn it into a project expense.',
    'microphonePermissionContinue': 'Continue',
    'microphonePermissionDenied':
        'Microphone access is required to record voice expenses.',
    'microphonePermissionSettingsTitle': 'Microphone access is off',
    'microphonePermissionSettingsMessage':
        'Enable Microphone in iOS Settings to record voice expenses.',
    'selectProjectRequired': 'Please select a project.',
    'amountMustBeGreaterThanZero': 'Amount must be greater than zero.',
    'selectValidCategory': 'Please select a valid category.',
    'selectValidCurrency': 'Please select a valid currency.',
    'selectedProjectInvalid': 'Selected project is invalid.',
    'subscriptionActivated': 'Subscription Activated',
    'subscriptionActivatedSubtitle':
        'Your Pro plan is now active. Limits are unlocked and you can continue working.',
    'goToDashboard': 'Go to Dashboard',
    'upgradeRequired': 'Upgrade Required',
    'activeProjectLimitReached': 'Active Project Limit Reached',
    'monthlyExpenseLimitReached': 'Monthly Expense Limit Reached',
    'monthlyPaymentLimitReached': 'Monthly Payment Limit Reached',
    'monthlyWorkerEntryLimitReached': 'Monthly Worker Entry Limit Reached',
    'teamMemberLimitReached': 'Team Member Limit Reached',
    'usageLimitReached': 'Usage Limit Reached',
    'freePlanLimitsMessage':
        'You are on the Free plan with strict usage limits. Upgrade to Pro to continue this action.',
    'limitUsageMessage':
        'You have used {current} of {max} {limitLabel} on the Free plan. Upgrade to Pro to {upgradeAction}.',
    'limitUsageActiveProjects': 'active projects',
    'limitUsageExpenses': 'monthly expense entries',
    'limitUsagePayments': 'monthly payment entries',
    'limitUsageWorkerEntries': 'monthly worker entries',
    'limitUsageTeamMembers': 'team members',
    'limitUsageGeneric': 'available actions',
    'limitUpgradeActionActiveProjects': 'create more active projects',
    'limitUpgradeActionExpenses': 'keep adding expenses',
    'limitUpgradeActionPayments': 'keep adding payments',
    'limitUpgradeActionWorkerEntries': 'keep adding worker entries',
    'limitUpgradeActionTeamMembers': 'invite more team members',
    'limitUpgradeActionGeneric': 'continue',
    'maybeLater': 'Maybe later',
    'purchaseCancelled': 'Purchase was cancelled.',
    'nativePaywallNotSupported':
        'Native paywall is not supported on this platform.',
    'paywallFailed': 'Paywall failed. Please try again.',
    'continueWithPaywall': 'Continue with RevenueCat Paywall',
    'purchaseNotCompleted': 'Purchase was not completed.',
    'proUnlocksSubtitle':
        'Buildozer Pro unlocks higher usage limits and operational scale.',
    'trialStartsWithPurchase':
        '7-day trial starts on first successful subscription purchase.',
    'purchasesRestoredSuccessfully': 'Purchases restored successfully.',
    'noActivePurchasesFound': 'No active purchases found.',
    'customerCenterClosed': 'Customer Center closed.',
    'customerCenterFailed': 'Customer Center failed: {error}',
    'restoring': 'Restoring...',
    'openingCustomerCenter': 'Opening Customer Center...',
    'openCustomerCenter': 'Open Customer Center',
    'trialEndsAt': 'Trial Ends At',
    'currentPeriodEndsAt': 'Current Period Ends At',
    'store': 'Store',
    'revenueCatAppUserId': 'RevenueCat App User ID',
    'wizeSiteProEntitlement': 'Buildozer Pro Entitlement',
    'currentProduct': 'Current Product',
    'entitlementExpiration': 'Entitlement Expiration',
    'entitlementActive': 'Active',
    'entitlementInactive': 'Not active',
    'paymentMethodCash': 'Cash',
    'paymentMethodBank': 'Bank Transfer',
    'paymentMethodCheck': 'Check',
    'expenseCategoryLabor': 'Labor',
    'expenseCategoryWorker': 'Worker',
    'expenseCategoryContractor': 'Contractor',
    'expenseCategoryMaterials': 'Materials',
    'expenseCategoryEquipment': 'Equipment',
    'expenseCategoryTransport': 'Transport',
    'expenseCategoryStorage': 'Storage',
    'expenseCategoryRentals': 'Rentals',
    'expenseCategoryPayments': 'Payments',
    'expenseCategoryOther': 'Other',
    'projectStatusActive': 'Active',
    'projectStatusPaused': 'Paused',
    'projectStatusCompleted': 'Completed',
    'projectStatusCancelled': 'Cancelled',
    'subscriptionStatusTrial': 'Trial',
    'subscriptionStatusActive': 'Active',
    'subscriptionStatusGrace': 'Grace',
    'subscriptionStatusExpired': 'Expired',
    'subscriptionStatusCanceled': 'Canceled',
    'subscriptionStatusUnknown': 'Unknown',
    'tierPro': 'Pro',
    'tierFree': 'Free',
    'dateWithValue': 'Date: {value}',
    'phoneWithValue': 'Phone: {value}',
    'dailyWageWithValue': 'Daily Wage: {value}',
    'typeWithValue': 'Type: {value}',
    'amountWithValue': 'Amount: {value}',
    'methodWithValue': 'Method: {value}',
    'projectWithValue': 'Project: {value}',
    'currencyWithValue': 'Currency: {value}',
    'categoryWithValue': 'Category: {value}',
    'supplierWithValue': 'Supplier: {value}',
    'notesWithValue': 'Notes: {value}',
    'sourceWithValue': 'Source: {value}',
    'inputSourceWithValue': 'Input: {input} | Source: {source}',
    'projectDateWithValue': '{project} | {date}',
    'wageWithValue': 'Wage: {value}',
    'totalWageWithValue': 'Total Wage: {value}',
    'workerEntryLine': '{days} d × {wage} = {total}',
    // --- Review improvement pack (Phase 1 localization inventory) ---
    // Navigation
    'navigationHomeTab': 'Home tab',
    'navigationAddTab': 'Add tab',
    'navigationProjectsTab': 'Projects tab',
    // Unread notifications
    'unreadNotificationsCount': '{count} unread notifications',
    'markAllRead': 'Mark all as read',
    'viewAllNotifications': 'View all notifications',
    // Loading and recovery states
    'loadingContent': 'Loading content',
    'somethingWentWrong': 'Something went wrong',
    'tryAgain': 'Try again',
    'recoverableErrorTitle': 'We hit a snag',
    // Voice countdown and playback
    'voiceCountdownRemaining': '{seconds}s remaining',
    'voiceRecordingInProgress': 'Recording…',
    'voicePlayRecording': 'Play recording',
    'voiceRerecord': 'Re-record',
    'voiceProcessing': 'Processing…',
    // Filter removal
    'removeFilter': 'Remove filter',
    'clearAllFilters': 'Clear all filters',
    'activeFilters': 'Active filters',
    // Bulk archive
    'selectionMode': 'Select items',
    'archiveSelected': 'Archive selected',
    'bulkArchiveConfirm': 'Archive {count} selected items?',
    'bulkArchivePartialFailure':
        'Some items could not be archived. Tap retry to try again.',
    // Report scope and export
    'reportScope': 'Report scope',
    'reportDateRange': 'Date range',
    'reportExports': 'Exports',
    'reportStartDate': 'From: {value}',
    'reportEndDate': 'To: {value}',
    'showArchivedProjects': 'Show archived projects',
    'loadMore': 'Load more',
    'reportExportProgress': 'Loaded {count} records',
    'cancelExport': 'Cancel export',
    'noDataYet': 'No data yet',
    'printReport': 'Print',
    'shareReport': 'Share',
    'shareChart': 'Share chart',
    // Worker status
    'workerStatusActive': 'Active',
    'workerStatusInactive': 'Inactive',
    'workerStatusTerminated': 'Terminated',
    // Plan comparison
    'comparePlans': 'Compare plans',
    'planRecommended': 'Recommended',
    'planFeatureIncluded': 'Included',
    'planFeatureNotIncluded': 'Not included',
    'plansUnavailableTitle': 'Plans unavailable',
    'plansUnavailableMessage':
        'Store offers are unavailable right now. Try again shortly.',
    'plansRecoveredAfterRetry': 'Plans loaded after retry.',
    'planFeatureUnlimitedProjects': 'Unlimited projects',
    'planFeaturePrioritySupport': 'Priority support',
    'planFeatureAdvancedReports': 'Advanced reports',
    // Settings help and legal
    'aboutApp': 'About app',
    'settingsAccount': 'Account',
    'settingsPreferences': 'Preferences',
    'settingsWorkspace': 'Workspace',
    'workspaceNameTitle': 'Workspace name',
    'renameWorkspace': 'Rename workspace',
    'workspaceNameEmptyError': 'Enter a workspace name.',
    'manageMembers': 'Manage members',
    'settingsSaveFailed':
        'Could not save settings. Your previous value was restored.',
    'appVersion': 'App version',
    'helpAndSupport': 'Help & Support',
    'privacyPolicy': 'Privacy Policy',
    'termsOfService': 'Terms of Service',
    'runDiagnostics': 'Run diagnostics',
    'crashlyticsDiagnostics': 'Crashlytics diagnostics',
    'sendTestNonFatalError': 'Send test non-fatal error',
    'crashlyticsNonFatalSent': 'Non-fatal sent',
    'runDiagnosticsConfirmTitle': 'Run diagnostics?',
    'runDiagnosticsConfirmMessage':
        'This can send a diagnostic report or terminate the app.',
    'forceCrash': 'Force crash',
    'forceCrashKillsApp': 'Force crash (kills app)',
    'forceCrashConfirmTitle': 'Force crash?',
    'forceCrashConfirmMessage':
        'This will terminate the app immediately. Continue only during diagnostics.',
    // Sync outcomes
    'syncStatus': 'Sync status',
    'syncStatusSubtitle':
        'Review pending, failed, and recently resolved sync items.',
    'syncPending': 'Pending sync',
    'syncFailed': 'Sync failed',
    'syncNeedsAttention': 'Needs attention',
    'syncRecentlyResolved': 'Recently resolved',
    'syncStatusEmpty': 'No pending or recent sync activity.',
    'syncNoPending': 'Nothing is waiting to sync.',
    'syncNoFailed': 'No failed sync items.',
    'syncNoNeedsAttention': 'No sync items need attention.',
    'syncNoResolved': 'No recently resolved sync items.',
    'offlineSyncStatusUnavailable':
        'Sync status is unavailable right now. Try again shortly.',
    'syncResolvedNewerKept':
        'A newer version was kept. Your older change was not applied.',
    'syncResolvedApplied': 'Your change was applied successfully.',
    'retrySync': 'Retry sync',
    // Sanitized failure messages (see core/utils/app_error_messages.dart)
    'errorNetwork': 'No connection. Check your network and try again.',
    'errorPermissionDenied': 'You do not have permission to do this.',
    'errorUnauthenticated': 'Please sign in again to continue.',
    'errorNotFound': 'That item is no longer available.',
    'errorQuota': 'Your plan limit has been reached.',
    'errorStorage':
        'File transfer failed. Check your connection and try again.',
    'errorAuth': 'Sign-in failed. Please try again.',
    'errorAuthInvalidCredentials':
        'Incorrect email or password. Please try again.',
    'errorRecording':
        'Recording failed. Check microphone access and try again.',
    'errorUnknown': 'Something went wrong. Please try again.',
    // Worker accounting partial payments (see worker_accounting_record.dart)
    'workerPaidAmountRequired':
        'Enter the amount paid for this partial record.',
    'workerPaidAmountTooLow': 'The paid amount must be greater than zero.',
    'workerPaidAmountTooHigh':
        'The paid amount must be less than the total amount.',
    'workerPaidAmountLabel': 'Amount paid',
    'workerLegacyPartialUnresolved':
        'This older partial record has no recorded paid amount, so it is excluded from confirmed totals.',
    'workerConfirmedPaid': 'Confirmed paid',
    'workerConfirmedOutstanding': 'Outstanding',
    // --- v2 design system ---
    'activity': 'Activity',
    'more': 'More',
    'income': 'Income',
    'account': 'Account',
    'plan': 'Plan',
    'netThisMonth': 'Net this month',
    'week': 'Week',
    'month': 'Month',
    'switchWorkspace': 'Switch workspace',
    'createWorkspace': 'Create workspace',
    'createWorkspaceTitle': 'New workspace',
    'createWorkspaceUpsell': 'Upgrade to Pro to create additional workspaces.',
    'ofContract': 'of contract value',
    'appearance': 'Appearance',
    'darkMode': 'Dark mode',
    'fundsIn': 'Funds in',
    'spent': 'Spent',
    'budgetHealth': 'Budget health',
    'good': 'Looking good',
    'whatToAdd': 'What do you want to add?',
    'expenseDesc': 'Money out — materials, wages, rent',
    'paymentDesc': 'Money in — owner deposit, funds',
    'startVoice': 'Or record it by voice',
    'markRead': 'Mark all read',
    'thisWeek': 'This week',
    'earlier': 'Earlier',
    'memberSince': 'Member since',
    'seeAll': 'See all',
    'searchActivity': 'Search activity',
    'recordExpense': 'Record an expense',
    'tapToSpeak': 'Tap to speak',
    'listening': 'Listening…',
    'detected': 'We detected',
    'onSite': 'on site',
    'upgradePro': 'Upgrade to Pro',
    'proSub': 'Unlimited projects & reports',
    'themeSystem': 'System',
    'themeLight': 'Light',
    'themeDark': 'Dark',
    'siteEngineer': 'Site Engineer',
    'welcomeSub': 'Track every pound on every site — by voice, in seconds.',
  };

  static final _ar = <String, String>{
    ..._en,
    'appName': 'بيلدوزر',
    'tagline': 'إدارة ذكية لمشاريع البناء',
    'home': 'الرئيسية',
    'projects': 'المشاريع',
    'add': 'إضافة',
    'reports': 'التقارير',
    'reportAccessDenied':
        'ليس لديك صلاحية لعرض التقارير المالية أو الأرصدة أو المرفقات.',
    'reportExportFailed': 'تعذر إنشاء ملف PDF. تحقق من الاتصال وحاول مرة أخرى.',
    'settings': 'الإعدادات',
    'subscription': 'الاشتراك',
    'upgradeToPro': 'الترقية إلى برو',
    'freePlan': 'الخطة المجانية',
    'proPlan': 'خطة برو',
    'monthlyUsage': 'استهلاك الشهر',
    'activeProjects': 'المشاريع النشطة',
    'expenses': 'المصروفات',
    'payments': 'الدفعات',
    'workerEntries': 'سجلات العمال',
    'planAndBilling': 'الخطة والفوترة',
    'manageSubscription': 'إدارة الاشتراك',
    'restorePurchases': 'استعادة المشتريات',
    'logout': 'تسجيل الخروج',
    'profile': 'الملف الشخصي',
    'editProfile': 'تعديل الملف الشخصي',
    'changePhoto': 'تغيير الصورة',
    'manageTeam': 'إدارة الفريق',
    'teamManagement': 'إدارة الفريق',
    'teamMembersTitle': 'أعضاء الفريق',
    'noTeamMembersYet': 'لا يوجد أعضاء فريق بعد.',
    'inviteMember': 'دعوة عضو',
    'inviteByEmail': 'دعوة عبر البريد الإلكتروني',
    'role': 'الدور',
    'memberRole': 'عضو',
    'ownerRole': 'مالك',
    'adminRole': 'مدير',
    'accountingApprovedRole': 'محاسب معتمد',
    'entryOnlyRole': 'إدخال فقط',
    'workspaceCrewTitle': 'فريق مساحة العمل',
    'allProjectsOption': 'كل المشاريع',
    'all': 'الكل',
    'allStatuses': 'كل الحالات',
    'projectSortRecent': 'الأحدث',
    'projectSortName': 'الاسم',
    'projectSortHighestExpense': 'الأعلى مصروفات',
    'projectSortHighestIncome': 'الأعلى دخلًا',
    'projectSortHighestNet': 'الأعلى صافيًا',
    'projectFinancialAccessRestricted':
        'التفاصيل المالية للمشاريع غير متاحة لدورك.',
    'confirmArchiveProject': 'هل تريد أرشفة هذا المشروع؟',
    'selectProject': 'اختر مشروعاً',
    'allProjects': 'كل المشاريع',
    'searchProjects': 'ابحث عن مشروع',
    'noProjectsMatchSearch': 'لا توجد مشاريع مطابقة لبحثك.',
    'showingDataForProject': 'عرض بيانات {project} فقط',
    'selectProjectToViewReport': 'يرجى اختيار مشروع لعرض التقرير.',
    'projectReport': 'تقرير المشروع',
    'generatedByBuildozer': 'تم إنشاء هذا التقرير بأمان بواسطة Buildozer',
    'notificationTargetedFeed': 'أحدث تنبيهات مساحة العمل الخاصة بك',
    'workerTypeCarpenter': 'نجار',
    'workerTypeElectrician': 'كهربائي',
    'workerTypePlumber': 'سباك',
    'workerTypeMason': 'بنّاء',
    'workerTypePainter': 'دهان',
    'workerTypeLaborer': 'عامل',
    'workerTypeOperator': 'مشغل',
    'workerTypeOther': 'أخرى',
    'search': 'بحث',
    'queuedForSync':
        'تم الحفظ بدون اتصال. ستتم المزامنة تلقائياً عند عودة الشبكة.',
    'offlineSyncPending': 'هناك {count} إجراءات بدون اتصال بانتظار المزامنة.',
    'offlineSyncFailed': 'فشل {count} إجراءات بدون اتصال وتحتاج إلى مراجعة.',
    'confirmArchiveExpense': 'هل تريد أرشفة هذا المصروف؟',
    'confirmArchivePayment': 'هل تريد أرشفة هذه الدفعة؟',
    'confirmArchiveWorkerEntry': 'هل تريد أرشفة سجل العامل هذا؟',
    'confirmDeleteProjectCascade':
        'هل تريد حذف هذا المشروع وكل المصروفات والدفعات وسجلات العمال والمقاييس والإشعارات المرتبطة به؟',
    'deleteProjectTypeNameToConfirm': 'للتأكيد، اكتب اسم المشروع أدناه.',
    'budgetUsed': 'الميزانية المستخدمة',
    'overBudget': 'تجاوز الميزانية',
    'archivedProjects': 'المشاريع المؤرشفة',
    'unarchive': 'إلغاء الأرشفة',
    'noArchivedProjects': 'لا توجد مشاريع مؤرشفة.',
    'limitReached': 'تم الوصول للحد',
    'continue': 'متابعة',
    'confirm': 'تأكيد',
    'save': 'حفظ',
    'cancel': 'إلغاء',
    'delete': 'Delete',
    'workerAccounting': 'محاسبة العامل',
    'contractorAccounting': 'محاسبة المقاول',
    'equipmentAccounting': 'محاسبة المعدات',
    'transportAccounting': 'محاسبة النقل',
    'accessibilityAttachmentControl': 'زر المرفقات',
    'accessibilityFilterControl': 'زر التصفية',
    'accessibilityGroupControl': 'زر التجميع',
    'accessibilitySummaryCard': 'بطاقة الملخص',
    'accessibilityExportControl': 'زر التصدير',
    'freeTrial': 'تجربة مجانية 7 أيام',
    'startTrial': 'ابدأ التجربة',
    'language': 'اللغة',
    'currency': 'العملة',
    'notifications': 'الإشعارات',
    'riskAlerts': 'تنبيهات المخاطر',
    'voiceExpense': 'مصروف صوتي',
    'welcome': 'مرحباً بك في بيلدوزر',
    'getStarted': 'ابدأ الآن',
    'remaining': 'المتبقي',
    'status': 'الحالة',
    'addExpense': 'إضافة مصروف',
    'addPayment': 'إضافة دفعة',
    'addWorkerEntry': 'إضافة سجل عامل',
    'createProject': 'إنشاء مشروع',
    'login': 'تسجيل الدخول',
    'signup': 'إنشاء حساب',
    'forgotPassword': 'نسيت كلمة المرور',
    'email': 'البريد الإلكتروني',
    'password': 'كلمة المرور',
    'loginEmailRequired': 'أدخل بريدك الإلكتروني.',
    'loginPasswordRequired': 'أدخل كلمة المرور.',
    'skip': 'تخطي',
    'next': 'التالي',
    'loading': 'جاري التحميل...',
    'retry': 'إعادة المحاولة',
    'edit': 'تعديل',
    'archive': 'أرشفة',
    'whatYouGet': 'ما الذي ستحصل عليه',
    'chooseLanguageTitle': 'اختر لغتك',
    'chooseLanguageSubtitle':
        'اختر اللغة التي تفضلها. يمكنك تغييرها لاحقاً من الإعدادات.',
    'englishLanguage': 'الإنجليزية',
    'arabicLanguage': 'العربية',
    'onboardingTrackProjectsTitle': 'تابع المشاريع',
    'onboardingTrackProjectsSubtitle':
        'أنشئ وتابع مشاريع البناء بسرعة مباشرة من الموقع.',
    'onboardingAddExpensesTitle': 'أضف المصروفات بسرعة',
    'onboardingAddExpensesSubtitle':
        'سجّل المصروفات خلال ثوانٍ مع إعدادات ذكية.',
    'onboardingKnowProfitTitle': 'اعرف الربحية فوراً',
    'onboardingKnowProfitSubtitle':
        'اطّلع على حالة المشروع والمخاطر والتكلفة المتوقعة لحظياً.',
    'featureMobileFirstTitle': 'تشغيل مخصص للجوال',
    'featureMobileFirstSubtitle': 'إدارة المشاريع والمصروفات من الموقع',
    'featureVoiceExpenseTitle': 'إدخال المصروفات بالصوت',
    'featureVoiceExpenseSubtitle': 'سجّل التكاليف بدون استخدام اليدين',
    'featureProfitabilityTitle': 'ربحية لحظية',
    'featureProfitabilitySubtitle': 'شاهد حالة المشروع والهوامش مباشرة',
    'featureLocalizationTitle': 'عربي / إنجليزي + RTL',
    'featureLocalizationSubtitle': 'دعم كامل للترجمة واتجاه الواجهة',
    'featurePdfReportsTitle': 'تقارير PDF',
    'featurePdfReportsSubtitle': 'صدّر وشارك تقارير احترافية',
    'featureOfflineTitle': 'عمل آمن بدون إنترنت',
    'featureOfflineSubtitle': 'واصل العمل بدون اتصال والمزامنة عند الرجوع',
    'welcomeBack': 'مرحباً بعودتك',
    'signInToContinue': 'سجّل الدخول للمتابعة',
    'continueWithGoogle': 'المتابعة باستخدام Google',
    'setupWorkspaceTitle': 'إعداد مساحة العمل',
    'setupWorkspaceSubtitle':
        'اختر اسم مساحة العمل والعملة التي ستستخدمها للمشاريع.',
    'dontHaveAccount': 'ليس لديك حساب؟',
    'alreadyHaveAccount': 'لديك حساب بالفعل؟',
    'fullName': 'الاسم الكامل',
    'confirmPassword': 'تأكيد كلمة المرور',
    'companyNameOptional': 'اسم الشركة (اختياري)',
    'phoneNumberOptional': 'رقم الهاتف (اختياري)',
    'phoneNumber': 'رقم الهاتف',
    'sendResetLink': 'إرسال رابط إعادة التعيين',
    'resetLinkSent': 'تم إرسال رابط إعادة التعيين إلى بريدك.',
    'signUpToContinue': 'أنشئ حسابًا للبدء',
    'resetPasswordSubtitle':
        'أدخل بريدك الإلكتروني وسنرسل لك رابطًا لإعادة تعيين كلمة المرور.',
    'backToSignIn': 'العودة لتسجيل الدخول',
    'orContinueWith': 'أو',
    'authNameRequired': 'أدخل اسمك.',
    'verifyEmailTitle': 'تأكيد بريدك الإلكتروني',
    'verifyEmailSubtitle':
        'أرسلنا رابط تأكيد إلى {email}. افتحه ثم تابع.',
    'verificationEmailSent': 'تم إرسال رسالة التأكيد.',
    'emailNotVerifiedYet':
        'لم يتم التأكيد بعد. افتح الرابط في بريدك ثم حاول مرة أخرى.',
    'iVerifiedContinue': 'لقد أكدت — متابعة',
    'resendVerificationEmail': 'إعادة إرسال الرسالة',
    'resendInSeconds': 'إعادة الإرسال خلال {seconds} ثانية',
    'signInCancelled': 'تم إلغاء تسجيل الدخول أو لم يكتمل.',
    'pleaseEnterEmailAndPassword': 'يرجى إدخال البريد الإلكتروني وكلمة المرور.',
    'authNoAccountFound': 'لا يوجد حساب مرتبط بهذا البريد.',
    'authIncorrectPassword': 'كلمة المرور غير صحيحة.',
    'authInvalidEmail': 'يرجى إدخال بريد إلكتروني صحيح.',
    'authAccountDisabled': 'تم تعطيل هذا الحساب. تواصل مع الدعم.',
    'authTooManyAttempts': 'محاولات كثيرة جداً. حاول مرة أخرى لاحقاً.',
    'authNetworkError': 'خطأ في الشبكة. تحقق من الاتصال وحاول مجدداً.',
    'authDifferentProvider':
        'يوجد حساب بهذا البريد. جرّب تسجيل الدخول بالبريد وكلمة المرور.',
    'authSignInFailed': 'فشل تسجيل الدخول. تحقق من البيانات وحاول مرة أخرى.',
    'authGoogleConfigError':
        'تسجيل الدخول عبر جوجل غير متاح مؤقتًا لهذا الإصدار من التطبيق. '
        'يرجى المحاولة مرة أخرى بعد بضع دقائق.',
    'authInvalidEmailFormat': 'تنسيق البريد الإلكتروني غير صحيح',
    'authPasswordMinLength': 'يجب أن تكون كلمة المرور 8 أحرف على الأقل',
    'authPasswordsDoNotMatch': 'كلمتا المرور غير متطابقتين',
    'authEmailAlreadyInUse': 'يوجد حساب بهذا البريد مسبقاً.',
    'authWeakPassword': 'كلمة المرور ضعيفة. استخدم 8 أحرف على الأقل.',
    'authOperationNotAllowed': 'التسجيل بالبريد غير مفعّل. تواصل مع الدعم.',
    'authSignUpFailed': 'فشل التسجيل. تحقق من الاتصال وحاول مرة أخرى.',
    'pleaseLoginFirst': 'يرجى تسجيل الدخول أولاً.',
    'overview': 'نظرة عامة',
    'quickActions': 'إجراءات سريعة',
    'chooseWorkspace': 'اختر مساحة العمل',
    'totalExpenses': 'إجمالي المصروفات',
    'totalIncome': 'إجمالي الإيرادات',
    'netProfit': 'صافي الربح',
    'unlockHigherLimits': 'افتح حدود استخدام أعلى وتوسّع الفريق',
    'profit': 'ربح',
    'loss': 'خسارة',
    'noWorkspaceSelected': 'لا توجد مساحة عمل محددة بعد.',
    'noInternetConnection': 'لا يوجد اتصال بالإنترنت',
    'quickAdd': 'إضافة سريعة',
    'expenseList': 'قائمة المصروفات',
    'paymentList': 'قائمة الدفعات',
    'addExpenseSubtitle': 'سجّل مصروف مشروع جديد خلال ثوانٍ.',
    'expenseListSubtitle': 'اعرض وعدّل وأرشف المصروفات.',
    'addPaymentSubtitle': 'سجّل دفعة العميل وحدث الرصيد.',
    'paymentListSubtitle': 'اعرض وعدّل وأرشف الدفعات.',
    'addWorkerEntrySubtitle': 'سجّل أيام العمل واحسب التكلفة تلقائياً.',
    'createProjectSubtitle': 'أنشئ مشروعاً جديداً مع تفاصيل العقد.',
    'voiceExpenseSubtitle': 'تحدث بشكل طبيعي ثم راجع النتيجة واحفظ.',
    'newProject': 'مشروع جديد',
    'editProjectTitle': 'تعديل المشروع',
    'noProjectsYet': 'لا توجد مشاريع بعد.',
    'projectDetails': 'تفاصيل المشروع',
    'projectNotFound': 'المشروع غير موجود.',
    'projectName': 'اسم المشروع',
    'clientName': 'اسم العميل',
    'contractValue': 'قيمة العقد',
    'location': 'الموقع',
    'description': 'الوصف',
    'purpose': 'الغرض',
    'paymentStatus': 'حالة الدفع',
    'paymentStatusUnpaid': 'غير مدفوع',
    'paymentStatusPartial': 'مدفوع جزئياً',
    'paymentStatusPaid': 'مدفوع',
    'paymentStatusRefunded': 'مستردة',
    'paymentStatusCancelled': 'ملغاة',
    'attachmentOpenDenied': 'ليس لديك صلاحية لفتح هذا المرفق.',
    'attachmentMissing': 'ملف المرفق غير موجود.',
    'attachmentPending': 'رفع المرفق قيد الانتظار.',
    'attachmentCannotOpen': 'لا يمكن فتح المرفق.',
    'previewAttachment': 'معاينة المرفق',
    'openAttachment': 'فتح المرفق',
    'downloadAttachment': 'تحميل المرفق',
    'closePreview': 'إغلاق المعاينة',
    'budgetLimit': 'حد الميزانية',
    'filters': 'عوامل التصفية',
    'clearFilters': 'Clear filters',
    'supplierName': 'اسم المورد',
    'entityName': 'اسم الكيان',
    'entityNameOptional': 'اسم الكيان (اختياري)',
    'startDate': 'تاريخ البداية',
    'expectedEndDate': 'تاريخ النهاية المتوقع',
    'expectedEndDateOptional': 'تاريخ النهاية المتوقع: اختياري',
    'startDateWithValue': 'تاريخ البداية: {value}',
    'expectedEndDateWithValue': 'تاريخ النهاية المتوقع: {value}',
    'completion': 'نسبة الإنجاز',
    'saveProject': 'حفظ المشروع',
    'updateProject': 'تحديث المشروع',
    'fillRequiredFields': 'يرجى تعبئة الحقول المطلوبة.',
    'contractValueLabel': 'قيمة العقد: {value}',
    'totalExpensesLabel': 'إجمالي المصروفات: {value}',
    'totalIncomeLabel': 'إجمالي الإيرادات: {value}',
    'netLabel': 'الصافي: {value}',
    'completionLabel': 'الإنجاز: {value}%',
    'generateReport': 'إنشاء تقرير',
    'noExpensesYet': 'لا توجد مصروفات بعد.',
    'expenseDetails': 'تفاصيل المصروف',
    'expenseNotFound': 'المصروف غير موجود.',
    'project': 'المشروع',
    'category': 'الفئة',
    'amount': 'المبلغ',
    'date': 'التاريخ',
    'supplierNameOptional': 'اسم المورد (اختياري)',
    'notes': 'ملاحظات',
    'saveExpense': 'حفظ المصروف',
    'updateExpense': 'تحديث المصروف',
    'selectProjectAndValidAmount': 'اختر مشروعاً وأدخل مبلغاً صحيحاً.',
    'currencyLabel': 'العملة',
    'inputLabel': 'الإدخال',
    'sourceLabel': 'المصدر',
    'addExpenseTitle': 'إضافة مصروف',
    'editExpenseTitle': 'تعديل مصروف',
    'noPaymentsYet': 'لا توجد دفعات بعد.',
    'paymentDetails': 'تفاصيل الدفعة',
    'paymentNotFound': 'الدفعة غير موجودة.',
    'paymentMethod': 'طريقة الدفع',
    'savePayment': 'حفظ الدفعة',
    'updatePayment': 'تحديث الدفعة',
    'addPaymentTitle': 'إضافة دفعة',
    'editPaymentTitle': 'تعديل دفعة',
    'workers': 'العمال',
    'noWorkersYet': 'لا يوجد عمال بعد.',
    'workerDetails': 'تفاصيل العامل',
    'workerNotFound': 'العامل غير موجود.',
    'workerName': 'اسم العامل',
    'dailyWage': 'الأجر اليومي',
    'workerType': 'نوع العامل',
    'billingType': 'طريقة الدفع',
    'billingTypeDaily': 'بالأيام',
    'billingTypeProject': 'بالمشروع',
    'billingTypeWithValue': 'الدفع: {value}',
    'dailyWageUsedForEntries':
        'سيتم استخدام الأجر اليومي عند إضافة أيام العامل.',
    'dailyWageNotRequiredForProjectBilling':
        'غير مطلوب للعامل الذي يُدفع بالمشروع.',
    'saveWorker': 'حفظ العامل',
    'updateWorker': 'تحديث العامل',
    'addWorkerTitle': 'إضافة عامل',
    'editWorkerTitle': 'تعديل عامل',
    'workerList': 'قائمة العمال',
    'workerListSubtitle': 'عرض وإدارة العمال.',
    'resources': 'Resources',
    'workerDirectory': 'Worker directory',
    'workerDirectorySubtitle': 'Open worker profiles and accounting.',
    'contractorsDirectory': 'Contractors',
    'contractorsDirectorySubtitle': 'Browse contractor profiles and records.',
    'equipmentDirectory': 'Equipment providers',
    'equipmentDirectorySubtitle': 'Browse equipment providers and records.',
    'transportDirectory': 'Transport providers',
    'transportDirectorySubtitle': 'Browse transport providers and records.',
    'noContractorsYet': 'No contractors yet.',
    'noEquipmentProvidersYet': 'No equipment providers yet.',
    'noTransportProvidersYet': 'No transport providers yet.',
    'searchResources': 'Search resources',
    'lastUsedAtLabel': 'Last used: {value}',
    'defaultRate': 'Default rate',
    'rateUnit': 'Rate unit',
    'manualInput': 'Manual input',
    'chooseSavedResource': 'Choose saved',
    'quantity': 'Quantity',
    'deleteResourceConfirm':
        'Delete {name}? Historical expenses keep their saved names.',
    'addWorkerSubtitle': 'إضافة ملف عامل جديد إلى مساحة العمل.',
    'addWorkerEntryTitle': 'إإضافة سجل عامل',
    'editWorkerEntryTitle': 'تعديل سجل عامل',
    'daysWorked': 'أيام العمل',
    'saveWorkerEntry': 'حفظ سجل العامل',
    'updateWorkerEntry': 'تحديث سجل العامل',
    'nameAndValidWageRequired': 'اسم العامل وأجر يومي صحيح مطلوبان.',
    'fillWorkerProjectDaysWage': 'املأ العامل والمشروع والأيام والأجر.',
    'fillWorkerProjectTotalWage': 'املأ العامل والمشروع وإجمالي الأجر.',
    'totalWage': 'إجمالي الأجر',
    'calculatedTotalWageWithValue': 'إجمالي الأجر المحسوب: {value}',
    'recentEntries': 'أحدث السجلات',
    'noEntriesYet': 'لا توجد سجلات بعد.',
    'totalLaborCost': 'إجمالي تكلفة العمالة',
    'editWorker': 'تعديل العامل',
    'buildozerFinancialReport': 'تقرير بيلدوزر المالي',
    'workspace': 'مساحة العمل',
    'generated': 'تم الإنشاء',
    'projectFinancialReport': 'تقرير المشروع المالي',
    'projectFinancialReportSubtitle':
        'العقد والمصروفات والدفعات وصافي الربح/الخسارة',
    'expenseReport': 'تقرير المصروفات',
    'expenseReportSubtitle': 'تفصيل حسب الفئة والفترة',
    'workerCostReport': 'تقرير تكلفة العمال',
    'workerCostReportSubtitle': 'إجماليات العمالة وسجلات العمال',
    'currentSnapshot': 'الملخص الحالي',
    'expenseBreakdown': 'توزيع المصروفات',
    'monthlyCashFlow': 'التدفق النقدي الشهري',
    'cashFlowTrend': 'اتجاه صافي التدفق النقدي',
    'recentExpenses': 'أحدث المصروفات',
    'recentPayments': 'أحدث الدفعات',
    'topWorkers': 'أعلى العمال',
    'topEntities': 'أعلى الكيانات',
    'groupBy': 'تجميع حسب',
    'groupByDate': 'تجميع حسب التاريخ',
    'groupByCategory': 'تجميع حسب الفئة',
    'groupByPaymentMethod': 'تجميع حسب طريقة الدفع',
    'groupByEntity': 'تجميع حسب الكيان',
    'ungroup': 'إلغاء التجميع',
    'unassigned': 'غير مخصص',
    'saveAndAddAnother': 'حفظ وإضافة آخر',
    'weeklyInsights': 'رؤى أسبوعية',
    'weeklySummary': 'ملخص أسبوعي',
    'topEntity': 'أفضل كيان',
    'topCategory': 'أفضل فئة',
    'laborExpenses': 'مصروفات العمالة',
    'equipmentExpenses': 'مصروفات المعدات',
    'laborSummary': 'العمالة',
    'equipmentSummary': 'المعدات',
    'paymentBreakdown': 'تفصيل الدفع',
    'recentTransactions': 'المعاملات الأخيرة',
    'combinedReport': 'تقرير مدمج',
    'paymentSummary': 'ملخص الدفع',
    'recentWeeklyTransactions': 'المعاملات الأسبوعية الأخيرة',
    'entityType': 'نوع الكيان',
    'allTypes': 'كل الأنواع',
    'entitySummary': 'ملخص الكيان',
    'exportExpenses': 'تصدير المصروفات',
    'exportPayments': 'تصدير الدفعات',
    'exportEntitySummary': 'تصدير ملخص الكيان',
    'exportWeeklyReport': 'تصدير التقرير الأسبوعي',
    'exportCombinedReport': 'تصدير التقرير المدمج',
    'exportPdf': 'تصدير PDF',
    'dateRange': 'النطاق الزمني',
    'filtersApplied': 'عوامل التصفية المطبقة',
    'duplicate': 'تكرار',
    'buildCustomReport': 'إنشاء تقرير مخصص',
    'dailyBreakdown': 'التوزيع اليومي',
    'operationsCount': '{count} عملية',
    'usagePeriod': 'فترة الاستخدام: {period} | المصروفات {count}/{limit}',
    'totalProjects': 'إجمالي المشاريع: {value}',
    'activeProjectsCount': 'المشاريع النشطة: {value}',
    'netProfitLoss': 'صافي الربح/الخسارة: {value}',
    'totalPayments': 'إجمالي الدفعات',
    'transactions': 'المعاملات',
    'todayExpenses': 'Today expenses',
    'weeklyExpenses': 'Weekly expenses',
    'monthlyExpenses': 'Monthly expenses',
    'transactionCount': 'Transactions',
    'groupByRelativeDate': 'Group by relative date',
    'noFilterResults': 'No matching results.',
    'attachments': 'المرفقات',
    'attachment': 'مرفق',
    'selectAttachments': 'اختيار المرفقات',
    'notificationsTitle': 'الإشعارات',
    'noNotificationsYet': 'لا توجد إشعارات بعد.',
    'recordShortNote':
        'سجّل ملاحظة قصيرة (من 5 إلى 20 ثانية)، ثم راجعها قبل الحفظ.',
    'tapToStart': 'اضغط على الميكروفون للبدء',
    'recording': 'جارٍ التسجيل... {seconds} ث',
    'notRecording': 'لا يوجد تسجيل',
    'readyToProcess': 'جاهز للمعالجة',
    'file': 'الملف: {name}',
    'cancelRerecord': 'إلغاء / إعادة تسجيل',
    'processVoice': 'معالجة الصوت',
    'processingVoice': 'معالجة الصوت',
    'uploadingAudio': 'جارٍ رفع الصوت...',
    'parsingExpense': 'جارٍ تحليل المصروف...',
    'failed': 'فشل',
    'reviewVoiceExpense': 'مراجعة المصروف الصوتي',
    'transcript': 'النص',
    'voiceConfidenceSummary':
        'الثقة - المبلغ {amount}%، الفئة {category}%، المشروع {project}%، الإجمالي {overall}%',
    'confirmAndSave': 'تأكيد وحفظ',
    'detectedProjectName': 'اسم المشروع المكتشف: {name}',
    'recordAudioFirst': 'سجّل الصوت أولاً.',
    'recordedFileMissing': 'ملف التسجيل مفقود، يرجى التسجيل مرة أخرى.',
    'selectProjectRequired': 'يرجى اختيار مشروع.',
    'amountMustBeGreaterThanZero': 'يجب أن يكون المبلغ أكبر من صفر.',
    'selectValidCategory': 'يرجى اختيار فئة صحيحة.',
    'selectValidCurrency': 'يرجى اختيار عملة صحيحة.',
    'selectedProjectInvalid': 'المشروع المحدد غير صالح.',
    'subscriptionActivated': 'تم تفعيل الاشتراك',
    'subscriptionActivatedSubtitle':
        'تم تفعيل خطة برو. فُتحت الحدود ويمكنك مواصلة العمل.',
    'goToDashboard': 'الانتقال إلى الرئيسية',
    'upgradeRequired': 'الترقية مطلوبة',
    'activeProjectLimitReached': 'تم الوصول لحد المشاريع النشطة',
    'monthlyExpenseLimitReached': 'تم الوصول لحد المصروفات الشهري',
    'monthlyPaymentLimitReached': 'تم الوصول لحد الدفعات الشهري',
    'monthlyWorkerEntryLimitReached': 'تم الوصول لحد سجلات العمال الشهري',
    'teamMemberLimitReached': 'تم الوصول لحد أعضاء الفريق',
    'usageLimitReached': 'تم الوصول لحد الاستخدام',
    'freePlanLimitsMessage':
        'أنت على الخطة المجانية بحدود استخدام صارمة. قم بالترقية إلى برو لمتابعة هذا الإجراء.',
    'limitUsageMessage':
        'استخدمت {current} من {max} {limitLabel} في الخطة المجانية. قم بالترقية إلى برو من أجل {upgradeAction}.',
    'limitUsageActiveProjects': 'مشاريع نشطة',
    'limitUsageExpenses': 'إدخالات مصروفات شهرية',
    'limitUsagePayments': 'إدخالات مدفوعات شهرية',
    'limitUsageWorkerEntries': 'إدخالات عمال شهرية',
    'limitUsageTeamMembers': 'أعضاء فريق',
    'limitUsageGeneric': 'إجراءات متاحة',
    'limitUpgradeActionActiveProjects': 'إنشاء المزيد من المشاريع النشطة',
    'limitUpgradeActionExpenses': 'متابعة إضافة المصروفات',
    'limitUpgradeActionPayments': 'متابعة إضافة المدفوعات',
    'limitUpgradeActionWorkerEntries': 'متابعة إضافة إدخالات العمال',
    'limitUpgradeActionTeamMembers': 'دعوة المزيد من أعضاء الفريق',
    'limitUpgradeActionGeneric': 'المتابعة',
    'maybeLater': 'لاحقاً',
    'purchaseCancelled': 'تم إلغاء عملية الشراء.',
    'nativePaywallNotSupported':
        'شاشة الدفع الأصلية غير مدعومة على هذا النظام.',
    'paywallFailed': 'فشلت شاشة الدفع. حاول مرة أخرى.',
    'continueWithPaywall': 'المتابعة عبر شاشة RevenueCat',
    'purchaseNotCompleted': 'لم تكتمل عملية الشراء.',
    'proUnlocksSubtitle':
        'خطة Buildozer Pro تفتح حدود استخدام أعلى وتوسعاً أكبر.',
    'trialStartsWithPurchase':
        'تبدأ التجربة المجانية 7 أيام عند أول عملية اشتراك ناجحة.',
    'purchasesRestoredSuccessfully': 'تمت استعادة المشتريات بنجاح.',
    'noActivePurchasesFound': 'لم يتم العثور على مشتريات نشطة.',
    'customerCenterClosed': 'تم إغلاق مركز العملاء.',
    'customerCenterFailed': 'فشل مركز العملاء: {error}',
    'restoring': 'جارٍ الاستعادة...',
    'openingCustomerCenter': 'جارٍ فتح مركز العملاء...',
    'openCustomerCenter': 'فتح مركز العملاء',
    'trialEndsAt': 'تنتهي التجربة في',
    'currentPeriodEndsAt': 'تنتهي الفترة الحالية في',
    'store': 'المتجر',
    'revenueCatAppUserId': 'معرف مستخدم RevenueCat',
    'wizeSiteProEntitlement': 'استحقاق Buildozer Pro',
    'currentProduct': 'المنتج الحالي',
    'entitlementExpiration': 'انتهاء الاستحقاق',
    'entitlementActive': 'نشط',
    'entitlementInactive': 'غير نشط',
    'paymentMethodCash': 'نقداً',
    'paymentMethodBank': 'تحويل بنكي',
    'paymentMethodCheck': 'شيك',
    'expenseCategoryLabor': 'عمالة',
    'expenseCategoryWorker': 'Worker',
    'expenseCategoryContractor': 'Contractor',
    'expenseCategoryMaterials': 'مواد',
    'expenseCategoryEquipment': 'معدات',
    'expenseCategoryTransport': 'نقل',
    'expenseCategoryStorage': 'تخزين',
    'expenseCategoryRentals': 'إيجارات',
    'expenseCategoryPayments': 'دفعات',
    'expenseCategoryOther': 'أخرى',
    'projectStatusActive': 'نشط',
    'projectStatusPaused': 'متوقف',
    'projectStatusCompleted': 'مكتمل',
    'projectStatusCancelled': 'ملغي',
    'subscriptionStatusTrial': 'تجريبي',
    'subscriptionStatusActive': 'نشط',
    'subscriptionStatusGrace': 'سماح',
    'subscriptionStatusExpired': 'منتهي',
    'subscriptionStatusCanceled': 'ملغي',
    'subscriptionStatusUnknown': 'غير معروف',
    'tierPro': 'برو',
    'tierFree': 'مجاني',
    'dateWithValue': 'التاريخ: {value}',
    'phoneWithValue': 'الهاتف: {value}',
    'dailyWageWithValue': 'الأجر اليومي: {value}',
    'typeWithValue': 'النوع: {value}',
    'amountWithValue': 'المبلغ: {value}',
    'methodWithValue': 'الطريقة: {value}',
    'projectWithValue': 'المشروع: {value}',
    'currencyWithValue': 'العملة: {value}',
    'categoryWithValue': 'الفئة: {value}',
    'supplierWithValue': 'المورد: {value}',
    'notesWithValue': 'الملاحظات: {value}',
    'sourceWithValue': 'المصدر: {value}',
    'inputSourceWithValue': 'الإدخال: {input} | المصدر: {source}',
    'projectDateWithValue': '{project} | {date}',
    'wageWithValue': 'الأجر: {value}',
    'totalWageWithValue': 'إجمالي الأجر: {value}',
    'workerEntryLine': '{days} يوم × {wage} = {total}',
    // --- Review improvement pack (Phase 1 localization inventory) ---
    // Navigation
    'navigationHomeTab': 'تبويب الرئيسية',
    'navigationAddTab': 'تبويب الإضافة',
    'navigationProjectsTab': 'تبويب المشاريع',
    // Unread notifications
    'unreadNotificationsCount': '{count} إشعارات غير مقروءة',
    'markAllRead': 'تعليم الكل كمقروء',
    'viewAllNotifications': 'عرض جميع الإشعارات',
    // Loading and recovery states
    'loadingContent': 'جارٍ تحميل المحتوى',
    'somethingWentWrong': 'حدث خطأ ما',
    'tryAgain': 'حاول مرة أخرى',
    'recoverableErrorTitle': 'واجهتنا مشكلة',
    // Voice countdown and playback
    'voiceCountdownRemaining': 'يتبقى {seconds} ثانية',
    'voiceRecordingInProgress': 'جارٍ التسجيل…',
    'voicePlayRecording': 'تشغيل التسجيل',
    'voiceRerecord': 'إعادة التسجيل',
    'voiceProcessing': 'جارٍ المعالجة…',
    // Filter removal
    'removeFilter': 'إزالة عامل التصفية',
    'clearAllFilters': 'مسح جميع عوامل التصفية',
    'activeFilters': 'عوامل التصفية النشطة',
    // Bulk archive
    'selectionMode': 'تحديد العناصر',
    'archiveSelected': 'أرشفة المحدد',
    'bulkArchiveConfirm': 'أرشفة {count} عناصر محددة؟',
    'bulkArchivePartialFailure':
        'تعذّرت أرشفة بعض العناصر. اضغط إعادة المحاولة.',
    // Report scope and export
    'reportScope': 'نطاق التقرير',
    'reportDateRange': 'النطاق الزمني',
    'reportExports': 'التصدير',
    'reportStartDate': 'من: {value}',
    'reportEndDate': 'إلى: {value}',
    'showArchivedProjects': 'عرض المشاريع المؤرشفة',
    'loadMore': 'تحميل المزيد',
    'reportExportProgress': 'تم تحميل {count} سجلات',
    'cancelExport': 'إلغاء التصدير',
    'noDataYet': 'لا توجد بيانات بعد',
    'printReport': 'طباعة',
    'shareReport': 'مشاركة',
    'shareChart': 'مشاركة الرسم البياني',
    // Worker status
    'workerStatusActive': 'نشط',
    'workerStatusInactive': 'غير نشط',
    'workerStatusTerminated': 'منتهٍ',
    // Plan comparison
    'comparePlans': 'قارن الخطط',
    'planRecommended': 'موصى به',
    'planFeatureIncluded': 'مضمّن',
    'planFeatureNotIncluded': 'غير مضمّن',
    'plansUnavailableTitle': 'الخطط غير متاحة',
    'plansUnavailableMessage':
        'عروض المتجر غير متاحة الآن. حاول مرة أخرى بعد قليل.',
    'plansRecoveredAfterRetry': 'تم تحميل الخطط بعد إعادة المحاولة.',
    'planFeatureUnlimitedProjects': 'مشاريع غير محدودة',
    'planFeaturePrioritySupport': 'دعم ذو أولوية',
    'planFeatureAdvancedReports': 'تقارير متقدمة',
    // Settings help and legal
    'aboutApp': 'حول التطبيق',
    'settingsAccount': 'الحساب',
    'settingsPreferences': 'التفضيلات',
    'settingsWorkspace': 'مساحة العمل',
    'workspaceNameTitle': 'اسم مساحة العمل',
    'renameWorkspace': 'إعادة تسمية مساحة العمل',
    'workspaceNameEmptyError': 'أدخل اسم مساحة العمل.',
    'manageMembers': 'إدارة الأعضاء',
    'settingsSaveFailed': 'تعذر حفظ الإعدادات. تمت استعادة القيمة السابقة.',
    'appVersion': 'إصدار التطبيق',
    'helpAndSupport': 'المساعدة والدعم',
    'privacyPolicy': 'سياسة الخصوصية',
    'termsOfService': 'شروط الخدمة',
    'runDiagnostics': 'تشغيل التشخيص',
    'crashlyticsDiagnostics': 'تشخيص Crashlytics',
    'sendTestNonFatalError': 'إرسال خطأ اختباري غير قاتل',
    'crashlyticsNonFatalSent': 'تم إرسال الخطأ غير القاتل',
    'runDiagnosticsConfirmTitle': 'تشغيل التشخيص؟',
    'runDiagnosticsConfirmMessage': 'قد يرسل هذا تقرير تشخيص أو يغلق التطبيق.',
    'forceCrash': 'إغلاق اختباري',
    'forceCrashKillsApp': 'إغلاق اختباري (يغلق التطبيق)',
    'forceCrashConfirmTitle': 'إغلاق التطبيق؟',
    'forceCrashConfirmMessage':
        'سيؤدي هذا إلى إغلاق التطبيق فوراً. تابع فقط أثناء التشخيص.',
    // Sync outcomes
    'syncStatus': 'حالة المزامنة',
    'syncStatusSubtitle':
        'راجع عناصر المزامنة المعلقة والفاشلة والتي تم حلها مؤخراً.',
    'syncPending': 'بانتظار المزامنة',
    'syncFailed': 'فشلت المزامنة',
    'syncNeedsAttention': 'تحتاج إلى مراجعة',
    'syncRecentlyResolved': 'تم حلها مؤخراً',
    'syncStatusEmpty': 'لا توجد أنشطة مزامنة معلقة أو حديثة.',
    'syncNoPending': 'لا يوجد شيء بانتظار المزامنة.',
    'syncNoFailed': 'لا توجد عناصر مزامنة فاشلة.',
    'syncNoNeedsAttention': 'لا توجد عناصر مزامنة تحتاج إلى مراجعة.',
    'syncNoResolved': 'لا توجد عناصر مزامنة محلولة مؤخراً.',
    'offlineSyncStatusUnavailable':
        'حالة المزامنة غير متاحة الآن. حاول مرة أخرى بعد قليل.',
    'syncResolvedNewerKept':
        'تم الاحتفاظ بنسخة أحدث. لم يتم تطبيق تغييرك الأقدم.',
    'syncResolvedApplied': 'تم تطبيق تغييرك بنجاح.',
    'retrySync': 'إعادة المزامنة',
    // Sanitized failure messages (see core/utils/app_error_messages.dart)
    'errorNetwork': 'لا يوجد اتصال. تحقق من شبكتك وحاول مرة أخرى.',
    'errorPermissionDenied': 'ليس لديك صلاحية للقيام بذلك.',
    'errorUnauthenticated': 'يرجى تسجيل الدخول مرة أخرى للمتابعة.',
    'errorNotFound': 'هذا العنصر لم يعد متاحًا.',
    'errorQuota': 'لقد وصلت إلى حد خطتك.',
    'errorStorage': 'فشل نقل الملف. تحقق من اتصالك وحاول مرة أخرى.',
    'errorAuth': 'فشل تسجيل الدخول. يرجى المحاولة مرة أخرى.',
    'errorAuthInvalidCredentials':
        'البريد الإلكتروني أو كلمة المرور غير صحيحة. حاول مرة أخرى.',
    'errorRecording': 'فشل التسجيل. تحقق من إذن الميكروفون وحاول مرة أخرى.',
    'errorUnknown': 'حدث خطأ ما. يرجى المحاولة مرة أخرى.',
    // Worker accounting partial payments
    'workerPaidAmountRequired': 'أدخل المبلغ المدفوع لهذا السجل الجزئي.',
    'workerPaidAmountTooLow': 'يجب أن يكون المبلغ المدفوع أكبر من صفر.',
    'workerPaidAmountTooHigh':
        'يجب أن يكون المبلغ المدفوع أقل من المبلغ الإجمالي.',
    'workerPaidAmountLabel': 'المبلغ المدفوع',
    'workerLegacyPartialUnresolved':
        'هذا السجل الجزئي القديم لا يحتوي على مبلغ مدفوع مسجّل، لذا يُستبعد من الإجماليات المؤكدة.',
    'workerConfirmedPaid': 'المدفوع المؤكد',
    'workerConfirmedOutstanding': 'المتبقي',
    // --- v2 design system ---
    'activity': 'النشاط',
    'more': 'المزيد',
    'income': 'الدخل',
    'account': 'الحساب',
    'plan': 'الباقة',
    'netThisMonth': 'صافي هذا الشهر',
    'week': 'أسبوع',
    'month': 'شهر',
    'switchWorkspace': 'تبديل مساحة العمل',
    'createWorkspace': 'إنشاء مساحة عمل',
    'createWorkspaceTitle': 'مساحة عمل جديدة',
    'createWorkspaceUpsell': 'الترقية إلى برو لإنشاء مساحات عمل إضافية.',
    'ofContract': 'من قيمة العقد',
    'appearance': 'المظهر',
    'darkMode': 'الوضع الداكن',
    'fundsIn': 'وارد',
    'spent': 'المصروف',
    'budgetHealth': 'حالة الميزانية',
    'good': 'كل شيء جيد',
    'whatToAdd': 'ماذا تريد أن تضيف؟',
    'expenseDesc': 'صرف — مواد، أجور، إيجار',
    'paymentDesc': 'وارد — دفعة المالك، تمويل',
    'startVoice': 'أو سجّلها بالصوت',
    'markRead': 'تحديد الكل كمقروء',
    'thisWeek': 'هذا الأسبوع',
    'earlier': 'سابقًا',
    'memberSince': 'عضو منذ',
    'seeAll': 'عرض الكل',
    'searchActivity': 'ابحث في النشاط',
    'recordExpense': 'سجّل مصروفًا',
    'tapToSpeak': 'اضغط للتحدث',
    'listening': 'جارٍ الاستماع…',
    'detected': 'اكتشفنا',
    'onSite': 'في الموقع',
    'upgradePro': 'الترقية إلى برو',
    'proSub': 'مشاريع وتقارير غير محدودة',
    'themeSystem': 'النظام',
    'themeLight': 'فاتح',
    'themeDark': 'داكن',
    'siteEngineer': 'مهندس موقع',
    'welcomeSub': 'تابع كل جنيه في كل موقع — بالصوت، في ثوانٍ.',
  };

  static final _localized = <String, Map<String, String>>{'en': _en, 'ar': _ar};

  String t(String key, {Map<String, String> params = const {}}) {
    var value = _localized[locale.languageCode]?[key] ?? _en[key] ?? key;
    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  String localeName(String languageCode) {
    switch (languageCode) {
      case 'ar':
        return t('arabicLanguage');
      case 'en':
        return t('englishLanguage');
      default:
        return languageCode.toUpperCase();
    }
  }

  String projectStatusLabel(String status) {
    switch (status) {
      case 'active':
        return t('projectStatusActive');
      case 'paused':
        return t('projectStatusPaused');
      case 'completed':
        return t('projectStatusCompleted');
      case 'cancelled':
        return t('projectStatusCancelled');
      default:
        return status;
    }
  }

  String expenseCategoryLabel(String category) {
    switch (category) {
      case 'labor':
        return t('expenseCategoryLabor');
      case 'worker':
        return t('expenseCategoryWorker');
      case 'contractor':
        return t('expenseCategoryContractor');
      case 'materials':
        return t('expenseCategoryMaterials');
      case 'equipment':
        return t('expenseCategoryEquipment');
      case 'transport':
        return t('expenseCategoryTransport');
      case 'storage':
        return t('expenseCategoryStorage');
      case 'rentals':
        return t('expenseCategoryRentals');
      case 'payments':
        return t('expenseCategoryPayments');
      case 'other':
        return t('expenseCategoryOther');
      default:
        return category;
    }
  }

  String paymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return t('paymentMethodCash');
      case 'bank':
        return t('paymentMethodBank');
      case 'check':
        return t('paymentMethodCheck');
      default:
        return method;
    }
  }

  String paymentStatusLabel(String status) {
    switch (status) {
      case 'unpaid':
        return t('paymentStatusUnpaid');
      case 'partial':
        return t('paymentStatusPartial');
      case 'paid':
        return t('paymentStatusPaid');
      case 'refunded':
        return t('paymentStatusRefunded');
      case 'cancelled':
        return t('paymentStatusCancelled');
      default:
        return status;
    }
  }

  String workerTypeLabel(String type) {
    switch (type) {
      case 'carpenter':
        return t('workerTypeCarpenter');
      case 'electrician':
        return t('workerTypeElectrician');
      case 'plumber':
        return t('workerTypePlumber');
      case 'mason':
        return t('workerTypeMason');
      case 'painter':
        return t('workerTypePainter');
      case 'laborer':
        return t('workerTypeLaborer');
      case 'operator':
        return t('workerTypeOperator');
      case 'other':
        return t('workerTypeOther');
      default:
        return type;
    }
  }

  String subscriptionStatusLabel(String status) {
    switch (status) {
      case 'trial':
        return t('subscriptionStatusTrial');
      case 'active':
        return t('subscriptionStatusActive');
      case 'grace':
        return t('subscriptionStatusGrace');
      case 'expired':
        return t('subscriptionStatusExpired');
      case 'canceled':
        return t('subscriptionStatusCanceled');
      default:
        return t('subscriptionStatusUnknown');
    }
  }

  String limitTitle(String limitType) {
    switch (limitType) {
      case 'activeProjects':
        return t('activeProjectLimitReached');
      case 'expensesPerMonth':
        return t('monthlyExpenseLimitReached');
      case 'paymentsPerMonth':
        return t('monthlyPaymentLimitReached');
      case 'workerEntriesPerMonth':
        return t('monthlyWorkerEntryLimitReached');
      case 'teamMembers':
        return t('teamMemberLimitReached');
      default:
        return t('usageLimitReached');
    }
  }

  String limitMessage(String limitType, {int? current, int? max}) {
    if (current == null || max == null) {
      return t('freePlanLimitsMessage');
    }
    return t(
      'limitUsageMessage',
      params: {
        'current': '$current',
        'max': '$max',
        'limitLabel': limitUsageLabel(limitType),
        'upgradeAction': limitUpgradeAction(limitType),
      },
    );
  }

  String limitUsageLabel(String limitType) {
    switch (limitType) {
      case 'activeProjects':
        return t('limitUsageActiveProjects');
      case 'expensesPerMonth':
        return t('limitUsageExpenses');
      case 'paymentsPerMonth':
        return t('limitUsagePayments');
      case 'workerEntriesPerMonth':
        return t('limitUsageWorkerEntries');
      case 'teamMembers':
        return t('limitUsageTeamMembers');
      default:
        return t('limitUsageGeneric');
    }
  }

  String limitUpgradeAction(String limitType) {
    switch (limitType) {
      case 'activeProjects':
        return t('limitUpgradeActionActiveProjects');
      case 'expensesPerMonth':
        return t('limitUpgradeActionExpenses');
      case 'paymentsPerMonth':
        return t('limitUpgradeActionPayments');
      case 'workerEntriesPerMonth':
        return t('limitUpgradeActionWorkerEntries');
      case 'teamMembers':
        return t('limitUpgradeActionTeamMembers');
      default:
        return t('limitUpgradeActionGeneric');
    }
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (it) => it.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
