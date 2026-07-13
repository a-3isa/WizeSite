class AppRoutes {
  static const String root = '/';
  static const String features = '/features';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String verifyEmail = '/verify-email';
  static const String initialWorkspaceSetup = '/setup/workspace';

  static const String dashboard = '/dashboard';
  static const String projects = '/projects';
  static const String activity = '/activity';
  static const String more = '/more';
  static const String archivedProjects = '/projects/archived';
  static const String reports = '/reports';
  static const String entitySummary = '/entity-summary';
  static const String settings = '/settings';
  static const String profileEdit = '/settings/profile';
  static const String workspaceSettings = '/settings/workspace';
  static const String syncStatus = '/settings/sync';

  static const String createProject = '/create-project';
  static const String projectDetail = '/project/:id';
  static const String projectEdit = '/project/:id/edit';
  static const String projectExpenses = '/project/:projectId/expenses';

  static const String addExpense = '/add-expense';
  static const String expenseDetail = '/expense/:id';
  static const String expenseEdit = '/expense/:id/edit';

  static const String payments = '/payments';
  static const String paymentDetail = '/payment/:id';
  static const String paymentEdit = '/payment/:id/edit';

  static const String voiceExpense = '/voice-expense';
  static const String addPayment = '/add-payment';
  static const String workers = '/workers';
  static const String contractorsDirectory = '/contractors';
  static const String equipmentDirectory = '/equipment';
  static const String transportProvidersDirectory = '/transport-providers';
  static const String workerDetail = '/worker/:id';
  static const String workerEdit = '/worker/:id/edit';
  static const String addWorker = '/add-worker';
  static const String workerEntry = '/worker-entry/:id';
  static const String workerAccounting = '/worker-accounting/:id';
  static const String contractors = '/contractors/:id';
  static const String equipment = '/equipment/:id';
  static const String transportProviders = '/transport-providers/:id';
  static const String notifications = '/notifications';

  static const String subscriptionPlans = '/subscription/plans';
  static const String subscriptionLimit = '/subscription/limit';
  static const String subscriptionManage = '/subscription/manage';
  static const String subscriptionSuccess = '/subscription/success';

  static String projectDetailPath(String id) => '/project/$id';
  static String projectEditPath(String id) => '/project/$id/edit';
  static String projectExpensesPath(String projectId) =>
      '/project/$projectId/expenses';

  static String addExpensePath({String? projectId}) =>
      _withOptionalQuery(addExpense, {'projectId': projectId});
  static String expenseDetailPath(String id, {String? projectId}) =>
      _withOptionalQuery('/expense/$id', {'projectId': projectId});
  static String expenseEditPath(String id, {String? projectId}) =>
      _withOptionalQuery('/expense/$id/edit', {'projectId': projectId});

  static String addPaymentPath({String? projectId}) =>
      _withOptionalQuery(addPayment, {'projectId': projectId});
  static String paymentsPath({String? projectId}) =>
      _withOptionalQuery(payments, {'projectId': projectId});
  static String paymentDetailPath(String id, {String? projectId}) =>
      _withOptionalQuery('/payment/$id', {'projectId': projectId});
  static String paymentEditPath(String id, {String? projectId}) =>
      _withOptionalQuery('/payment/$id/edit', {'projectId': projectId});

  static String workerDetailPath(String id) => '/worker/$id';
  static String workerEditPath(String id) => '/worker/$id/edit';
  static String contractorsDirectoryPath() => contractorsDirectory;
  static String equipmentDirectoryPath() => equipmentDirectory;
  static String transportProvidersDirectoryPath() =>
      transportProvidersDirectory;
  static String workerEntryPath(String id, {String? projectId}) =>
      _withOptionalQuery('/worker-entry/$id', {'projectId': projectId});
  static String workerAccountingPath(
    String id, {
    String? name,
    String? projectId,
  }) => _withOptionalQuery('/worker-accounting/$id', {
    'name': name,
    'projectId': projectId,
  });
  static String contractorsPath(String id, {String? name, String? projectId}) =>
      _withOptionalQuery('/contractors/$id', {
        'name': name,
        'projectId': projectId,
      });
  static String equipmentPath(String id, {String? name, String? projectId}) =>
      _withOptionalQuery('/equipment/$id', {
        'name': name,
        'projectId': projectId,
      });
  static String transportProvidersPath(
    String id, {
    String? name,
    String? projectId,
  }) => _withOptionalQuery('/transport-providers/$id', {
    'name': name,
    'projectId': projectId,
  });

  static String reportsPath({String? projectId}) =>
      _withOptionalQuery(reports, {'projectId': projectId});
  static String entitySummaryPath() => entitySummary;
  static String subscriptionLimitPath(
    String limitType, {
    int? current,
    int? max,
  }) => _withOptionalQuery(subscriptionLimit, {
    'limit': limitType,
    'current': current?.toString(),
    'max': max?.toString(),
  });

  static String _withOptionalQuery(
    String path,
    Map<String, String?> parameters,
  ) {
    final queryParameters = <String, String>{};
    for (final entry in parameters.entries) {
      final value = entry.value;
      if (value == null || value.isEmpty) {
        continue;
      }
      queryParameters[entry.key] = value;
    }
    return Uri(
      path: path,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }
}
