import 'dart:async';

import 'package:drift/drift.dart';

import '../models/project_record.dart';
import '../models/room_model.dart';
import 'drift_database.dart';
import 'project_repository.dart';

class DriftProjectRepository implements ProjectRepository {
  DriftProjectRepository({ArchScanDatabase? database}) : _database = database;

  ArchScanDatabase? _database;

  ArchScanDatabase get _db {
    final database = _database;
    if (database == null) {
      throw StateError('DriftProjectRepository.init() must be called first.');
    }
    return database;
  }

  @override
  Future<void> init({required String directoryPath}) async {
    await _database?.close();
    _database = ArchScanDatabase('$directoryPath/archscan.sqlite');
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }

  @override
  Future<List<ProjectRecord>> getAllProjects() async {
    final rows = await (_db.select(_db.projects)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();

    return rows
        .map(
          (row) => ProjectRecord(
            id: row.id,
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
    final project = await (_db.select(_db.projects)
          ..where((p) => p.uuid.equals(uuid)))
        .getSingleOrNull();

    if (project == null) {
      return const [];
    }

    // Room/point/feature order is part of the domain contract. SQLite does
    // not guarantee row order unless it is explicit, while the original
    // Isar collection order was stable. The auto-increment IDs are assigned
    // in insertion order, so use them as the persisted sequence here.
    final roomRows = await (_db.select(_db.rooms)
          ..where((r) => r.projectId.equals(project.id))
          ..orderBy([(r) => OrderingTerm.asc(r.id)]))
        .get();

    if (roomRows.isEmpty) {
      return const [];
    }

    final roomDatabaseIds = roomRows.map((room) => room.id).toList();
    final pointRows = await (_db.select(_db.roomPoints)
          ..where((p) => p.roomId.isIn(roomDatabaseIds))
          ..orderBy([(p) => OrderingTerm.asc(p.id)]))
        .get();
    final featureRows = await (_db.select(_db.wallFeaturesTable)
          ..where((f) => f.roomId.isIn(roomDatabaseIds))
          ..orderBy([(f) => OrderingTerm.asc(f.id)]))
        .get();

    final pointsByRoom = <int, List<ARPoint>>{};
    for (final point in pointRows) {
      (pointsByRoom[point.roomId] ??= []).add(
        ARPoint(x: point.x, y: point.y, z: point.z),
      );
    }

    final featuresByRoom = <int, List<WallFeature>>{};
    for (final feature in featureRows) {
      (featuresByRoom[feature.roomId] ??= []).add(
        WallFeature(
          id: feature.featureId,
          type: _parsePersistedEnum(
            FeatureType.values,
            feature.type,
            'wall_features_table.type',
          ),
          start: ARPoint(
            x: feature.startX,
            y: feature.startY,
            z: feature.startZ,
          ),
          connectedRoomId: feature.connectedRoomId,
          connectionSide: _parseConnectionSide(feature.connectionSide),
          end: ARPoint(
            x: feature.endX,
            y: feature.endY,
            z: feature.endZ,
          ),
          doorHingeSide: _parsePersistedEnum(
            DoorHingeSide.values,
            feature.hingeSide,
            'wall_features_table.hinge_side',
          ),
          doorSwingSide: _parsePersistedEnum(
            DoorSwingSide.values,
            feature.swingSide,
            'wall_features_table.swing_side',
          ),
          doorOpeningDirection: _parsePersistedEnum(
            DoorOpeningDirection.values,
            feature.openingDirection,
            'wall_features_table.opening_direction',
          ),
          openingHeightMeters: feature.openingHeight,
          sillHeightMeters: feature.sillHeight,
        ),
      );
    }

    return roomRows
        .map(
          (room) => RoomModel(
            id: room.roomId,
            name: room.name,
            type: _parsePersistedEnum(
              RoomType.values,
              room.type,
              'rooms.type',
            ),
            points: List<ARPoint>.unmodifiable(
              pointsByRoom[room.id] ?? const [],
            ),
            features: List<WallFeature>.unmodifiable(
              featuresByRoom[room.id] ?? const [],
            ),
            isClosed: room.isClosed,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.projects)
            ..where((p) => p.uuid.equals(uuid)))
          .getSingleOrNull();
      final now = DateTime.now().toUtc();
      final updatedAt = existing == null
          ? now
          : (now.isAfter(
                  existing.updatedAt.toUtc().add(const Duration(seconds: 1)),
                )
              ? now
              : existing.updatedAt.toUtc().add(const Duration(seconds: 1)));

      late final int projectId;
      if (existing == null) {
        projectId = await _db.into(_db.projects).insert(
              ProjectsCompanion(
                uuid: Value(uuid),
                name: Value(name),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (_db.update(_db.projects)
              ..where((p) => p.id.equals(existing.id)))
            .write(
          ProjectsCompanion(
            name: Value(name),
            updatedAt: Value(updatedAt),
          ),
        );
        projectId = existing.id;
      }

      final currentProject = existing ??
          await (_db.select(_db.projects)
                ..where((p) => p.id.equals(projectId)))
              .getSingle();

      final oldRooms = await (_db.select(_db.rooms)
            ..where((r) => r.projectId.equals(currentProject.id)))
          .get();

      final oldRoomIds = oldRooms.map((r) => r.id).toList();
      if (oldRoomIds.isNotEmpty) {
        await (_db.delete(_db.wallFeaturesTable)
              ..where((f) => f.roomId.isIn(oldRoomIds)))
            .go();
        await (_db.delete(_db.roomPoints)
              ..where((p) => p.roomId.isIn(oldRoomIds)))
            .go();
        await (_db.delete(_db.rooms)
              ..where((r) => r.id.isIn(oldRoomIds)))
            .go();
      }

      for (final room in rooms) {
        final roomDbId = await _db.into(_db.rooms).insert(
              RoomsCompanion.insert(
                projectId: currentProject.id,
                roomId: room.id,
                name: room.name,
                type: room.type.name,
                isClosed: Value(room.isClosed),
              ),
            );

        await _db.batch((batch) {
          batch.insertAll(
            _db.roomPoints,
            room.points
                .map(
                  (point) => RoomPointsCompanion.insert(
                    roomId: roomDbId,
                    x: point.x,
                    y: point.y,
                    z: point.z,
                  ),
                )
                .toList(),
          );

          batch.insertAll(
            _db.wallFeaturesTable,
            room.features
                .map(
                  (feature) => WallFeaturesTableCompanion.insert(
                    roomId: roomDbId,
                    featureId: feature.id,
                    type: feature.type.name,
                    connectedRoomId: Value(feature.connectedRoomId),
                    connectionSide: Value(feature.connectionSide?.name),
                    startX: feature.start.x,
                    startY: feature.start.y,
                    startZ: feature.start.z,
                    endX: feature.end.x,
                    endY: feature.end.y,
                    endZ: feature.end.z,
                    hingeSide: Value(feature.doorHingeSide.name),
                    swingSide: Value(feature.doorSwingSide.name),
                    openingDirection: Value(
                      feature.doorOpeningDirection.name,
                    ),
                    openingHeight: Value(feature.openingHeightMeters),
                    sillHeight: Value(feature.sillHeightMeters),
                  ),
                )
                .toList(),
          );
        });
      }

      // Keep this local variable used as an explicit transaction invariant.
      assert(projectId > 0);
    });
  }

  @override
  Future<void> deleteProject(String uuid) async {
    await _db.transaction(() async {
      final project = await (_db.select(_db.projects)
            ..where((p) => p.uuid.equals(uuid)))
          .getSingleOrNull();

      if (project == null) {
        return;
      }

      final rooms = await (_db.select(_db.rooms)
            ..where((r) => r.projectId.equals(project.id)))
          .get();
      final roomIds = rooms.map((r) => r.id).toList();

      if (roomIds.isNotEmpty) {
        await (_db.delete(_db.wallFeaturesTable)
              ..where((f) => f.roomId.isIn(roomIds)))
            .go();
        await (_db.delete(_db.roomPoints)
              ..where((p) => p.roomId.isIn(roomIds)))
            .go();
        await (_db.delete(_db.rooms)
              ..where((r) => r.id.isIn(roomIds)))
            .go();
      }

      await (_db.delete(_db.projects)..where((p) => p.id.equals(project.id)))
          .go();
    });
  }
}


OpeningConnectionSide? _parseConnectionSide(String? value) {
  if (value == null) {
    return null;
  }
  return _parsePersistedEnum(
    OpeningConnectionSide.values,
    value,
    'wall_features_table.connection_side',
  );
}

T _parsePersistedEnum<T extends Enum>(
  List<T> values,
  String? value,
  String field,
) {
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }

  throw StateError(
    'Unknown persisted enum value "$value" for $field.',
  );
}
