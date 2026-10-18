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

void main() {
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });

  testWidgets(
    'closed-room continuation can select a corner in another room',
    (tester) async {
      final source = RoomModel(
        id: 'source',
        name: 'Source room',
        type: RoomType.living,
        isClosed: true,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 3),
          ARPoint(x: 0, y: 0, z: 3),
        ],
      );
      final target = RoomModel(
        id: 'target',
        name: 'Target room',
        type: RoomType.other,
        isClosed: true,
        points: [
          ARPoint(x: 10, y: 0, z: 0),
          ARPoint(x: 14, y: 0, z: 0),
          ARPoint(x: 14, y: 0, z: 3),
          ARPoint(x: 10, y: 0, z: 3),
        ],
      );
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'cross-room-continuation',
          name: 'Plan',
          rooms: [source, target],
        );
      final settings = MeasurementSettingsProvider();
      addTearDown(provider.dispose);
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FloorPlanProvider>.value(value: provider),
            ChangeNotifierProvider<MeasurementSettingsProvider>.value(
              value: settings,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const FloorPlanViewerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Offset location(double x, double z) {
        final canvas = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is FloorPlanPainter,
        );
        final painter =
            tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
        return tester.getTopLeft(canvas) +
            painter.transform(ARPoint(x: x, y: 0, z: z));
      }

      await tester.tapAt(location(0, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-continue-scan')));
      await tester.pumpAndSettle();

      expect(find.text('How do you want to continue the scan?'), findsOneWidget);
      await tester.tap(find.text('Connect to another corner'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose the corner where you want to close'),
        findsOneWidget,
      );

      // The source room is at x=0..4; this corner belongs to the other room.
      await tester.tapAt(location(10, 0));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'closed-room continuation can select a point on another room wall',
    (tester) async {
      final source = RoomModel(
        id: 'source', name: 'Source room', type: RoomType.living,
        isClosed: true,
        points: [ARPoint(x: 0, y: 0, z: 0), ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 3), ARPoint(x: 0, y: 0, z: 3)],
      );
      final target = RoomModel(
        id: 'target', name: 'Target room', type: RoomType.other,
        isClosed: true,
        points: [ARPoint(x: 10, y: 0, z: 0), ARPoint(x: 14, y: 0, z: 0),
          ARPoint(x: 14, y: 0, z: 3), ARPoint(x: 10, y: 0, z: 3)],
      );
      final originalTargetPoints = List<ARPoint>.from(target.points);
      final provider = FloorPlanProvider()
        ..loadProject(uuid: 'wall-point-continuation', name: 'Plan',
          rooms: [source, target]);
      final settings = MeasurementSettingsProvider();
      addTearDown(provider.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<FloorPlanProvider>.value(value: provider),
          ChangeNotifierProvider<MeasurementSettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FloorPlanViewerScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      Offset location(double x, double z) {
        final canvas = find.byWidgetPredicate((w) =>
          w is CustomPaint && w.painter is FloorPlanPainter);
        final painter = tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
        return tester.getTopLeft(canvas) + painter.transform(ARPoint(x: x, y: 0, z: z));
      }
      await tester.tapAt(location(0, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-continue-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect directly to another wall'));
      await tester.pumpAndSettle();
      // The canvas instruction uses the generic closing-corner prompt while
      // the point mode accepts both corners and wall segments.
      expect(find.text('Choose the corner where you want to close'),
        findsOneWidget);
      // Midpoint of the target's top wall: not a corner.
      await tester.tapAt(location(12, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(provider.completedRooms.firstWhere((r) => r.id == 'target').points,
        equals(originalTargetPoints));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'free-direction continuation asks for a direction without a closing target',
    (tester) async {
      final source = RoomModel(
        id: 'source', name: 'Source room', type: RoomType.living,
        isClosed: true,
        points: [ARPoint(x: 0, y: 0, z: 0), ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 3), ARPoint(x: 0, y: 0, z: 3)],
      );
      final target = RoomModel(
        id: 'target', name: 'Target room', type: RoomType.other,
        isClosed: true,
        points: [ARPoint(x: 10, y: 0, z: 0), ARPoint(x: 14, y: 0, z: 0),
          ARPoint(x: 14, y: 0, z: 3), ARPoint(x: 10, y: 0, z: 3)],
      );
      final provider = FloorPlanProvider()
        ..loadProject(uuid: 'free-direction-continuation', name: 'Plan',
          rooms: [source, target]);
      final settings = MeasurementSettingsProvider();
      addTearDown(provider.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<FloorPlanProvider>.value(value: provider),
          ChangeNotifierProvider<MeasurementSettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FloorPlanViewerScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      Offset location(double x, double z) {
        final canvas = find.byWidgetPredicate((w) =>
          w is CustomPaint && w.painter is FloorPlanPainter);
        final painter = tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
        return tester.getTopLeft(canvas) + painter.transform(ARPoint(x: x, y: 0, z: z));
      }
      await tester.tapAt(location(0, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plan-continue-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue without connecting'));
      await tester.pumpAndSettle();
      expect(find.text('Which way does the floor plan continue?'), findsOneWidget);
      expect(find.text('To the left'), findsOneWidget);
      expect(find.text('To the right'), findsOneWidget);
      await tester.tap(find.text('To the left'));
      await tester.pumpAndSettle();
      // The free mode goes to direction selection, not the closing-point picker.
      expect(find.text('Choose the corner where you want to close'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

}
