part of 'floor_plan_viewer_screen.dart';

// Tipos de valor y enums privados del visor de planos.

// =============================================================================
// ACCIONES
// =============================================================================
enum _FloorPlanAction {
  transformRooms,
  organizeRooms,
  areaSummary,
  importProject,
  exportProject,
}

enum _ExportFormat { json, svg, png, jpg, pdf, dxf }

extension on _ExportFormat {
  String label(AppLocalizations localizations) => switch (this) {
    _ExportFormat.json => localizations.exportJson,
    _ExportFormat.svg => localizations.exportSvg,
    _ExportFormat.png => localizations.exportPng,
    _ExportFormat.jpg => localizations.exportJpg,
    _ExportFormat.pdf => localizations.exportPdf,
    _ExportFormat.dxf => localizations.exportDxf,
  };
}

enum _RoomListActionType { delete, editMeasurements, rename, organize }

class _RoomListAction {
  final _RoomListActionType type;

  final String? roomId;

  const _RoomListAction({required this.type, this.roomId});
}

enum _FeatureMenuAction {
  move,
  delete,
  continueScanning,
  editGeometry,
  toggleHinge,
  chooseOpeningDirection,
}

class _OpeningGeometryInput {
  final double widthMeters;
  final double distanceFromWallStartMeters;
  final double openingHeightMeters;
  final double sillHeightMeters;

  const _OpeningGeometryInput({
    required this.widthMeters,
    required this.distanceFromWallStartMeters,
    required this.openingHeightMeters,
    required this.sillHeightMeters,
  });
}

class _FeatureSelection {
  final String roomId;
  final WallFeature feature;

  const _FeatureSelection({required this.roomId, required this.feature});
}

// =============================================================================
// PAINTER// =============================================================================
class _WallIdentity {
  final String roomId;
  final int wallIndex;

  const _WallIdentity(this.roomId, this.wallIndex);

  @override
  bool operator ==(Object other) =>
      other is _WallIdentity &&
      other.roomId == roomId &&
      other.wallIndex == wallIndex;

  @override
  int get hashCode => Object.hash(roomId, wallIndex);
}

class _WallInterval {
  final double start;
  final double end;

  const _WallInterval(this.start, this.end);
}

class _PreciseTransformInput {
  final double offsetX;
  final double offsetZ;
  final double angleDegrees;

  const _PreciseTransformInput({
    required this.offsetX,
    required this.offsetZ,
    required this.angleDegrees,
  });
}
