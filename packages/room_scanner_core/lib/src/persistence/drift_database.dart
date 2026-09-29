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
}

class Rooms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().references(Projects, #id)();
  TextColumn get roomId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
}

class RoomPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roomId => integer().references(Rooms, #id)();
  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get z => real()();
}

class WallFeaturesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roomId => integer().references(Rooms, #id)();
  TextColumn get featureId => text()();
  TextColumn get type => text()();
  TextColumn get connectedRoomId => text().nullable()();
  TextColumn get connectionSide => text().nullable()();
  RealColumn get startX => real()();
  RealColumn get startY => real()();
  RealColumn get startZ => real()();
  RealColumn get endX => real()();
  RealColumn get endY => real()();
  RealColumn get endZ => real()();
  TextColumn get hingeSide => text().withDefault(const Constant('start'))();
  TextColumn get swingSide => text().withDefault(const Constant('left'))();
  TextColumn get openingDirection =>
      text().withDefault(const Constant('interior'))();
  RealColumn get openingHeight => real().nullable()();
  RealColumn get sillHeight => real().nullable()();
}

@DriftDatabase(tables: [Projects, Rooms, RoomPoints, WallFeaturesTable])
class ArchScanDatabase extends _$ArchScanDatabase {
  ArchScanDatabase(String path) : super(_openNativeDatabase(File(path)));

  ArchScanDatabase.inMemory() : super(_openInMemoryDatabase());


  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Schema changes must be accompanied by a versioned migration test.
          if (from < 1) {
            await m.createAll();
          }
        },
      );
}


QueryExecutor _openNativeDatabase(File file) {
  return NativeDatabase(
    file,
    setup: (database) {
      database.execute('PRAGMA foreign_keys = ON');
    },
  );
}

QueryExecutor _openInMemoryDatabase() {
  return NativeDatabase.memory(
    setup: (database) {
      database.execute('PRAGMA foreign_keys = ON');
    },
  );
}
