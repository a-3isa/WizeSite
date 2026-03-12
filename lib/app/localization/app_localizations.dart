import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return value ?? AppLocalizations(const Locale('en'));
  }

  static const supportedLocales = <Locale>[Locale('ar'), Locale('en')];

  static const _localized = <String, Map<String, String>>{
    'en': {
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
    },
    'ar': {
      'appName': 'بيلد تراك',
      'tagline': 'إدارة ذكية للمشاريع الإنشائية',
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
      'welcome': 'مرحبًا بك في بيلد تراك',
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
    },
  };

  String t(String key) =>
      _localized[locale.languageCode]?[key] ?? _localized['en']![key] ?? key;
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
