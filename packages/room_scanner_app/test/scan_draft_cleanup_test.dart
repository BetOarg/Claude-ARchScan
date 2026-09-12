import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_scanner_ar/services/scan_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RoomModel room(String id) => RoomModel(
      id: id, name: id, type: RoomType.other,
      points: [ARPoint(x: 0, y: 0, z: 0)], isClosed: false);

  test('draft retains original continuation snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    const service = ScanDraftService();
    await service.save(projectUuid: 'resume-test', room: room('draft'),
        resumeRoom: room('original'));
    final restored = await service.load('resume-test');
    expect(restored!.resumeRoom!.id, 'original');
    expect(restored.room.id, 'draft');
    final legacy = ScanDraft.fromJson({'room': room('legacy').toJson()});
    expect(legacy.resumeRoom, isNull);
  });

  test('deleted projects reject late saves and clear queued drafts', () async {
    SharedPreferences.setMockInitialValues({});
    const service = ScanDraftService();
    final pending = service.save(projectUuid: 'deleted-test', room: room('draft'));
    final failure = expectLater(pending, throwsStateError);
    final deletion = service.clear('deleted-test', permanentlyDeleted: true);
    await failure;
    await deletion;
    await expectLater(service.save(projectUuid: 'deleted-test', room: room('late')),
        throwsStateError);
    expect(await service.load('deleted-test'), isNull);
    await service.save(projectUuid: 'other-test', room: room('other'));
    expect(await service.load('other-test'), isNotNull);
  });

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
