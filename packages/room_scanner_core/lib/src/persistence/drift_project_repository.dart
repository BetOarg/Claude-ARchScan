import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/room_model.dart';
import 'drift_database.dart';
import 'project_repository.dart';
import 'project_summary.dart';

/// Implementación de [ProjectRepository] sobre SQLite mediante Drift.
///
/// Los ambientes se almacenan como JSON dentro del proyecto para conservar
/// exactamente el modelo de dominio actual durante la primera etapa de la
/// migración. La interfaz de persistencia permanece independiente del motor.
class DriftProjectRepository implements ProjectRepository {
  ArchScanDatabase? _database;

  DriftProjectRepository([this._database]);

  factory DriftProjectRepository.local() => DriftProjectRepository();

  @override
  Future<void> open({required String directoryPath}) async {
    await _database?.close();
    _database = ArchScanDatabase(directoryPath: directoryPath);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  ArchScanDatabase get _db {
    final database = _database;
    if (database == null) {
      throw StateError('Project repository has not been opened.');
    }
    return database;
  }

  @override
  Future<List<ProjectSummary>> getAllProjects() async {
    final rows = await (_db.select(_db.projects)
          ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)]))
        .get();

    return rows
        .map(
          (row) => ProjectSummary(
            uuid: row.uuid,
            name: row.name,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<RoomModel>> getRoomsForProject(String uuid) async {
    final row = await (_db.select(_db.projects)
          ..where((table) => table.uuid.equals(uuid)))
        .getSingleOrNull();

    if (row == null || row.roomsJson.isEmpty) {
      return const <RoomModel>[];
    }

    final decoded = jsonDecode(row.roomsJson);
    if (decoded is! List) {
      throw StateError('Invalid rooms payload for project $uuid.');
    }

    return decoded
        .map((room) => RoomModel.fromJson(room as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    final now = DateTime.now();
    final roomsJson = jsonEncode(
      rooms.map((room) => room.toJson()).toList(growable: false),
    );

    await _db.transaction(() async {
      final existing = await (_db.select(_db.projects)
            ..where((table) => table.uuid.equals(uuid)))
          .getSingleOrNull();

      await (_db.delete(_db.projects)
            ..where((table) => table.uuid.equals(uuid)))
          .go();

      await _db.into(_db.projects).insert(
            ProjectsCompanion.insert(
              uuid: uuid,
              name: name,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              roomsJson: roomsJson,
            ),
          );
    });
  }

  @override
  Future<void> deleteProject(String uuid) async {
    await (_db.delete(_db.projects)
          ..where((table) => table.uuid.equals(uuid)))
        .go();
  }
}
