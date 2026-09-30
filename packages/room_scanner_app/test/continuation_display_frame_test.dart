import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:room_scanner_ar/services/continuation_display_frame.dart';

void main() {
  test('screen directions stay fixed for every wall orientation and side', () {
    for (final orientation in [0, 90, 180, 270]) {
      for (final side in OpeningConnectionSide.values) {
        final radians=orientation*math.pi/180;
        final reference=ScanContinuationReference(
          sourceRoomId:'room',featureId:'door',featureType:FeatureType.door,
          globalStart:ARPoint(x:4,y:0,z:5),
          globalEnd:ARPoint(x:4+math.cos(radians),y:0,z:5+math.sin(radians)),
          side:side,startEndpoint:ContinuationStartEndpoint.start,
        );
        final frame=ContinuationDisplayFrame(reference);
        for(final angle in [0.0,90.0,180.0,270.0]) {
          final local=frame.toLocalAngle(angle)*math.pi/180;
          final display=frame.toDisplay(ARPoint(x:math.sin(local),y:0,z:-math.cos(local)));
          expect(display.x,closeTo(math.sin(angle*math.pi/180),0.000001));
          expect(display.z,closeTo(-math.cos(angle*math.pi/180),0.000001));
        }
      }
    }
  });
}
