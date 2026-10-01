import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/services/resume_room_calibration.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

void main() {
  group('ResumeRoomCalibration', () {
    for (final degrees in <double>[30, 45, 60]) {
      test('preserves a $degrees degree historical direction', () {
        final radians = degrees * math.pi / 180;
        final modelPrevious = ARPoint(x: 0, y: 0, z: 0);
        final modelStart = ARPoint(
          x: 3 * math.cos(radians),
          y: 0,
          z: 3 * math.sin(radians),
        );
        final calibration = ResumeRoomCalibration.tryCreate(
          modelPrevious: modelPrevious,
          modelStart: modelStart,
          sessionPrevious: ARPoint(x: 10, y: 1, z: 4),
          sessionStart: ARPoint(x: 12, y: 1, z: 4),
        )!;

        final result = calibration.transform(
          ARPoint(x: 12, y: 1.25, z: 5),
        );

        expect(result.x, closeTo(modelStart.x - math.sin(radians), 0.000001));
        expect(result.y, closeTo(0.25, 0.000001));
        expect(result.z, closeTo(modelStart.z + math.cos(radians), 0.000001));
      });
    }

    test('supports a historical contour reversed from its first endpoint', () {
      final calibration = ResumeRoomCalibration.tryCreate(
        modelPrevious: ARPoint(x: 3, y: 0, z: 0),
        modelStart: ARPoint(x: 0, y: 0, z: 0),
        sessionPrevious: ARPoint(x: 4, y: 0, z: 7),
        sessionStart: ARPoint(x: 6, y: 0, z: 7),
      )!;

      final result = calibration.transform(
        ARPoint(x: 7, y: 0, z: 7),
      );

      expect(result.x, closeTo(-1, 0.000001));
      expect(result.z, closeTo(0, 0.000001));
    });

    test('rejects coincident reference points', () {
      expect(
        ResumeRoomCalibration.tryCreate(
          modelPrevious: ARPoint(x: 0, y: 0, z: 0),
          modelStart: ARPoint(x: 0, y: 0, z: 0),
          sessionPrevious: ARPoint(x: 0, y: 0, z: 0),
          sessionStart: ARPoint(x: 1, y: 0, z: 0),
        ),
        isNull,
      );
    });
  });
}
