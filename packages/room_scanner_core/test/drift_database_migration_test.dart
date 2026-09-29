import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/src/persistence/drift_database.dart';

void main() {
  test('fresh database exposes schema version 1 and all tables', () async {
    final database = ArchScanDatabase.inMemory();
    addTearDown(database.close);

    expect(database.schemaVersion, 1);

    final tables = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();

    final names = tables
        .map((row) => row.read<String>('name'))
        .where((name) => !name.startsWith('sqlite_'))
        .toSet();

    expect(
      names,
      containsAll(<String>{
        'projects',
        'rooms',
        'room_points',
        'wall_features_table',
      }),
    );
  });

  test('foreign keys reject child rows with nonexistent parents', () async {
    final database = ArchScanDatabase.inMemory();
    addTearDown(database.close);

    await expectLater(
      database.customStatement(
        'INSERT INTO rooms '
        '(project_id, room_id, name, type, is_closed) '
        "VALUES (999999, 'orphan-room', 'Orphan', 'living', 0)",
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
