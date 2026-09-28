import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:room_scanner_ar/services/scan_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RoomModel room(String id) => RoomModel(
        id: id,
        name: id,
        type: RoomType.other,
        points: [ARPoint(x: 0, y: 0, z: 0)],
        isClosed: false,
      );

  test('draft retains original continuation snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    const service = ScanDraftService();
    await service.save(
      projectUuid: 'resume-test',
      room: room('draft'),
      resumeRoom: room('original'),
    );
    final restored = await service.load('resume-test');
    expect(restored!.resumeRoom!.id, 'original');
    expect(restored.room.id, 'draft');
    final legacy = ScanDraft.fromJson({'room': room('legacy').toJson()});
    expect(legacy.resumeRoom, isNull);
  });

  test('continuation metadata and basic history survive round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    const service = ScanDraftService();
    final reference = ScanContinuationReference(
      sourceRoomId: 'source-room',
      featureId: 'door-1',
      featureType: FeatureType.door,
      globalStart: ARPoint(x: 1, y: 2, z: 3),
      globalEnd: ARPoint(x: 4, y: 5, z: 6),
      side: OpeningConnectionSide.right,
      startEndpoint: ContinuationStartEndpoint.end,
    );
    final history = [
      ARPoint(x: 0, y: 0, z: 0),
      ARPoint(x: 1.25, y: 0, z: 2.5),
    ];

    await service.save(
      projectUuid: 'continuation-test',
      room: room('draft'),
      continuationReference: reference,
      basicHistory: history,
    );

    final restored = await service.load('continuation-test');
    expect(restored, isNotNull);
    expect(restored!.continuationReference, isNotNull);
    expect(restored.continuationReference!.sourceRoomId, 'source-room');
    expect(restored.continuationReference!.featureId, 'door-1');
    expect(restored.continuationReference!.featureType, FeatureType.door);
    expect(restored.continuationReference!.globalStart.x, 1);
    expect(restored.continuationReference!.globalEnd.z, 6);
    expect(restored.continuationReference!.side, OpeningConnectionSide.right);
    expect(
      restored.continuationReference!.startEndpoint,
      ContinuationStartEndpoint.end,
    );
    expect(restored.basicHistory, hasLength(2));
    expect(restored.basicHistory[1].x, 1.25);
    expect(restored.basicHistory[1].z, 2.5);
  });

  test('malformed drafts are discarded and do not poison future loads', () async {
    SharedPreferences.setMockInitialValues({
      'scan_draft_v1_corrupt': '{not-json',
    });
    const service = ScanDraftService();

    expect(await service.load('corrupt'), isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('scan_draft_v1_corrupt'), isNull);
  });

  test('deleted projects reject late saves and clear queued drafts', () async {
    SharedPreferences.setMockInitialValues({});
    const service = ScanDraftService();
    final pending = service.save(
      projectUuid: 'deleted-test',
      room: room('draft'),
    );
    final failure = expectLater(pending, throwsStateError);
    final deletion = service.clear(
      'deleted-test',
      permanentlyDeleted: true,
    );
    await failure;
    await deletion;
    await expectLater(
      service.save(projectUuid: 'deleted-test', room: room('late')),
      throwsStateError,
    );
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

  test('clear is idempotent when the project has no draft', () async {
    SharedPreferences.setMockInitialValues({
      'measurement_system': 'metric',
    });
    await const ScanDraftService().clear('missing-project');
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
