import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  group('cierre seguro de ambientes', () {
    test('sugiere la esquina ortogonal que falta antes de cerrar', () {
      final points = <ARPoint>[
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 3),
      ];

      final suggestion = ScanValidator.suggestOrthogonalClosurePoint(points);

      expect(suggestion, isNotNull);
      expect(suggestion!.x, closeTo(0, 0.000001));
      expect(suggestion.z, closeTo(3, 0.000001));

      final completed = <ARPoint>[...points, suggestion];
      expect(ScanValidator.validateClosure(completed).isValid, isTrue);
      expect(ScanValidator.hasSelfIntersections(completed), isFalse);
    });

    test('no cambia un contorno cuyo cierre ya es ortogonal', () {
      final points = <ARPoint>[
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 3),
        ARPoint(x: 0, y: 0, z: 3),
      ];

      expect(ScanValidator.suggestOrthogonalClosurePoint(points), isNull);
    });

    test('no fuerza una esquina en un ambiente triangular', () {
      final points = <ARPoint>[
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 2, y: 0, z: 3),
      ];

      expect(ScanValidator.suggestOrthogonalClosurePoint(points), isNull);
    });

    test('la sugerencia no modifica los puntos medidos', () {
      final points = <ARPoint>[
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 3),
      ];
      final original = List<ARPoint>.from(points);

      ScanValidator.suggestOrthogonalClosurePoint(points);

      expect(points, orderedEquals(original));
    });
  });

  group('edición segura de contornos abiertos', () {
    test('el primer vértice no considera vecino al último punto abierto', () {
      final points = <ARPoint>[
        ARPoint(x: 0.1, y: 0, z: 0.1),
        ARPoint(x: 2, y: 0, z: 0),
        ARPoint(x: 2, y: 0, z: 2),
        ARPoint(x: 0.25, y: 0, z: 0.2),
      ];

      final result = ScanValidator.validatePointUpdate(
        0,
        ARPoint(x: 0, y: 0, z: 0),
        points,
        false,
      );

      expect(result.isValid, isTrue);
    });

    test('un contorno cerrado conserva la validación entre extremos', () {
      final points = <ARPoint>[
        ARPoint(x: 0.1, y: 0, z: 0.1),
        ARPoint(x: 2, y: 0, z: 0),
        ARPoint(x: 2, y: 0, z: 2),
        ARPoint(x: 0.25, y: 0, z: 0.2),
      ];

      final result = ScanValidator.validatePointUpdate(
        0,
        ARPoint(x: 0, y: 0, z: 0),
        points,
        true,
      );

      expect(result.isValid, isFalse);
    });
  });
}
