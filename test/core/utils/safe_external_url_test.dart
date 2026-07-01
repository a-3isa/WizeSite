import 'package:buildtrack_app/core/utils/safe_external_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows only explicit web and email URLs by default', () {
    expect(safeExternalUrlOrNull('https://buildozer.app/privacy'), isNotNull);
    expect(safeExternalUrlOrNull('http://example.com/receipt.pdf'), isNotNull);
    expect(safeExternalUrlOrNull('mailto:support@buildozer.app'), isNotNull);
  });

  test('rejects script, data, file, and relative URLs', () {
    expect(safeExternalUrlOrNull('javascript:alert(1)'), isNull);
    expect(safeExternalUrlOrNull('data:text/html,<script>1</script>'), isNull);
    expect(safeExternalUrlOrNull('file:///tmp/receipt.pdf'), isNull);
    expect(safeExternalUrlOrNull('/tmp/receipt.pdf'), isNull);
    expect(safeExternalUrlOrNull('C:\\tmp\\receipt.pdf'), isNull);
  });

  test('requires hosts for web URLs and an address for mailto URLs', () {
    expect(safeExternalUrlOrNull('https:///missing-host'), isNull);
    expect(safeExternalUrlOrNull('mailto:'), isNull);
    expect(safeExternalUrlOrNull('  '), isNull);
  });
}
