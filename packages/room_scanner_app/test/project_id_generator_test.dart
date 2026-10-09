import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/services/project_id_generator.dart';

void main() {
  test('generates unique RFC 4122 version 4 project identifiers', () {
    final ids = List<String>.generate(1000, (_) => generateProjectUuid());

    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });
}
