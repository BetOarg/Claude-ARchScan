import 'dart:convert';

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

  test('draft round-trip preserves cross-room continuation and point history', () async {
    SharedPreferences.setMockInitialValues({});
    const service = ScanDraftService();
    final sourcePoint = ARPoint(x: 1, y: 0, z: 2);
    final targetPoint = ARPoint(x: 4, y: 0, z: 5);
    final reference = ScanContinuationReference.fromCorners(
      sourceRoomId: 'source-room',
      sourcePoint: sourcePoint,
      targetRoomId: 'target-room',
      targetPoint: targetPoint,
    );
    final history = [
      ARPoint(x: 0, y: 0, z: 0),
      ARPoint(x: 2, y: 0, z: 0),
    ];

    await service.save(
      projectUuid: 'continuation-round-trip',
      room: room('draft-room'),
      continuationReference: reference,
      basicHistory: history,
    );

    final restored = await service.load('continuation-round-trip');
    expect(restored, isNotNull);
    expect(restored!.continuationReference!.sourceRoomId, 'source-room');
    expect(restored.continuationReference!.targetRoomId, 'target-room');
    expect(restored.continuationReference!.targetGlobalPoint!.toJson(),
        targetPoint.toJson());
    expect(restored.continuationReference!.globalStart.toJson(),
        sourcePoint.toJson());
    expect(restored.basicHistory.map((point) => point.toJson()).toList(),
        history.map((point) => point.toJson()).toList());
  });

  test('does not delete drafts written by a newer format version', () async {
    SharedPreferences.setMockInitialValues({
      'scan_draft_v1_future': jsonEncode({'version': 2}),
    });
    const service = ScanDraftService();

    expect(await service.load('future'), isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('scan_draft_v1_future'), jsonEncode({'version': 2}));
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

  test('load ignores drafts for permanently deleted projects', () async {
    SharedPreferences.setMockInitialValues({
      'scan_draft_v1_deleted-load': '{}',
    });
    const service = ScanDraftService();

    await service.clear('deleted-load', permanentlyDeleted: true);

    expect(await service.load('deleted-load'), isNull);
  });

  test('orphan cleanup removes only drafts for missing projects', () async {
    SharedPreferences.setMockInitialValues({
      'scan_draft_v1_valid-project': jsonEncode({'version': 2}),
      'scan_draft_v1_orphan-project': '{}',
      'measurement_system': 'imperial',
      'theme_mode': 'dark',
    });

    await const ScanDraftService().clearOrphanedDrafts({'valid-project'});

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('scan_draft_v1_valid-project'),
        jsonEncode({'version': 2}));
    expect(preferences.containsKey('scan_draft_v1_orphan-project'), isFalse);
    expect(preferences.getString('measurement_system'), 'imperial');
    expect(preferences.getString('theme_mode'), 'dark');
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

  test('clear succeeds when the project has no draft', () async {
    SharedPreferences.setMockInitialValues({
      'measurement_system': 'imperial',
    });

    await const ScanDraftService().clear('missing-project');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'measurement_system'});
  });

  test('load is ordered after a queued draft mutation', () async {
    SharedPreferences.setMockInitialValues({
      'scan_draft_v1_ordered': '{}',
    });
    const service = ScanDraftService();

    final clear = service.clear('ordered');
    final load = service.load('ordered');

    await clear;
    expect(await load, isNull);
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
