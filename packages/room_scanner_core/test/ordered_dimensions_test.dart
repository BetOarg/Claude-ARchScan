import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  RoomModel roomWithFeatures() {
    return RoomModel(
      id: 'ordered-dimensions',
      name: 'Dormitorio',
      type: RoomType.dormitorio,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 2),
        ARPoint(x: 0, y: 0, z: 2),
      ],
      features: [
        WallFeature(
          id: 'door-short',
          type: FeatureType.door,
          start: ARPoint(x: 0.8, y: 0, z: 0),
          end: ARPoint(x: 1.6, y: 0, z: 0),
        ),
        WallFeature(
          id: 'window-medium',
          type: FeatureType.window,
          start: ARPoint(x: 3, y: 0, z: 0.4),
          end: ARPoint(x: 3, y: 0, z: 1.6),
          openingHeightMeters: 1.1,
          sillHeightMeters: 0.85,
        ),
      ],
      isClosed: true,
    );
  }

  test('orders dimension placement from shortest to longest', () {
    final svg = PlanExportBuilder.buildFloorPlanSvg([
      roomWithFeatures(),
    ], MeasurementSystem.metric);

    int documentPositionFor(String label) {
      final position = svg.indexOf('data-dimension-label="$label"');
      expect(
        position,
        greaterThanOrEqualTo(0),
        reason: 'Missing dimension $label',
      );
      return position;
    }

    final door = documentPositionFor('0,80 m');
    final window = documentPositionFor('1,20 m');
    final shortWall = documentPositionFor('2,00 m');
    final longWall = documentPositionFor('3,00 m');

    expect(door, lessThan(window));
    expect(window, lessThan(shortWall));
    expect(shortWall, lessThan(longWall));
  });

  test('keeps consecutive wall segments on one dimension chain', () {
    final segments = <DimensionSegment>[
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 1.5,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'wall-1',
        centerX: 2,
        centerY: 1,
      ),
      const DimensionSegment(
        x1: 1.5,
        y1: 0,
        x2: 3,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'wall-2',
        centerX: 2,
        centerY: 1,
      ),
      const DimensionSegment(
        x1: 3,
        y1: 0,
        x2: 5,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'wall-3',
        centerX: 2,
        centerY: 1,
      ),
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 5,
        y2: 0,
        kind: DimensionKind.total,
        id: 'total',
        centerX: 2,
        centerY: 1,
      ),
    ];

    final placements = DimensionLayout.layout(
      segments,
      strictHierarchy: true,
    );

    final walls = placements
        .where((placement) => placement.segment.kind == DimensionKind.wall)
        .toList();
    final total = placements.firstWhere(
      (placement) => placement.segment.kind == DimensionKind.total,
    );

    expect(walls, hasLength(3));
    expect(walls.every((placement) => placement.level == 1), isTrue);
    expect(walls.map((placement) => placement.offset).toSet(), {34.0});
    expect(total.level, 2);
  });

  test('keeps the room name visible and other labels out of the drawing', () {
    final svg = PlanExportBuilder.buildFloorPlanSvg([
      roomWithFeatures(),
    ], MeasurementSystem.metric);
    expect(svg, contains('>Dormitorio<'));
    expect(svg, isNot(contains('>Pared<')));
    expect(svg, isNot(contains('>Puerta<')));
    expect(svg, isNot(contains('>Ventana<')));
  });
  test(
    'renders ISO 128 dimension linework with extension lines and arrowheads',
    () {
      final svg = PlanExportBuilder.buildFloorPlanSvg([
        roomWithFeatures(),
      ], MeasurementSystem.metric);

      expect(svg, contains('stroke-width="0.7"'));
      expect(svg, contains('data-dimension-label="0,80 m"'));
      final dimensionSectionStart = svg.indexOf('<g id="cotas">');
      expect(dimensionSectionStart, greaterThanOrEqualTo(0));
      final dimensionSection = svg.substring(dimensionSectionStart);
      expect(
        RegExp(r'<line x1="[^"]+" y1="[^"]+" x2="[^"]+" y2="[^"]+"')
            .allMatches(dimensionSection)
            .length,
        greaterThan(8),
      );
    },
  );
}
