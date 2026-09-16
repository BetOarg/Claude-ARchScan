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
    final svg = PlanExportBuilder.buildFloorPlanSvg(
      [roomWithFeatures()],
      MeasurementSystem.metric,
    );

    int indexFor(String label) {
      final match = RegExp(
        'data-dimension-label="$label" data-layout-index="(\\d+)"',
      ).firstMatch(svg);
      expect(match, isNotNull, reason: 'Missing dimension $label');
      return int.parse(match!.group(1)!);
    }

    final door = indexFor('0,80 m');
    final window = indexFor('1,20 m');
    final shortWall = indexFor('2,00 m');
    final longWall = indexFor('3,00 m');

    expect(door, lessThan(window));
    expect(window, lessThan(shortWall));
    expect(shortWall, lessThan(longWall));
  });

  test('keeps the room name visible and other labels out of the drawing', () {
    final svg = PlanExportBuilder.buildFloorPlanSvg(
      [roomWithFeatures()],
      MeasurementSystem.metric,
    );
    expect(svg, contains('>Dormitorio<'));
    expect(svg, isNot(contains('>Pared<')));
    expect(svg, isNot(contains('>Puerta<')));
    expect(svg, isNot(contains('>Ventana<')));
  });
}
