import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:room_scanner_ar/l10n/generated/app_localizations.dart';
import 'package:room_scanner_ar/widgets/opening_placement_dialog.dart';
import 'package:room_scanner_ar/providers/scanner_provider.dart';

void main() {
  for (final type in FeatureType.values) {
    testWidgets('AR measured ${type.name} keeps its width until confirmation', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final measured = WallFeature(
        id: 'ar-measured', type: type,
        start: ARPoint(x: 0.5, y: 0, z: 0),
        end: ARPoint(x: 1.6, y: 0, z: 0),
        openingHeightMeters: 2.3,
        sillHeightMeters: type == FeatureType.window ? 0.6 : 0,
      );
      final room = RoomModel(id: 'room', name: 'Room', type: RoomType.living,
        points: [ARPoint(x: 0, y: 0, z: 0), ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 3), ARPoint(x: 0, y: 0, z: 3)]);
      OpeningPlacement? result;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) => Scaffold(body: TextButton(
          child: const Text('Confirm measurement'),
          onPressed: () async {
            result = await showOpeningPlacementDialog(
              context: context, room: room, type: type,
              system: MeasurementSystem.metric, initialFeature: measured,
            );
          },
        ))),
      ));
      await tester.tap(find.text('Confirm measurement'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      final canvas = find.byKey(const ValueKey('opening-plan'));
      await tester.tapAt(tester.getTopLeft(canvas) + const Offset(120, 20));
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.width, closeTo(1.1, 1e-8));
      expect(result!.openingHeightMeters, 2.3);
      expect(result!.sillHeightMeters, type == FeatureType.window ? 0.6 : 0);
      expect(room.features, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final system in MeasurementSystem.values) {
    testWidgets('window dimensions and validation in ${system.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      OpeningPlacement? result;
      final room = RoomModel(
        id: 'room', name: 'Room', type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 3),
          ARPoint(x: 0, y: 0, z: 3),
        ],
      );
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) => Scaffold(
          body: TextButton(onPressed: () async {
            result = await showOpeningPlacementDialog(
              context: context, room: room, system: system,
              type: FeatureType.window,
            );
          }, child: const Text('Open')),
        )),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final canvas = find.byKey(const ValueKey('opening-plan'));
      expect(tester.getSize(canvas).width, greaterThan(80));
      final origin = tester.getTopLeft(canvas);
      await tester.tapAt(origin + const Offset(80, 20));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull, reason: 'Tapping a wall must enable saving valid dimensions');
      final beforeDrag = origin + const Offset(80, 20);
      await tester.dragFrom(beforeDrag, const Offset(50, 0));
      await tester.pump();
      final height = find.byKey(const ValueKey('opening-height'));
      final sill = find.byKey(const ValueKey('opening-sill'));
      await tester.enterText(height, 'NaN');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.enterText(height, system == MeasurementSystem.metric ? '1,5' : '60');
      await tester.enterText(sill, '-1');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.enterText(sill, system == MeasurementSystem.metric ? '0,8' : '30');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull, reason: 'Corrected dimensions must allow saving');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.wallIndex, 0);
      expect(result!.location.x, greaterThan(1));
      expect(result!.location.z, closeTo(0, 0.000001));
      expect(result!.openingHeightMeters,
          closeTo(system == MeasurementSystem.metric ? 1.5 : 1.524, 0.000001));
      expect(result!.sillHeightMeters,
          closeTo(system == MeasurementSystem.metric ? 0.8 : 0.762, 0.000001));
      expect(tester.takeException(), isNull);
    });
  }

  test('scanner retains dimensions through history and JSON', () {
    final provider = ScannerProvider()..startNewRoom();
    addTearDown(provider.dispose);
    provider.tryAddPoint(0, 0, 0);
    provider.tryAddPoint(3, 0, 0);
    final location = ARPoint(x: 1, y: 0, z: 0);
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      expect(provider.addFeatureToCurrentRoom(
        FeatureType.window, location, widthMeters: 0.8,
        openingHeightMeters: invalid,
      ).isValid, isFalse);
    }
    expect(provider.currentRoom!.features, isEmpty);
    expect(provider.addFeatureToCurrentRoom(
      FeatureType.window, location, widthMeters: 0.8,
      openingHeightMeters: 1.5, sillHeightMeters: 0.8,
    ).isValid, isTrue);
    provider.undoEdit();
    expect(provider.currentRoom!.features, isEmpty);
    provider.redoEdit();
    final saved = RoomModel.fromJson(provider.currentRoom!.toJson()).features.single;
    expect(saved.openingHeightMeters, 1.5);
    expect(saved.sillHeightMeters, 0.8);
  });
}
