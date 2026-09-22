import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import '../lib/providers/floor_plan_provider.dart';
import '../lib/providers/measurement_settings_provider.dart';
import '../lib/screens/floor_plan_viewer_screen.dart';
import '../lib/screens/measurement_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import '../lib/l10n/generated/app_localizations.dart';
import '../lib/services/recent_room_names_service.dart';
import '../lib/widgets/room_name_dialog.dart';
import '../lib/widgets/room_completion_dialog.dart';

void main() {
  setUp(() {
    final previousPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() {
      SharedPreferencesAsyncPlatform.instance = previousPreferences;
    });
  });


  for (final save in [false, true]) {
    testWidgets('wall editor closes safely with focused field (save: $save)', (tester) async {
      final room = RoomModel(
        id: 'room', name: 'Room', type: RoomType.living, isClosed: true,
        points: [
          ARPoint(x: 0, y: 0, z: 0), ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 3), ARPoint(x: 0, y: 0, z: 3),
        ],
      );
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'wall-editor', name: 'Plan', rooms: [room],
      );
      final settings = MeasurementSettingsProvider();
      addTearDown(provider.dispose);
      addTearDown(settings.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<FloorPlanProvider>.value(value: provider),
          ChangeNotifierProvider<MeasurementSettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MeasurementEditorScreen(roomId: 'room'),
        ),
      ));
      await tester.pumpAndSettle();
      final edit = find.byTooltip('Editar medida').first;
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MeasurementEditorScreen)),
      )!;
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == l10n.newLength,
      );
      await tester.enterText(field, '5');
      final action = find.text(save ? l10n.save : l10n.cancel);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      final points = provider.completedRooms.single.points;
      expect((points[1].x - points[0].x).abs(), closeTo(save ? 5 : 4, 1e-8));
    });
  }

  for (final type in FeatureType.values) {
    testWidgets('editing ${type.name} distance closes safely with field focused', (tester) async {
      final feature = WallFeature(
        id: 'opening', type: type,
        start: ARPoint(x: 1, y: 0, z: 0),
        end: ARPoint(x: 2, y: 0, z: 0),
      );
      final provider = FloorPlanProvider()..loadProject(
        uuid: 'p', name: 'Plan', rooms: [RoomModel(
          id: 'room', name: 'Room', type: RoomType.living, isClosed: true,
          points: [
            ARPoint(x: 0, y: 0, z: 0), ARPoint(x: 4, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 3), ARPoint(x: 0, y: 0, z: 3),
          ], features: [feature],
        )],
      );
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
      final canvas = find.byWidgetPredicate((w) =>
          w is CustomPaint && w.painter is FloorPlanPainter);
      final painter = tester.widget<CustomPaint>(canvas).painter! as FloorPlanPainter;
      final position = painter.transform(ARPoint(x: 1.5, y: 0, z: 0));
      await tester.tapAt(tester.getTopLeft(canvas) + position);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(FloorPlanViewerScreen)))!;
      await tester.tap(find.text(l10n.editOpeningDimensions));
      await tester.pumpAndSettle();
      final distance = find.byWidgetPredicate((w) => w is TextField &&
          w.decoration?.labelText == l10n.distanceFromWallStart);
      await tester.enterText(distance, '2');
      await tester.ensureVisible(find.widgetWithText(FilledButton, l10n.save));
      await tester.tap(find.widgetWithText(FilledButton, l10n.save));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(provider.completedRooms.single.features.single.start.x, closeTo(2, 1e-8));
    });
  }

  testWidgets('room name and completion dialogs finish transitions before navigation', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        child: const Text('Start test'),
        onPressed: () async {
          final name = await showRoomNameDialog(context: context, initialName: 'Kitchen');
          if (!context.mounted || name == null) return;
          final action = await showRoomCompletionDialog(context);
          if (!context.mounted || action == null) return;
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Finished')),
          ));
        },
      ))),
    ));
    await tester.tap(find.text('Start test'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Finished'), findsOneWidget);
    expect(await RecentRoomNamesService().load(), contains('Kitchen'));
    expect(tester.takeException(), isNull);
  });
}
