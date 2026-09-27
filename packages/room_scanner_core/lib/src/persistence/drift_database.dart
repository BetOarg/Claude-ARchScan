import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'drift_database.g.dart';

class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get roomsJson => text()();
}

@DriftDatabase(tables: [Projects])
class ArchScanDatabase extends _$ArchScanDatabase {
  ArchScanDatabase({required String directoryPath})
      : super(
          LazyDatabase(
            () async => NativeDatabase.createInBackground(
              File('$directoryPath/archscan.sqlite'),
            ),
          ),
        );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
