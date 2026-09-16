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
    test('contains only plan geometry and dimension text', () {
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
      expect(svg, isNot(contains('Estar principal')));
      expect(svg, isNot(contains('Pared')));
      expect(svg, isNot(contains('Puerta')));
      expect(svg, isNot(contains('Ventana')));
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
      final firstDimension = RegExp(
        r'data-dimension-label="3,00 m" data-layout-index="\d+" '
        r'x="([\d.]+)" y="([\d.]+)"',
      ).firstMatch(svg)!;
      final x = double.parse(firstDimension.group(1)!);
      final y = double.parse(firstDimension.group(2)!);
      expect(x, greaterThan(0));
      expect(y, greaterThan(0));
    });

    test('repositions coincident dimensions instead of stacking them', () {
      final room = rectangularRoom(
        features: [
          WallFeature(
            id: 'full-width-door',
            type: FeatureType.door,
            start: ARPoint(x: 0, y: 0, z: 0),
            end: ARPoint(x: 3, y: 0, z: 0),
          ),
        ],
      );
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      final matches = RegExp(
        r'data-dimension-label="3,00 m" data-layout-index="(\d+)" '
        r'x="([\d.]+)" y="([\d.]+)"',
      ).allMatches(svg).toList();
      final positions = matches
          .map((match) => '${match.group(2)}:${match.group(3)}')
          .toSet();

      expect(matches.length, greaterThanOrEqualTo(2));
      expect(positions.length, matches.length);
    });

    test('keeps imperial dimension symbols', () {
      final room = rectangularRoom();
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.imperial,
        languageCode: 'en',
      );
      expect(svg, contains('′'));
      expect(svg, contains('″'));
    });

    test('preserves door interior/exterior distinction', () {
      RoomModel roomWith(DoorOpeningDirection direction) => rectangularRoom(
            features: [
              WallFeature(
                id: 'direction-door',
                type: FeatureType.door,
                start: ARPoint(x: 0.5, y: 0, z: 0),
                end: ARPoint(x: 1.5, y: 0, z: 0),
                doorOpeningDirection: direction,
              ),
            ],
          );

      String drawingFor(DoorOpeningDirection direction) {
        final svg = PlanExportBuilder.buildFloorPlanSvg(
          [roomWith(direction)],
          MeasurementSystem.metric,
        );
        return RegExp(
          r'<g data-feature-id="direction-door">([\s\S]*?)</g>',
        ).firstMatch(svg)!.group(1)!;
      }

      expect(
        drawingFor(DoorOpeningDirection.interior),
        isNot(drawingFor(DoorOpeningDirection.exterior)),
      );
    });

    test('does not duplicate a shared opening', () {
      final sharedDoor = WallFeature(
        id: 'shared-door',
        type: FeatureType.door,
        start: ARPoint(x: 2, y: 0, z: 0.8),
        end: ARPoint(x: 2, y: 0, z: 1.7),
      );
      final rooms = [
        RoomModel(
          id: 'room-a',
          name: 'A',
          type: RoomType.living,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 2.5),
            ARPoint(x: 0, y: 0, z: 2.5),
          ],
          features: [sharedDoor],
          isClosed: true,
        ),
        RoomModel(
          id: 'room-b',
          name: 'B',
          type: RoomType.cocina,
          points: [
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 2.5),
            ARPoint(x: 2, y: 0, z: 2.5),
          ],
          features: [sharedDoor],
          isClosed: true,
        ),
      ];
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        rooms,
        MeasurementSystem.metric,
      );
      expect(
        RegExp('data-feature-id="shared-door"').allMatches(svg).length,
        1,
      );
    });

    test('snaps near-right angles only in technical geometry', () {
      final room = RoomModel(
        id: 'orthogonal-room',
        name: 'Taller',
        type: RoomType.other,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4.052, y: 0, z: 3),
          ARPoint(x: 0.018, y: 0, z: 3.04),
        ],
        isClosed: true,
      );
      final svg = PlanExportBuilder.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      expect(svg, contains('<polygon'));
      final restored = PlanExportBuilder.parseProjectSvg(svg)!;
      expect(restored.rooms.single.points[2].x, closeTo(4.052, 0.000001));
      expect(restored.rooms.single.points[3].z, closeTo(3.04, 0.000001));
    });
  });

  test('PDF contains a technical drawing page without report sections', () async {
    final pdf = PlanExportBuilder.buildPdfDocument(
      [rectangularRoom()],
      'Casa',
      MeasurementSystem.metric,
    );
    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });
}
