import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  test('measurement failures expose a stable domain error code', () {
    expect(
      () => MeasurementUnits.formatLength(
        double.nan,
        MeasurementSystem.metric,
        metersLabel: 'm',
        feetLabel: '′',
        inchesLabel: '″',
      ),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          DomainErrorCode.invalidMeasurement,
        ),
      ),
    );
  });

  test('DXF coordinate failures expose a stable domain error code', () {
    final room = RoomModel(
      id: 'invalid',
      name: 'Invalid',
      type: RoomType.living,
      points: [ARPoint(x: double.nan, y: 0, z: 0)],
      isClosed: false,
    );
    expect(
      () => DxfExportBuilder.build([room]),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          DomainErrorCode.invalidExportGeometry,
        ),
      ),
    );
  });
}
