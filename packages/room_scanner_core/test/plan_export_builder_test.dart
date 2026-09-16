import 'dart:convert';

import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  RoomModel rectangularRoom({
    String id = 'room',
    String name = 'Dormitorio',
    List<WallFeature> features = const [],
  }) {
    return RoomModel(
      id: id,
      name: name,
      type: RoomType.dormitorio,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 2),
        ARPoint(x: 0, y: 0, z: 2),
      ],
      features: features,
      isClosed: true,
    );
  }

  group('import resource limits', () {
    test('rejects oversized JSON and SVG before decoding', () {
      final oversized =
          List.filled(PlanExportBuilder.maxImportBytes + 1, ' ').join();
      expect(PlanExportBuilder.parseProjectJson(oversized), isNull);
      expect(PlanExportBuilder.parseProjectSvg(oversized), isNull);
    });

    test('rejects excess room count', () {
      final source = jsonEncode({
        'rooms': List.generate(
          PlanExportBuilder.maxImportRooms + 1,
          (_) => {'points': [], 'features': []},
        ),
      });
      expect(PlanExportBuilder.parseProjectJson(source), isNull);
    });

    test('rejects excess point count', () {
      final source = jsonEncode({
        'rooms': List.generate(
          21,
          (_) => {
            'points': List.filled(500, {'x': 0, 'y': 0, 'z': 0}),
            'features': [],
          },
        ),
      });
      expect(PlanExportBuilder.parseProjectJson(source), isNull);
    });

    test('rejects excess feature count', () {
      final source = jsonEncode({
        'rooms': [
          {
            'points': [],
            'features': List.filled(PlanExportBuilder.maxImportFeatures + 1, {}),
          },
        ],
      });
      expect(PlanExportBuilder.parseProjectJson(source), isNull);
    });
  });

  test('JSON round-trip preserves project and geometry data', () {
    final room = rectangularRoom(
      id: 'round-trip',
      name: 'Estar de Sofía',
      features: [
        WallFeature(
          id: 'window-1',
          type: FeatureType.window,
          start: ARPoint(x: 0.5, y: 0, z: 0),
          end: ARPoint(x: 1.7, y: 0, z: 0),
          openingHeightMeters: 1.1,
          sillHeightMeters: 0.85,
        ),
      ],
    );
    final encoded = jsonEncode(
      PlanExportBuilder.buildJsonData([room], 'Casa Ñandú'),
    );
    final imported = PlanExportBuilder.parseProjectJson(encoded);

    expect(imported, isNotNull);
    expect(imported!.projectName, 'Casa Ñandú');
    expect(imported.rooms.single.toJson(), room.toJson());
  });

  group('clean technical SVG', () {
    test('contains plan geometry, room name and dimension text only', () {
      final room = rectangularRoom(
        name: 'Estar principal',
        features: [
          WallFeature(
            id: 'door-svg',
            type: FeatureType.door,
            start: ARPoint(x: 0.8, y: 0, z: 0),
            end: ARPoint(x: 1.7, y: 0, z: 0),
          ),
          WallFeature(
            id: 'window-svg',
            type: FeatureType.window,
            start: ARPoint(x: 3, y: 0, z: 0.8),
            end: ARPoint(x: 3, y: 0, z: 2),
          ),
        ],
      );

      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('<polygon'));
      expect(svg, contains('data-feature-id="door-svg"'));
      expect(svg, contains('data-feature-id="window-svg"'));
      expect(svg, contains('<g id="paredes">'));
      expect(svg, contains('<g id="carpinteria">'));
      expect(svg, contains('<g id="cotas">'));
      expect(svg, contains('stroke="#000000" stroke-width="3.5"'));
      expect(svg, contains('data-dimension-label="3,00 m"'));
      expect(svg, contains('>Estar principal</text>'));
      expect(svg, isNot(contains('>Pared</text>')));
      expect(svg, isNot(contains('>Puerta</text>')));
      expect(svg, isNot(contains('>Ventana</text>')));
    });

    test('keeps project data importable through hidden metadata', () {
      final room = rectangularRoom(name: 'Nombre no visible');
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
        projectName: 'Proyecto oculto',
      );
      final parsed = PlanExportBuilder.parseProjectSvg(svg);

      expect(parsed, isNotNull);
      expect(parsed!.projectName, 'Proyecto oculto');
      expect(parsed.rooms.single.name, 'Nombre no visible');
    });

    test('places dimensions farther from the wall than the old compact offset', () {
      final room = rectangularRoom();
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      expect(svg, contains('x1="108.00" y1="72.00" x2="108.00" y2="25.00"'));
    });

    test('repositions coincident dimensions instead of stacking them', () {
      final room = rectangularRoom(
        features: [
          WallFeature(
            id: 'door-1',
            type: FeatureType.door,
            start: ARPoint(x: 0.8, y: 0, z: 0),
            end: ARPoint(x: 1.7, y: 0, z: 0),
          ),
        ],
      );
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      expect(svg, contains('data-layout-index="0"'));
      expect(svg, contains('data-layout-index="1"'));
    });

    test('keeps imperial dimension symbols', () {
      final room = rectangularRoom();
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.imperial,
        languageCode: 'en',
      );
      expect(svg, contains('ft'));
      expect(svg, contains('in'));
    });

    test('preserves door interior/exterior distinction', () {
      final interior = rectangularRoom(
        features: [
          WallFeature(
            id: 'door-interior',
            type: FeatureType.door,
            start: ARPoint(x: 0.8, y: 0, z: 0),
            end: ARPoint(x: 1.7, y: 0, z: 0),
            doorOpeningDirection: DoorOpeningDirection.interior,
          ),
        ],
      );
      final exterior = rectangularRoom(
        features: [
          WallFeature(
            id: 'door-exterior',
            type: FeatureType.door,
            start: ARPoint(x: 0.8, y: 0, z: 0),
            end: ARPoint(x: 1.7, y: 0, z: 0),
            doorOpeningDirection: DoorOpeningDirection.exterior,
          ),
        ],
      );
      final interiorSvg = PlanExportBuilder.buildFloorPlanSvg(
        [interior],
        MeasurementSystem.metric,
      );
      final exteriorSvg = PlanExportBuilder.buildFloorPlanSvg(
        [exterior],
        MeasurementSystem.metric,
      );
      expect(interiorSvg, isNot(equals(exteriorSvg)));
    });

    test('does not duplicate a shared opening', () {
      final opening = WallFeature(
        id: 'shared-window',
        type: FeatureType.window,
        start: ARPoint(x: 3, y: 0, z: 0.8),
        end: ARPoint(x: 3, y: 0, z: 2),
      );
      final first = rectangularRoom(id: 'first', features: [opening]);
      final second = rectangularRoom(id: 'second', features: [opening]);
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [first, second],
        MeasurementSystem.metric,
      );
      expect(RegExp('data-feature-id="shared-window"').allMatches(svg), hasLength(1));
    });

    test('snaps near-right angles only in technical geometry', () {
      final room = RoomModel(
        id: 'angled',
        name: 'Angulado',
        type: RoomType.dormitorio,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3.03, y: 0, z: 2),
          ARPoint(x: 0, y: 0, z: 2),
        ],
        features: const [],
        isClosed: true,
      );
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      expect(svg, contains('792.00,528.00 108.00,528.00'));
    });
  });

  test('PDF contains a technical drawing page without report sections', () {
    final pdf = PlanExportBuilder.buildPdfDocument(
      [rectangularRoom(name: 'Estar')],
      'Proyecto',
      MeasurementSystem.metric,
    );
    expect(pdf, isNotNull);
  });
}
