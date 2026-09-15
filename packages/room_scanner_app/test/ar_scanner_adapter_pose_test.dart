import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/scanner/adapters/ar_scanner_adapter.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() {
  test('decodifica la pose Map devuelta por ARCore', () {
    final position = ARScannerAdapter.decodeAndroidCameraTranslation({
      'position': {'x': 1, 'y': 2.5, 'z': -3},
      'rotation': {'x': 0, 'y': 0, 'z': 0, 'w': 1},
    });

    expect(position, isNotNull);
    expect(position!.x, 1);
    expect(position.y, 2.5);
    expect(position.z, -3);
  });

  test('preserva la distancia real entre capturas consecutivas', () {
    final first = ARScannerAdapter.scannerPointFromTranslation(
      vector.Vector3(0, 1.2, 0),
    );
    final second = ARScannerAdapter.scannerPointFromTranslation(
      vector.Vector3(1.10, 1.2, 0),
    );

    expect(second.x - first.x, closeTo(1.10, 0.000001));
    expect(second.z - first.z, closeTo(0, 0.000001));
  });

  test('rechaza una pose Android incompleta', () {
    expect(
      ARScannerAdapter.decodeAndroidCameraTranslation({
        'position': {'x': 1, 'z': 2},
      }),
      isNull,
    );
  });
}
