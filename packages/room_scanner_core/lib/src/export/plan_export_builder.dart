import 'dart:convert';
import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import '../models/room_model.dart';
import '../utils/measurement_units.dart';
import 'dimension_layout.dart';
import 'technical_dimension_layout.dart';
import 'technical_drawing_geometry.dart';

/// Builds ARchScan project data and technical drawing exports.
///
/// Visual exports contain only the architectural drawing itself: walls,
/// openings, room names and dimensional annotations. Project metadata and
/// report/legend data remain machine-readable where required for import.
class PlanExportBuilder {
  static const int maxImportBytes = 10 * 1024 * 1024;
  static const int maxImportRooms = 1000;
  static const int maxImportPoints = 10000;
  static const int maxImportFeatures = 10000;
  static const int maxImportPointsPerRoom = 500;

  static Map<String, dynamic> buildJsonData(List<RoomModel> rooms, String projectName) => {
        'application': 'ARchScan',
        'generator': 'ARchScan',
        'formatVersion': 2,
        'lengthUnit': 'meters',
        'projectName': projectName,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };

  static String buildJsonFileName(String projectName) {
    var safeName = projectName.trim();
    safeName = safeName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    safeName = safeName.replaceAll(RegExp(r'\s+'), ' ');
    safeName = safeName.replaceAll(RegExp(r'[. ]+$'), '');
    if (safeName.isEmpty) safeName = 'Plano 2D';
    if (safeName.length > 80) safeName = safeName.substring(0, 80).trimRight();
    return '$safeName.json';
  }

  static String buildPdfFileName(String projectName) {
    final jsonFileName = buildJsonFileName(projectName);
    return '${jsonFileName.substring(0, jsonFileName.length - 5)}.pdf';
  }

  static String buildSvgFileName(String projectName) {
    final jsonFileName = buildJsonFileName(projectName);
    return '${jsonFileName.substring(0, jsonFileName.length - 5)}.svg';
  }

  static ({List<RoomModel> rooms, String projectName})? parseProjectSvg(String svgString) {
    if (svgString.length > maxImportBytes) return null;
    final match = RegExp(
      r'<metadata\s+id="archscan-project"\s+data-format="json-base64-v1"(?:\s+data-generator="ARchScan")?>([A-Za-z0-9+/=\s]+)</metadata>',
    ).firstMatch(svgString);
    if (match == null) return null;
    try {
      final encoded = match.group(1)!.replaceAll(RegExp(r'\s'), '');
      return parseProjectJson(utf8.decode(base64Decode(encoded)));
    } on FormatException {
      return null;
    }
  }

  static ({List<RoomModel> rooms, String projectName})? parseProjectJson(String jsonString) {
    if (jsonString.length > maxImportBytes) return null;
    var source = jsonString;
    if (source.startsWith('\uFEFF')) {
      source = source.substring(1);
    }
    if (source.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return null;
      final formatVersion = decoded['formatVersion'];
      if (formatVersion != null &&
          (formatVersion is! num || !formatVersion.isFinite ||
              formatVersion != formatVersion.roundToDouble() ||
              formatVersion < 1 || formatVersion > 2)) return null;
      final lengthUnit = decoded['lengthUnit'];
      if (lengthUnit != null && lengthUnit != 'meters') return null;
      final roomsData = decoded['rooms'];
      if (roomsData is! List || roomsData.length > maxImportRooms) return null;
      var pointCount = 0;
      var featureCount = 0;
      for (final room in roomsData) {
        if (room is! Map) return null;
        final points = room['points'];
        final features = room['features'];
        if (points is! List || (features != null && features is! List)) return null;
        if (points.length > maxImportPointsPerRoom) return null;
        pointCount += points.length;
        featureCount += features is List ? features.length : 0;
        if (pointCount > maxImportPoints || featureCount > maxImportFeatures) return null;
      }
      final rawProjectName = decoded['projectName'];
      if (rawProjectName != null && rawProjectName is! String) {
        return null;
      }
      final projectName = rawProjectName as String? ?? 'Proyecto Importado';
      final rooms = roomsData
          .map((room) => RoomModel.fromJson(Map<String, dynamic>.from(room as Map)))
          .toList(growable: false);
      if (rooms.any((room) => !_hasFiniteGeometry(room))) return null;
      return (rooms: rooms, projectName: projectName);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    } on StateError {
      return null;
    }
  }

  static bool _hasFiniteGeometry(RoomModel room) {
    bool pointIsFinite(ARPoint point) => point.x.isFinite && point.y.isFinite && point.z.isFinite;
    if (!room.points.every(pointIsFinite)) return false;
    for (final feature in room.features) {
      if (!pointIsFinite(feature.start) || !pointIsFinite(feature.end) ||
          !feature.openingHeightMeters.isFinite || feature.openingHeightMeters < 0 ||
          !feature.sillHeightMeters.isFinite || feature.sillHeightMeters < 0) return false;
    }
    return true;
  }

  static pw.Document buildPdfDocument(
    List<RoomModel> rooms,
    String projectName,
    MeasurementSystem measurementSystem, {
    String languageCode = 'es',
  }) {
    final pdf = pw.Document(
      title: projectName.trim().isEmpty ? 'Plano 2D' : projectName.trim(),
      author: 'ARchScan',
      creator: 'ARchScan',
      producer: 'ARchScan',
      subject: 'Two-dimensional architectural plan',
      keywords: 'plan, rooms, doors, windows, dimensions',
    );
    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(18),
        build: (pw.Context context) => pw.Center(
          child: pw.SvgImage(
            svg: buildFloorPlanSvg(
              rooms,
              measurementSystem,
              languageCode: languageCode,
              projectName: projectName,
            ),
          ),
        ),
      ),
    );
    return pdf;
  }

  /// Builds the vector technical plan used by SVG, PDF and raster exports.
  /// Dimensions are ordered by physical length, from shortest/interior to
  /// longest/outer. Each occupied dimension corridor is reserved before the
  /// next one is placed, reducing crossings of lines as well as labels.
  static String buildFloorPlanSvg(
    List<RoomModel> rooms,
    MeasurementSystem measurementSystem, {
    String languageCode = 'es',
    String projectName = 'Plano 2D',
  }) {
    final drawingRooms = rooms.map(TechnicalDrawingGeometry.normalizeRoom).toList();
    const canvasWidth = 900.0;
    const canvasHeight = 600.0;
    const padding = 72.0;
    final decimalSeparator = languageCode.toLowerCase().startsWith('en') ? '.' : ',';

    final points = <ARPoint>[
      for (final room in drawingRooms) ...room.points,
      for (final room in drawingRooms)
        for (final feature in room.features) ...[feature.start, feature.end],
    ];
    if (points.isEmpty) {
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $canvasWidth $canvasHeight">'
          '${_projectSvgMetadata(rooms, projectName)}</svg>';
    }

    var minX = points.first.x;
    var maxX = points.first.x;
    var minZ = points.first.z;
    var maxZ = points.first.z;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minZ = math.min(minZ, point.z);
      maxZ = math.max(maxZ, point.z);
    }
    final planWidth = math.max(maxX - minX, 0.01);
    final planHeight = math.max(maxZ - minZ, 0.01);
    final availableWidth = canvasWidth - padding * 2;
    final availableHeight = canvasHeight - padding * 2;
    final scale = math.min(availableWidth / planWidth, availableHeight / planHeight);
    final offsetX = padding + (availableWidth - planWidth * scale) / 2.0;
    final offsetY = padding + (availableHeight - planHeight * scale) / 2.0;
    _SvgPoint transform(ARPoint point) => _SvgPoint(
          offsetX + (point.x - minX) * scale,
          offsetY + (point.z - minZ) * scale,
        );

    final svg = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $canvasWidth $canvasHeight">')
      ..writeln(_projectSvgMetadata(rooms, projectName))
      ..writeln('<rect width="$canvasWidth" height="$canvasHeight" fill="white"/>');
    final wallsSvg = StringBuffer();
    final carpentrySvg = StringBuffer();
    final roomNamesSvg = StringBuffer();
    final dimensionsSvg = StringBuffer();

    final dimensionSegments = <DimensionSegment>[];
    final dimensionLabels = <String, String>{};
    for (final room in drawingRooms) {
      if (room.points.length < 2) continue;
      final transformed = room.points.map(transform).toList();
      final outlinePoints = transformed.map((point) => '${_svgNumber(point.x)},${_svgNumber(point.y)}').join(' ');
      if (room.isClosed) {
        wallsSvg.writeln('<polygon points="$outlinePoints" fill="none" stroke="#000000" stroke-width="3.5" stroke-linejoin="round"/>');
      } else {
        wallsSvg.writeln('<polyline points="$outlinePoints" fill="none" stroke="#000000" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round"/>');
      }
      final center = _roomCenter(transformed);
      if (room.name.trim().isNotEmpty) {
        roomNamesSvg.writeln('<text x="${_svgNumber(center.x)}" y="${_svgNumber(center.y + 3)}" text-anchor="middle" font-family="Helvetica" font-size="9" font-weight="bold" fill="#000000">${_escapeSvg(room.name.trim())}</text>');
      }
    }

    final drawnFeatureIds = <String>{};
    for (final room in drawingRooms) {
      for (final feature in room.features) {
        if (!drawnFeatureIds.add(feature.id)) continue;
        final start = transform(feature.start);
        final end = transform(feature.end);
        carpentrySvg.writeln('<g data-feature-id="${_escapeSvg(feature.id)}">');
        if (feature.type == FeatureType.door) {
          _writeDoorSvg(carpentrySvg, feature, start, end);
        } else {
          _writeWindowSvg(carpentrySvg, start, end);
        }

        carpentrySvg.writeln('</g>');
      }
    }

    for (final room in drawingRooms) {
      final semanticSegments = TechnicalDimensionLayout.forRoom(
        room: room,
        x: (point) => point.x,
        y: (point) => point.z,
        includeTotals: true,
      );
      for (final semantic in semanticSegments) {
        final start = transform(ARPoint(x: semantic.x1, y: 0, z: semantic.y1));
        final end = transform(ARPoint(x: semantic.x2, y: 0, z: semantic.y2));
        final center = semantic.centerX == null || semantic.centerY == null
            ? null
            : transform(ARPoint(
                x: semantic.centerX!,
                y: 0,
                z: semantic.centerY!,
              ));
        dimensionSegments.add(DimensionSegment(
          x1: start.x,
          y1: start.y,
          x2: end.x,
          y2: end.y,
          kind: semantic.kind,
          id: semantic.id,
          centerX: center?.x,
          centerY: center?.y,
          normalDirection: semantic.normalDirection,
          labelHalfWidth: 19.0,
        ));
        dimensionLabels[semantic.id] = _formatCompactLength(
          semantic.length,
          measurementSystem,
          decimalSeparator: decimalSeparator,
        );
      }
    }

    final placements = DimensionLayout.layout(dimensionSegments);
    for (final placement in placements) {
      final label = dimensionLabels[placement.segment.id];
      if (label == null) continue;
      _writeDimensionSvg(
        svg: dimensionsSvg,
        placement: placement,
        label: label,
      );
    }

    svg
      ..writeln('<g id="paredes">')
      ..write(wallsSvg)
      ..writeln('</g>')
      ..writeln('<g id="carpinteria">')
      ..write(carpentrySvg)
      ..writeln('</g>')
      ..writeln('<g id="nombres-ambientes">')
      ..write(roomNamesSvg)
      ..writeln('</g>')
      ..writeln('<g id="cotas">')
      ..write(dimensionsSvg)
      ..writeln('</g>')
      ..writeln('</svg>');
    return svg.toString();
  }

  static _SvgPoint _roomCenter(List<_SvgPoint> points) {
    if (points.isEmpty) return const _SvgPoint(450, 300);
    final x = points.fold<double>(0, (sum, point) => sum + point.x) / points.length;
    final y = points.fold<double>(0, (sum, point) => sum + point.y) / points.length;
    return _SvgPoint(x, y);
  }

  static void _writeDoorSvg(StringBuffer svg, WallFeature feature, _SvgPoint start, _SvgPoint end) {
    final hinge = feature.doorHingeSide == DoorHingeSide.start ? start : end;
    final closedEnd = feature.doorHingeSide == DoorHingeSide.start ? end : start;
    final dx = closedEnd.x - hinge.x;
    final dy = closedEnd.y - hinge.y;
    var direction = feature.doorSwingSide == DoorSwingSide.left ? -1.0 : 1.0;
    if (feature.doorOpeningDirection == DoorOpeningDirection.exterior) direction = -direction;
    final openEnd = _SvgPoint(hinge.x + direction * -dy, hinge.y + direction * dx);
    final radius = math.sqrt(dx * dx + dy * dy);
    final sweep = direction > 0 ? 1 : 0;
    svg
      ..writeln('<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" x2="${_svgNumber(end.x)}" y2="${_svgNumber(end.y)}" stroke="white" stroke-width="8"/>')
      ..writeln('<line x1="${_svgNumber(hinge.x)}" y1="${_svgNumber(hinge.y)}" x2="${_svgNumber(openEnd.x)}" y2="${_svgNumber(openEnd.y)}" stroke="#000000" stroke-width="1.4"/>')
      ..writeln('<path d="M ${_svgNumber(closedEnd.x)} ${_svgNumber(closedEnd.y)} A ${_svgNumber(radius)} ${_svgNumber(radius)} 0 0 $sweep ${_svgNumber(openEnd.x)} ${_svgNumber(openEnd.y)}" fill="none" stroke="#000000" stroke-width="1"/>')
      ..writeln('<circle cx="${_svgNumber(hinge.x)}" cy="${_svgNumber(hinge.y)}" r="2" fill="#000000"/>');
  }

  static void _writeWindowSvg(StringBuffer svg, _SvgPoint start, _SvgPoint end) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.max(math.sqrt(dx * dx + dy * dy), 0.01);
    final normalX = (-dy / length) * 2.4;
    final normalY = (dx / length) * 2.4;
    svg
      ..writeln('<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" x2="${_svgNumber(end.x)}" y2="${_svgNumber(end.y)}" stroke="white" stroke-width="8"/>')
      ..writeln('<line x1="${_svgNumber(start.x + normalX)}" y1="${_svgNumber(start.y + normalY)}" x2="${_svgNumber(end.x + normalX)}" y2="${_svgNumber(end.y + normalY)}" stroke="#000000" stroke-width="1"/>')
      ..writeln('<line x1="${_svgNumber(start.x - normalX)}" y1="${_svgNumber(start.y - normalY)}" x2="${_svgNumber(end.x - normalX)}" y2="${_svgNumber(end.y - normalY)}" stroke="#000000" stroke-width="1"/>')
      ..writeln('<line x1="${_svgNumber(start.x + normalX)}" y1="${_svgNumber(start.y + normalY)}" x2="${_svgNumber(start.x - normalX)}" y2="${_svgNumber(start.y - normalY)}" stroke="#000000" stroke-width="1"/>')
      ..writeln('<line x1="${_svgNumber(end.x + normalX)}" y1="${_svgNumber(end.y + normalY)}" x2="${_svgNumber(end.x - normalX)}" y2="${_svgNumber(end.y - normalY)}" stroke="#000000" stroke-width="1"/>');
  }

  static void _writeDimensionSvg({
    required StringBuffer svg,
    required DimensionPlacement placement,
    required String label,
  }) {
    final segment = placement.segment;
    final normalX = placement.normalX;
    final normalY = placement.normalY;
    final tangentX = placement.tangentX;
    final tangentY = placement.tangentY;
    final tangentLength = math.sqrt(tangentX * tangentX + tangentY * tangentY);
    final tx = tangentLength > 0.000001 ? tangentX / tangentLength : 1.0;
    final ty = tangentLength > 0.000001 ? tangentY / tangentLength : 0.0;
    final middleX = (segment.x1 + segment.x2) / 2.0;
    final middleY = (segment.y1 + segment.y2) / 2.0;
    final actualOffset = placement.offset;
    final labelWidth = math.max(38.0, segment.labelHalfWidth * 2.0);
    final labelX = middleX + normalX * actualOffset;
    final labelY = middleY + normalY * actualOffset;
    final extensionOffset = math.max(actualOffset - 3.0, 4.0);
    const arrowLength = 7.0;
    const arrowHalfWidth = 2.4;

    String arrow(double tipX, double tipY, double dirX, double dirY) {
      final baseX = tipX + dirX * arrowLength;
      final baseY = tipY + dirY * arrowLength;
      final px = -dirY * arrowHalfWidth;
      final py = dirX * arrowHalfWidth;
      return '<line x1="${_svgNumber(tipX)}" y1="${_svgNumber(tipY)}" x2="${_svgNumber(baseX + px)}" y2="${_svgNumber(baseY + py)}" stroke="#000000" stroke-width="0.7"/>'
          '<line x1="${_svgNumber(tipX)}" y1="${_svgNumber(tipY)}" x2="${_svgNumber(baseX - px)}" y2="${_svgNumber(baseY - py)}" stroke="#000000" stroke-width="0.7"/>';
    }

    svg
      ..writeln('<line x1="${_svgNumber(segment.x1)}" y1="${_svgNumber(segment.y1)}" x2="${_svgNumber(segment.x1 + normalX * extensionOffset)}" y2="${_svgNumber(segment.y1 + normalY * extensionOffset)}" stroke="#000000" stroke-width="0.7"/>')
      ..writeln('<line x1="${_svgNumber(segment.x2)}" y1="${_svgNumber(segment.y2)}" x2="${_svgNumber(segment.x2 + normalX * extensionOffset)}" y2="${_svgNumber(segment.y2 + normalY * extensionOffset)}" stroke="#000000" stroke-width="0.7"/>')
      ..writeln('<line x1="${_svgNumber(segment.x1 + normalX * actualOffset)}" y1="${_svgNumber(segment.y1 + normalY * actualOffset)}" x2="${_svgNumber(segment.x2 + normalX * actualOffset)}" y2="${_svgNumber(segment.y2 + normalY * actualOffset)}" stroke="#000000" stroke-width="0.7"/>')
      ..writeln(arrow(
        segment.x1 + normalX * actualOffset,
        segment.y1 + normalY * actualOffset,
        tx,
        ty,
      ))
      ..writeln(arrow(
        segment.x2 + normalX * actualOffset,
        segment.y2 + normalY * actualOffset,
        -tx,
        -ty,
      ))
      ..writeln('<rect x="${_svgNumber(labelX - labelWidth / 2)}" y="${_svgNumber(labelY - 8)}" width="${_svgNumber(labelWidth)}" height="14" fill="white" fill-opacity="0.96"/>')
      ..writeln('<text data-dimension-label="${_escapeSvg(label)}" data-layout-index="${placement.level}" x="${_svgNumber(labelX)}" y="${_svgNumber(labelY + 3)}" text-anchor="middle" font-family="Helvetica" font-size="8.5" font-weight="bold" fill="#000000">${_escapeSvg(label)}</text>');
  }

  static String _formatCompactLength(double meters, MeasurementSystem measurementSystem, {required String decimalSeparator}) {
    return MeasurementUnits.formatLength(
      meters,
      measurementSystem,
      metersLabel: 'm',
      feetLabel: '′',
      inchesLabel: '″',
      decimalSeparator: decimalSeparator,
    );
  }

  static String _svgNumber(double value) => value.toStringAsFixed(2);

  static String _projectSvgMetadata(List<RoomModel> rooms, String projectName) {
    final json = jsonEncode(buildJsonData(rooms, projectName));
    final encoded = base64Encode(utf8.encode(json));
    return '<metadata id="archscan-project" data-format="json-base64-v1" data-generator="ARchScan">$encoded</metadata>';
  }

  static String _escapeSvg(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class _SvgPoint {
  final double x;
  final double y;
  const _SvgPoint(this.x, this.y);
}

