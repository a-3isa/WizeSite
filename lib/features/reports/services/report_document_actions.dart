import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Outcome of a print or share/save document action.
enum DocumentActionStatus {
  /// The OS print/share flow finished successfully.
  completed,

  /// The user dismissed the print/share flow without completing it.
  dismissed,

  /// The action threw before completing.
  failed,
}

/// Result of a document action, including the raw error (for logging /
/// sanitization) when the action failed.
class DocumentActionResult {
  const DocumentActionResult(this.status, [this.error]);

  const DocumentActionResult.completed() : this(DocumentActionStatus.completed);
  const DocumentActionResult.dismissed() : this(DocumentActionStatus.dismissed);
  const DocumentActionResult.failed(Object error)
    : this(DocumentActionStatus.failed, error);

  final DocumentActionStatus status;

  /// Populated only when [status] is [DocumentActionStatus.failed]. Callers must
  /// sanitize this through `appErrorMessage` before showing it to the user.
  final Object? error;

  bool get isCompleted => status == DocumentActionStatus.completed;
  bool get isDismissed => status == DocumentActionStatus.dismissed;
  bool get isFailed => status == DocumentActionStatus.failed;
}

/// Returns `true` when the platform flow completed, `false` when dismissed.
typedef DocumentPrintHandler =
    Future<bool> Function(Uint8List bytes, String name);
typedef DocumentShareHandler =
    Future<bool> Function(Uint8List bytes, String filename);

/// Shared adapter over the `printing` package so every feature exposes both a
/// print path ([printDocument]) and a share/save path ([shareDocument]) with
/// consistent completed/dismissed/failed handling.
///
/// PDF byte generation stays in `ReportPdfExporter`; this class only routes the
/// already-built bytes to the OS print or share sheet.
class ReportDocumentActions {
  ReportDocumentActions({
    DocumentPrintHandler? printHandler,
    DocumentShareHandler? shareHandler,
  }) : _printHandler = printHandler ?? _defaultPrint,
       _shareHandler = shareHandler ?? _defaultShare;

  final DocumentPrintHandler _printHandler;
  final DocumentShareHandler _shareHandler;

  Future<DocumentActionResult> printDocument({
    required Uint8List bytes,
    required String name,
  }) {
    return _run(() => _printHandler(bytes, name));
  }

  Future<DocumentActionResult> shareDocument({
    required Uint8List bytes,
    required String filename,
  }) {
    return _run(() => _shareHandler(bytes, filename));
  }

  Future<DocumentActionResult> _run(Future<bool> Function() action) async {
    try {
      final completed = await action();
      return completed
          ? const DocumentActionResult.completed()
          : const DocumentActionResult.dismissed();
    } catch (error) {
      return DocumentActionResult.failed(error);
    }
  }

  static Future<bool> _defaultPrint(Uint8List bytes, String name) {
    return Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  }

  static Future<bool> _defaultShare(Uint8List bytes, String filename) {
    return Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
