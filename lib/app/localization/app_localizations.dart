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

  static const _en = <String, String>{
    'appName': 'Buildozer',
    'tagline': 'Smart Construction Management',
    'home': 'Home',
    'projects': 'Projects',
    'add': 'Add',
    'reports': 'Reports',
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
    'limitReached': 'Limit Reached',
    'continue': 'Continue',
    'confirm': 'Confirm',
    'save': 'Save',
    'cancel': 'Cancel',
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
    'dontHaveAccount': "Don't have an account?",
    'alreadyHaveAccount': 'Already have an account?',
    'fullName': 'Full Name',
    'confirmPassword': 'Confirm Password',
    'companyNameOptional': 'Company Name (optional)',
    'phoneNumberOptional': 'Phone Number (optional)',
    'phoneNumber': 'Phone Number',
    'sendResetLink': 'Send reset link',
    'resetLinkSent': 'Reset link sent to your email.',
    'signInCancelled': 'Sign-in was cancelled or could not complete.',
    'pleaseEnterEmailAndPassword': 'Please enter your email and password.',
    'authNoAccountFound':
        'No account found with this email. Check the address or sign up.',
    'authIncorrectPassword': 'Incorrect password. Please try again.',
    'authInvalidEmail': 'Please enter a valid email address.',
    'authAccountDisabled':
        'This account has been disabled. Contact support.',
    'authTooManyAttempts': 'Too many attempts. Please try again later.',
    'authNetworkError': 'Network error. Check your connection and try again.',
    'authDifferentProvider':
        'An account already exists with this email. Try signing in with email and password.',
    'authSignInFailed':
        'Sign-in failed. Please check your email and password and try again.',
    'authInvalidEmailFormat': 'Invalid email format',
    'authPasswordMinLength': 'Password must be at least 8 characters',
    'authPasswordsDoNotMatch': 'Passwords do not match',
    'pleaseLoginFirst': 'Please login first.',
    'overview': 'Overview',
    'quickActions': 'Quick Actions',
    'totalExpenses': 'Total Expenses',
    'totalIncome': 'Total Income',
    'netProfit': 'Net Profit',
    'unlockHigherLimits': 'Unlock higher limits and team scaling',
    'profit': 'Profit',
    'loss': 'Loss',
    'noWorkspaceSelected': 'No workspace selected yet.',
    'quickAdd': 'Quick Add',
    'expenseList': 'Expense List',
    'paymentList': 'Payment List',
    'addExpenseSubtitle': 'Record a new project expense in seconds.',
    'expenseListSubtitle': 'View, edit, and archive expenses.',
    'addPaymentSubtitle': 'Record client payment and update balance.',
    'paymentListSubtitle': 'View, edit, and archive payments.',
    'addWorkerEntrySubtitle': 'Capture labor days and auto-calculate cost.',
    'createProjectSubtitle': 'Create a new project with contract details.',
    'voiceExpenseSubtitle': 'Speak naturally, confirm parsed result, then save.',
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
    'budgetLimit': 'Budget Limit',
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
    'paymentMethod': 'Payment Method',
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
    'saveWorker': 'Save Worker',
    'updateWorker': 'Update Worker',
    'addWorkerTitle': 'Add Worker',
    'editWorkerTitle': 'Edit Worker',
    'addWorkerEntryTitle': 'Add Worker Entry',
    'editWorkerEntryTitle': 'Edit Worker Entry',
    'daysWorked': 'Days Worked',
    'saveWorkerEntry': 'Save Worker Entry',
    'updateWorkerEntry': 'Update Worker Entry',
    'nameAndValidWageRequired': 'Name and valid daily wage are required.',
    'fillWorkerProjectDaysWage': 'Fill worker, project, days, and wage.',
    'recentEntries': 'Recent Entries',
    'noEntriesYet': 'No entries yet.',
    'totalLaborCost': 'Total Labor Cost',
    'editWorker': 'Edit Worker',
    'addEntry': 'Add Entry',
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
    'usagePeriod': 'Usage period: {period} | expenses {count}/{limit}',
    'totalProjects': 'Total Projects: {value}',
    'activeProjectsCount': 'Active Projects: {value}',
    'netProfitLoss': 'Net Profit/Loss: {value}',
    'notificationsTitle': 'Notifications',
    'noNotificationsYet': 'No notifications yet.',
    'recordShortNote':
        'Record a short note (5 to 20 seconds), then review before saving.',
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
    'maybeLater': 'Maybe later',
    'purchaseCancelled': 'Purchase was cancelled.',
    'nativePaywallNotSupported':
        'Native paywall is not supported on this platform.',
    'paywallFailed': 'Paywall failed. Please try again.',
    'continueWithPaywall': 'Continue with RevenueCat Paywall',
    'purchaseNotCompleted': 'Purchase was not completed.',
    'proUnlocksSubtitle':
        'WizeSite Pro unlocks higher usage limits and operational scale.',
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
    'wizeSiteProEntitlement': 'WizeSite Pro Entitlement',
    'currentProduct': 'Current Product',
    'entitlementExpiration': 'Entitlement Expiration',
    'entitlementActive': 'Active',
    'entitlementInactive': 'Not active',
    'paymentMethodCash': 'Cash',
    'paymentMethodBank': 'Bank Transfer',
    'paymentMethodCheck': 'Check',
    'expenseCategoryLabor': 'Labor',
    'expenseCategoryMaterials': 'Materials',
    'expenseCategoryEquipment': 'Equipment',
    'expenseCategoryTransport': 'Transport',
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
    'workerEntryLine': '{days} d × {wage} = {total}',
  };

  static final _ar = <String, String>{
    ..._en,
    'appName': 'بيلدوزر',
    'tagline': 'إدارة ذكية لمشاريع البناء',
    'home': 'الرئيسية',
    'projects': 'المشاريع',
    'add': 'إضافة',
    'reports': 'التقارير',
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
    'limitReached': 'تم الوصول للحد',
    'continue': 'متابعة',
    'confirm': 'تأكيد',
    'save': 'حفظ',
    'cancel': 'إلغاء',
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
    'dontHaveAccount': 'ليس لديك حساب؟',
    'alreadyHaveAccount': 'لديك حساب بالفعل؟',
    'fullName': 'الاسم الكامل',
    'confirmPassword': 'تأكيد كلمة المرور',
    'companyNameOptional': 'اسم الشركة (اختياري)',
    'phoneNumberOptional': 'رقم الهاتف (اختياري)',
    'phoneNumber': 'رقم الهاتف',
    'sendResetLink': 'إرسال رابط إعادة التعيين',
    'resetLinkSent': 'تم إرسال رابط إعادة التعيين إلى بريدك.',
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
    'authInvalidEmailFormat': 'تنسيق البريد الإلكتروني غير صحيح',
    'authPasswordMinLength': 'يجب أن تكون كلمة المرور 8 أحرف على الأقل',
    'authPasswordsDoNotMatch': 'كلمتا المرور غير متطابقتين',
    'pleaseLoginFirst': 'يرجى تسجيل الدخول أولاً.',
    'overview': 'نظرة عامة',
    'quickActions': 'إجراءات سريعة',
    'totalExpenses': 'إجمالي المصروفات',
    'totalIncome': 'إجمالي الإيرادات',
    'netProfit': 'صافي الربح',
    'unlockHigherLimits': 'افتح حدود استخدام أعلى وتوسّع الفريق',
    'profit': 'ربح',
    'loss': 'خسارة',
    'noWorkspaceSelected': 'لا توجد مساحة عمل محددة بعد.',
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
    'budgetLimit': 'حد الميزانية',
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
    'saveWorker': 'حفظ العامل',
    'updateWorker': 'تحديث العامل',
    'addWorkerTitle': 'إضافة عامل',
    'editWorkerTitle': 'تعديل عامل',
    'addWorkerEntryTitle': 'إضافة سجل عامل',
    'editWorkerEntryTitle': 'تعديل سجل عامل',
    'daysWorked': 'أيام العمل',
    'saveWorkerEntry': 'حفظ سجل العامل',
    'updateWorkerEntry': 'تحديث سجل العامل',
    'nameAndValidWageRequired': 'اسم العامل وأجر يومي صحيح مطلوبان.',
    'fillWorkerProjectDaysWage': 'املأ العامل والمشروع والأيام والأجر.',
    'recentEntries': 'أحدث السجلات',
    'noEntriesYet': 'لا توجد سجلات بعد.',
    'totalLaborCost': 'إجمالي تكلفة العمالة',
    'editWorker': 'تعديل العامل',
    'addEntry': 'إضافة سجل',
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
    'usagePeriod': 'فترة الاستخدام: {period} | المصروفات {count}/{limit}',
    'totalProjects': 'إجمالي المشاريع: {value}',
    'activeProjectsCount': 'المشاريع النشطة: {value}',
    'netProfitLoss': 'صافي الربح/الخسارة: {value}',
    'notificationsTitle': 'الإشعارات',
    'noNotificationsYet': 'لا توجد إشعارات بعد.',
    'recordShortNote':
        'سجّل ملاحظة قصيرة (من 5 إلى 20 ثانية)، ثم راجعها قبل الحفظ.',
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
    'maybeLater': 'لاحقاً',
    'purchaseCancelled': 'تم إلغاء عملية الشراء.',
    'nativePaywallNotSupported':
        'شاشة الدفع الأصلية غير مدعومة على هذا النظام.',
    'paywallFailed': 'فشلت شاشة الدفع. حاول مرة أخرى.',
    'continueWithPaywall': 'المتابعة عبر شاشة RevenueCat',
    'purchaseNotCompleted': 'لم تكتمل عملية الشراء.',
    'proUnlocksSubtitle': 'خطة WizeSite Pro تفتح حدود استخدام أعلى وتوسعاً أكبر.',
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
    'wizeSiteProEntitlement': 'استحقاق WizeSite Pro',
    'currentProduct': 'المنتج الحالي',
    'entitlementExpiration': 'انتهاء الاستحقاق',
    'entitlementActive': 'نشط',
    'entitlementInactive': 'غير نشط',
    'paymentMethodCash': 'نقداً',
    'paymentMethodBank': 'تحويل بنكي',
    'paymentMethodCheck': 'شيك',
    'expenseCategoryLabor': 'عمالة',
    'expenseCategoryMaterials': 'مواد',
    'expenseCategoryEquipment': 'معدات',
    'expenseCategoryTransport': 'نقل',
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
    'workerEntryLine': '{days} يوم × {wage} = {total}',
  };

  static final _localized = <String, Map<String, String>>{
    'en': _en,
    'ar': _ar,
  };

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
      case 'materials':
        return t('expenseCategoryMaterials');
      case 'equipment':
        return t('expenseCategoryEquipment');
      case 'transport':
        return t('expenseCategoryTransport');
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
