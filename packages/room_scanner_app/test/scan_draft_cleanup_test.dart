import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_scanner_ar/services/scan_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearAll removes orphan drafts but preserves unrelated settings', () async {
    SharedPreferences.setMockInitialValues({
      'scan_draft_v1_a': '{}',
      'scan_draft_v1_deleted-project': '{}',
      'measurement_system': 'imperial',
    });
    await const ScanDraftService().clearAll();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'measurement_system'});
  });

  test('clear removes only the selected project draft', () async {
    SharedPreferences.setMockInitialValues({
      'scan_draft_v1_a': '{}',
      'scan_draft_v1_b': '{}',
    });
    await const ScanDraftService().clear('a');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'scan_draft_v1_b'});
  });
}
