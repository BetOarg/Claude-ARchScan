import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:room_scanner_ar/l10n/generated/app_localizations.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';
import 'package:room_scanner_ar/providers/measurement_settings_provider.dart';
import 'package:room_scanner_ar/screens/floor_plan_viewer_screen.dart';
import 'package:room_scanner_ar/widgets/plan_wall_length_dialog.dart';

void main() {
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });
  Future<FloorPlanProvider> mount(WidgetTester tester,
      {String locale = 'en'}) async {
    final provider = FloorPlanProvider()
      ..loadProject(uuid: 'test', name: 'Plan', rooms: [
        RoomModel(
          id: 'room',
          name: 'Living',
          type: RoomType.living,
          isClosed: true,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 3),
            ARPoint(x: 0, y: 0, z: 3),
          ],
        )
      ]);
    final settings = MeasurementSettingsProvider();
    addTearDown(provider.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<FloorPlanProvider>.value(value: provider),
          ChangeNotifierProvider<MeasurementSettingsProvider>.value(
              value: settings),
        ],
        child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const FloorPlanViewerScreen())));
    await tester.pumpAndSettle();
    return provider;
  }

  Offset location(WidgetTester tester, double x, double z) {
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
    return tester.getTopLeft(canvas) +
        painter.transform(ARPoint(x: x, y: 0, z: z));
  }

  testWidgets('toolbar places a door on tapped wall and undo/redo restores it',
      (tester) async {
    final provider = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('plan-add-door')));
    await tester.pumpAndSettle();
    await tester.tapAt(location(tester, 2, 0));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.features, hasLength(1));
    expect(provider.completedRooms.single.features.single.start.z, 0);
    await tester.tap(find.byKey(const ValueKey('plan-undo')));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.features, isEmpty);
    await tester.tap(find.byKey(const ValueKey('plan-redo')));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.features, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final remainingPoints in [0, 1]) {
    testWidgets(
        'delete empty room with $remainingPoints points from list, cancel and undo/redo',
        (tester) async {
      final provider = await mount(tester, locale: 'es');
      final remnant = provider.completedRooms.single.copyWith(
        points: remainingPoints == 0 ? [] : [ARPoint(x: 0, y: 0, z: 0)],
        isClosed: false,
      );
      provider.loadProject(uuid: 'test', name: 'Plan', rooms: [remnant]);
      await tester.pumpAndSettle();
      Future<void> requestDelete() async {
        await tester.tap(find.text('Ambientes registrados'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('room-actions-room')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar ambiente'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      }

      await requestDelete();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(provider.completedRooms, hasLength(1));
      expect(provider.canUndoTransform, isFalse);
      await requestDelete();
      await tester.tap(find.byKey(const ValueKey('plan-confirm-delete-room')));
      await tester.pumpAndSettle();
      expect(provider.completedRooms, isEmpty);
      await tester.tap(find.byKey(const ValueKey('plan-undo')));
      await tester.pumpAndSettle();
      expect(provider.completedRooms.single.toJson(), remnant.toJson());
      await tester.tap(find.byKey(const ValueKey('plan-redo')));
      await tester.pumpAndSettle();
      expect(provider.completedRooms, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('delete a complete room directly from selected wall',
      (tester) async {
    final provider = await mount(tester);
    await tester.tapAt(location(tester, 2, 0));
    await tester.pumpAndSettle();
    final delete = find.byKey(const ValueKey('plan-delete-room'));
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-confirm-delete-room')));
    await tester.pumpAndSettle();
    expect(provider.completedRooms, isEmpty);
    expect(provider.canUndoTransform, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continuation start and closing corners are selected on plan',
      (tester) async {
    await mount(tester);
    await tester.tapAt(location(tester, 0, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-continue-scan')));
    await tester.pumpAndSettle();

    expect(find.text('Choose the corner where you want to close'),
        findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tapAt(location(tester, 4, 3));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit selected wall in place, confirm, delete and undo',
      (tester) async {
    final provider = await mount(tester);
    await tester.tapAt(location(tester, 2, 0));
    await tester.pumpAndSettle();
    expect(find.text('Living · Wall 1'), findsOneWidget);
    await tester.tap(find.text('Edit measurements'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanWallLengthDialog), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('plan-wall-length')), '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Preview on plan'));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.points[1].x, 4);
    expect(find.byType(FloorPlanViewerScreen), findsOneWidget);
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.points[1].x, 5);
    await tester.tapAt(location(tester, 2, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete wall'));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.isClosed, isTrue);
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.isClosed, isFalse);
    await tester.tap(find.byKey(const ValueKey('plan-undo')));
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.isClosed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected wall drags directly and remains undoable',
      (tester) async {
    final provider = await mount(tester);
    await tester.tapAt(location(tester, 2, 0));
    await tester.pumpAndSettle();
    final start = location(tester, 2, 0);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(provider.completedRooms.single.points.first.z, lessThan(0));
    expect(provider.completedRooms.single.points[1].z,
        provider.completedRooms.single.points.first.z);
    expect(provider.canUndoTransform, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Spanish narrow layout keeps all controls available without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, locale: 'es');
    for (final key in [
      'plan-add-door',
      'plan-add-window',
      'plan-undo',
      'plan-redo'
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    final doorCenter =
        tester.getCenter(find.byKey(const ValueKey('plan-add-door')));
    final windowCenter =
        tester.getCenter(find.byKey(const ValueKey('plan-add-window')));
    final undoCenter =
        tester.getCenter(find.byKey(const ValueKey('plan-undo')));
    final redoCenter =
        tester.getCenter(find.byKey(const ValueKey('plan-redo')));
    expect(doorCenter.dy, windowCenter.dy);
    expect(undoCenter.dy, redoCenter.dy);
    expect(undoCenter.dy, greaterThan(doorCenter.dy));
    expect(tester.takeException(), isNull);
    await tester.tapAt(location(tester, 2, 3));
    await tester.pumpAndSettle();
    final canvas = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FloorPlanPainter);
    expect(tester.getRect(canvas).contains(location(tester, 2, 3)), isTrue);
    expect(find.text('Living · Pared 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch-drag snaps a room to a nearby wall', (tester) async {
    final provider = await mount(tester);
    RoomModel square(String id, double x) => RoomModel(
          id: id,
          name: id,
          type: RoomType.other,
          isClosed: true,
          points: [
            ARPoint(x: x, y: 0, z: 0),
            ARPoint(x: x + 2, y: 0, z: 0),
            ARPoint(x: x + 2, y: 0, z: 2),
            ARPoint(x: x, y: 0, z: 2),
          ],
        );
    provider.loadProject(
      uuid: 'touch-magnet-widget',
      name: 'Plan',
      rooms: [square('anchor', 0), square('movable', 4)],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move rooms with gestures'));
    await tester.pumpAndSettle();

    final start = location(tester, 5, 1);
    final end = location(tester, 3.1, 1);
    // Select the room first so the drag does not depend on edge hit-testing.
    await tester.tapAt(start);
    await tester.pumpAndSettle();
    await tester.dragFrom(start, end - start, touchSlopY: 0);
    await tester.pumpAndSettle();

    final moved = provider.completedRooms.singleWhere(
      (room) => room.id == 'movable',
    );
    expect(moved.points.first.x, closeTo(2, 0.00001));
    expect(moved.points.last.x, closeTo(2, 0.00001));
    expect(provider.canUndoTransform, isTrue);
    expect(tester.takeException(), isNull);
  });
}
