import 'dart:convert';
import 'dart:math' as math;

import 'package:pdf/widgets.dart' as pw;

import '../models/room_model.dart';
import '../geometry/geometry_service.dart'; // <-- Añadir esta importación (ajusta la ruta según la estructura de carpetas)
import '../utils/measurement_units.dart';

/// Construye los datos y documentos de exportación/importación del plano
/// (JSON, SVG del plano y PDF técnico) de forma puramente computacional.
///
/// No realiza ningún I/O: no escribe archivos, no abre selectores, no
/// comparte ni imprime. Eso es responsabilidad de la capa de aplicación
/// (`room_scanner_app`), que consume estos métodos y decide qué hacer con
/// los bytes/strings resultantes (`file_picker`, `share_plus`, `printing`,
/// `path_provider`).
class PlanExportBuilder {
  static const int maxImportBytes = 10 * 1024 * 1024;
  static const int maxImportRooms = 1000;
  static const int maxImportPoints = 10000;
  static const int maxImportFeatures = 10000;
  static const int maxImportPointsPerRoom = 500;
  /// Arma el mapa serializable del proyecto para exportación JSON.
  static Map<String, dynamic> buildJsonData(
    List<RoomModel> rooms,
    String projectName,
  ) {
    return {
      'application': 'ARchScan',
      'generator': 'ARchScan',
      'formatVersion': 2,
      'lengthUnit': 'meters',
      'projectName': projectName,
      'rooms': rooms.map((r) => r.toJson()).toList(),
    };
  }

  /// Construye un nombre de archivo válido para Android, iOS y los destinos
  /// habituales del menú de compartir.
  static String buildJsonFileName(String projectName) {
    var safeName = projectName.trim();

    safeName = safeName.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    safeName = safeName.replaceAll(RegExp(r'\s+'), ' ');
    safeName = safeName.replaceAll(RegExp(r'[. ]+$'), '');

    if (safeName.isEmpty) {
      safeName = 'Plano 2D';
    }

    if (safeName.length > 80) {
      safeName = safeName.substring(0, 80).trimRight();
    }

    return '$safeName.json';
  }

  /// Construye un nombre seguro para guardar o compartir el PDF desde el
  /// diálogo nativo de Android o iOS.
  static String buildPdfFileName(String projectName) {
    final jsonFileName = buildJsonFileName(projectName);
    final baseName = jsonFileName.substring(
      0,
      jsonFileName.length - '.json'.length,
    );
    return '$baseName.pdf';
  }

  static String buildSvgFileName(String projectName) {
    final jsonFileName = buildJsonFileName(projectName);
    return '${jsonFileName.substring(0, jsonFileName.length - 5)}.svg';
  }

  static ({List<RoomModel> rooms, String projectName})? parseProjectSvg(
    String svgString,
  ) {
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

  /// Parsea el contenido de un archivo JSON de proyecto previamente
  /// exportado. Devuelve `null` si el contenido no tiene el formato
  /// esperado; no lanza excepciones para que la capa de app decida cómo
  /// informar el error (esto reemplaza el `try/catch` silencioso que antes
  /// vivía junto al `file_picker`).
  static ({List<RoomModel> rooms, String projectName})? parseProjectJson(
    String jsonString,
  ) {
    if (jsonString.length > maxImportBytes) return null;
    var source = jsonString;
    if (source.startsWith('\uFEFF')) {
      source = source.substring(1);
    }
    if (source.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final formatVersion = decoded['formatVersion'];
      if (formatVersion != null &&
          (formatVersion is! num ||
              !formatVersion.isFinite ||
              formatVersion != formatVersion.roundToDouble() ||
              formatVersion < 1 ||
              formatVersion > 2)) {
        return null;
      }

      final lengthUnit = decoded['lengthUnit'];
      if (lengthUnit != null && lengthUnit != 'meters') {
        return null;
      }

      final roomsData = decoded['rooms'];
      if (roomsData is! List || roomsData.length > maxImportRooms) {
        return null;
      }

      var pointCount = 0;
      var featureCount = 0;
      for (final room in roomsData) {
        if (room is! Map) return null;
        final points = room['points'];
        final features = room['features'];
        if (points is! List || (features != null && features is! List)) {
          return null;
        }
        if (points.length > maxImportPointsPerRoom) return null;
        pointCount += points.length;
        featureCount += features is List ? features.length : 0;
        if (pointCount > maxImportPoints || featureCount > maxImportFeatures) {
          return null;
        }
      }

      final rawProjectName = decoded['projectName'];
      if (rawProjectName != null && rawProjectName is! String) {
        return null;
      }
      final projectName =
          rawProjectName as String? ?? 'Proyecto Importado';

      final rooms = roomsData
          .map(
            (room) => RoomModel.fromJson(
              Map<String, dynamic>.from(room as Map),
            ),
          )
          .toList(growable: false);

      if (rooms.any((room) => !_hasFiniteGeometry(room))) {
        return null;
      }

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
    bool pointIsFinite(ARPoint point) =>
        point.x.isFinite && point.y.isFinite && point.z.isFinite;

    if (!room.points.every(pointIsFinite)) {
      return false;
    }

    for (final feature in room.features) {
      if (!pointIsFinite(feature.start) ||
          !pointIsFinite(feature.end) ||
          !feature.openingHeightMeters.isFinite ||
          feature.openingHeightMeters < 0 ||
          !feature.sillHeightMeters.isFinite ||
          feature.sillHeightMeters < 0) {
        return false;
      }
    }

    return true;
  }

  /// Genera el documento PDF completo del informe técnico del plano.
  /// No lo imprime ni lo comparte: eso es responsabilidad de `app`
  /// (`Printing.layoutPdf`).
  static pw.Document buildPdfDocument(
    List<RoomModel> rooms,
    String projectName,
    MeasurementSystem measurementSystem, {
    String languageCode = 'es',
  }) {
    final labels = _PdfLabels.forLanguage(languageCode);
    final pdf = pw.Document(
      title: projectName.trim().isEmpty ? 'Plano 2D' : projectName.trim(),
      author: 'ARchScan',
      creator: 'ARchScan',
      producer: 'ARchScan',
      subject: labels.documentSubject,
      keywords: labels.documentKeywords,
    );

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('${labels.architecturalPlan}: $projectName'),
            ),
            pw.Text(
              '${labels.surveyedRooms}: ${rooms.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            if (rooms.any((room) => room.points.length >= 2)) ...[
              pw.Text(
                labels.generalPlan,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                height: 390,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.6),
                ),
                child: pw.SvgImage(
                  svg: buildFloorPlanSvg(
                    rooms,
                    measurementSystem,
                    languageCode: labels.languageCode,
                    projectName: projectName,
                  ),
                ),
              ),
              pw.SizedBox(height: 18),
            ],
            ...rooms.map(
              (room) => _buildRoomReport(
                room,
                measurementSystem,
                labels,
              ),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  /// Construye el dibujo vectorial del plano completo para incorporarlo al
  /// PDF. Mantiene las coordenadas globales y ajusta la escala a la página.
  static String buildFloorPlanSvg(
    List<RoomModel> rooms,
    MeasurementSystem measurementSystem, {
    String languageCode = 'es',
    String projectName = 'Plano 2D',
  }) {
    final labels = _PdfLabels.forLanguage(languageCode);
    const canvasWidth = 760.0;
    const canvasHeight = 500.0;
    const padding = 42.0;

    final points = <ARPoint>[
      for (final room in rooms) ...room.points,
      for (final room in rooms)
        for (final feature in room.features) ...[
          feature.start,
          feature.end,
        ],
    ];

    if (points.isEmpty) {
      return '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 760 500">${_projectSvgMetadata(rooms, projectName)}</svg>';
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
    final availableWidth = canvasWidth - (padding * 2);
    final availableHeight = canvasHeight - (padding * 2);
    final scale = math.min(
      availableWidth / planWidth,
      availableHeight / planHeight,
    );
    final offsetX =
        padding + (availableWidth - (planWidth * scale)) / 2.0;
    final offsetY =
        padding + (availableHeight - (planHeight * scale)) / 2.0;

    _SvgPoint transform(ARPoint point) {
      return _SvgPoint(
        offsetX + ((point.x - minX) * scale),
        offsetY + ((point.z - minZ) * scale),
      );
    }

    final svg = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 $canvasWidth $canvasHeight">',
      )
      ..writeln(_projectSvgMetadata(rooms, projectName))
      ..writeln('<rect width="760" height="500" fill="white"/>');
    final labelLayout = _SvgLabelLayout(
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      bottomReserved: 34,
    );

    // Room captions are part of the drawing too. Reserve their space before
    // placing any dimension so an early wall label cannot occupy the caption
    // of a room that is drawn later.
    for (final room in rooms) {
      if (room.points.length < 2) continue;
      final transformed = room.points.map(transform).toList();
      final centerX = transformed
              .map((point) => point.x)
              .reduce((value, element) => value + element) /
          transformed.length;
      final centerY = transformed
              .map((point) => point.y)
              .reduce((value, element) => value + element) /
          transformed.length;
      final detailsLength = room.type == RoomType.other
          ? 12
          : labels.roomType(room.type).length + 12;
      final typeAndAreaWidth = math.max(
        62.0,
        detailsLength * 5.2,
      );
      labelLayout.reserve(
        center: _SvgPoint(centerX, centerY + 4),
        width: math.max(typeAndAreaWidth, room.name.length * 6.8),
        height: 34,
      );
    }

    final drawnWallKeys = <String>{};
    for (final room in rooms) {
      if (room.points.length < 2) {
        continue;
      }

      final transformed = room.points.map(transform).toList();
      final outlinePoints = transformed
          .map((point) => '${_svgNumber(point.x)},${_svgNumber(point.y)}')
          .join(' ');
      if (room.isClosed) {
        svg.writeln(
          '<polygon points="$outlinePoints" fill="#E3F2FD" '
          'fill-opacity="0.34" stroke="#1565C0" stroke-width="3" '
          'stroke-linejoin="round"/>',
        );
      } else {
        svg.writeln(
          '<polyline points="$outlinePoints" fill="none" '
          'stroke="#1565C0" stroke-width="3" stroke-linejoin="round" '
          'stroke-linecap="round"/>',
        );
      }

      final centerX = transformed
              .map((point) => point.x)
              .reduce((value, element) => value + element) /
          transformed.length;
      final centerY = transformed
              .map((point) => point.y)
              .reduce((value, element) => value + element) /
          transformed.length;
      final area = room.isClosed
          ? GeometryService.calculateArea(room.points)
          : 0.0;
      final displayArea = measurementSystem == MeasurementSystem.metric
          ? area
          : MeasurementUnits.squareMetersToSquareFeet(area);
      final areaText = displayArea.toStringAsFixed(2).replaceAll(
            '.',
            labels.decimalSeparator,
          );
      final areaUnit = measurementSystem == MeasurementSystem.metric
          ? 'm²'
          : 'ft²';

      svg
        ..writeln(
          '<text x="${_svgNumber(centerX)}" '
          'y="${_svgNumber(centerY - 4)}" text-anchor="middle" '
          'font-family="Helvetica" font-size="13" font-weight="bold" '
          'fill="#1F2937">${_escapeSvg(room.name)}</text>',
        )
        ..writeln(
          '<text x="${_svgNumber(centerX)}" '
          'y="${_svgNumber(centerY + 13)}" text-anchor="middle" '
          'font-family="Helvetica" font-size="10" fill="#374151">'
          '${_escapeSvg(_roomDetails(room, areaText, areaUnit, labels))}</text>',
        );

      final wallCount = room.isClosed
          ? room.points.length
          : room.points.length - 1;
      for (var index = 0; index < wallCount; index++) {
        final first = room.points[index];
        final second = room.points[(index + 1) % room.points.length];
        if (!drawnWallKeys.add(_wallKey(first, second))) {
          continue;
        }

        _writeDimensionSvg(
          svg: svg,
          layout: labelLayout,
          start: transform(first),
          end: transform(second),
          label: _formatCompactLength(
            GeometryService.calculateDistance(first, second),
            measurementSystem,
            decimalSeparator: labels.decimalSeparator,
          ),
          color: '#1565C0',
          center: _SvgPoint(centerX, centerY),
          offset: 13,
        );
      }
    }

    final drawnFeatureIds = <String>{};
    for (final room in rooms) {
      for (final feature in room.features) {
        if (!drawnFeatureIds.add(feature.id)) {
          continue;
        }

        final start = transform(feature.start);
        final end = transform(feature.end);
        svg.writeln(
          '<g data-feature-id="${_escapeSvg(feature.id)}">',
        );

        if (feature.type == FeatureType.door) {
          _writeDoorSvg(svg, feature, start, end);
        } else {
          _writeWindowSvg(svg, start, end);
        }

        _writeDimensionSvg(
          svg: svg,
          layout: labelLayout,
          start: start,
          end: end,
          label: _formatCompactLength(
            GeometryService.calculateDistance(feature.start, feature.end),
            measurementSystem,
            decimalSeparator: labels.decimalSeparator,
          ),
          color: feature.type == FeatureType.door
              ? '#F57C00'
              : '#C2185B',
          offset: 11,
        );

        svg.writeln('</g>');
      }
    }

    svg
      ..writeln(
        '<g font-family="Helvetica" font-size="10" fill="#374151">',
      )
      ..writeln(
        '<line x1="42" y1="476" x2="66" y2="476" '
        'stroke="#1565C0" stroke-width="3"/>',
      )
      ..writeln('<text x="72" y="480">${labels.wall}</text>')
      ..writeln(
        '<line x1="126" y1="476" x2="150" y2="476" '
        'stroke="#F57C00" stroke-width="3"/>',
      )
      ..writeln('<text x="156" y="480">${labels.door}</text>')
      ..writeln(
        '<line x1="214" y1="476" x2="238" y2="476" '
        'stroke="#C2185B" stroke-width="3"/>',
      )
      ..writeln('<text x="244" y="480">${labels.window}</text>')
      ..writeln('</g>')
      ..writeln('</svg>');

    return svg.toString();
  }

  static void _writeDoorSvg(
    StringBuffer svg,
    WallFeature feature,
    _SvgPoint start,
    _SvgPoint end,
  ) {
    final hinge = feature.doorHingeSide == DoorHingeSide.start
        ? start
        : end;
    final closedEnd = feature.doorHingeSide == DoorHingeSide.start
        ? end
        : start;
    final dx = closedEnd.x - hinge.x;
    final dy = closedEnd.y - hinge.y;
    var direction = feature.doorSwingSide == DoorSwingSide.left
        ? -1.0
        : 1.0;
    if (feature.doorOpeningDirection == DoorOpeningDirection.exterior) {
      direction = -direction;
    }
    final openEnd = _SvgPoint(
      hinge.x + (direction * -dy),
      hinge.y + (direction * dx),
    );
    final radius = math.sqrt((dx * dx) + (dy * dy));
    final sweep = direction > 0 ? 1 : 0;

    svg
      ..writeln(
        '<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" '
        'x2="${_svgNumber(end.x)}" y2="${_svgNumber(end.y)}" '
        'stroke="white" stroke-width="8"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(hinge.x)}" '
        'y1="${_svgNumber(hinge.y)}" '
        'x2="${_svgNumber(openEnd.x)}" '
        'y2="${_svgNumber(openEnd.y)}" '
        'stroke="#F57C00" stroke-width="2.5"/>',
      )
      ..writeln(
        '<path d="M ${_svgNumber(closedEnd.x)} ${_svgNumber(closedEnd.y)} '
        'A ${_svgNumber(radius)} ${_svgNumber(radius)} 0 0 $sweep '
        '${_svgNumber(openEnd.x)} ${_svgNumber(openEnd.y)}" '
        'fill="none" stroke="#F57C00" stroke-width="1.4" '
        'stroke-dasharray="4 3"/>',
      )
      ..writeln(
        '<circle cx="${_svgNumber(hinge.x)}" '
        'cy="${_svgNumber(hinge.y)}" r="2.4" fill="#F57C00"/>',
      );
  }

  static void _writeWindowSvg(
    StringBuffer svg,
    _SvgPoint start,
    _SvgPoint end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.max(math.sqrt((dx * dx) + (dy * dy)), 0.01);
    final normalX = (-dy / length) * 2.4;
    final normalY = (dx / length) * 2.4;

    svg
      ..writeln(
        '<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" '
        'x2="${_svgNumber(end.x)}" y2="${_svgNumber(end.y)}" '        'stroke="white" stroke-width="8"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(start.x + normalX)}" '
        'y1="${_svgNumber(start.y + normalY)}" '
        'x2="${_svgNumber(end.x + normalX)}" '
        'y2="${_svgNumber(end.y + normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(start.x - normalX)}" '
        'y1="${_svgNumber(start.y - normalY)}" '
        'x2="${_svgNumber(end.x - normalX)}" '
        'y2="${_svgNumber(end.y - normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(start.x + normalX)}" '
        'y1="${_svgNumber(start.y + normalY)}" '
        'x2="${_svgNumber(start.x - normalX)}" '
        'y2="${_svgNumber(start.y - normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(end.x + normalX)}" '
        'y1="${_svgNumber(end.y + normalY)}" '
        'x2="${_svgNumber(end.x - normalX)}" '
        'y2="${_svgNumber(end.y - normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      );
  }

  static void _writeDimensionSvg({
    required StringBuffer svg,
    required _SvgLabelLayout layout,
    required _SvgPoint start,
    required _SvgPoint end,
    required String label,
    required String color,
    required double offset,
    _SvgPoint? center,
  }) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.max(math.sqrt((dx * dx) + (dy * dy)), 0.01);
    var normalX = -dy / length;
    var normalY = dx / length;
    final middleX = (start.x + end.x) / 2.0;
    final middleY = (start.y + end.y) / 2.0;

    if (center != null) {
      final towardCenterX = center.x - middleX;
      final towardCenterY = center.y - middleY;
      if ((normalX * towardCenterX) + (normalY * towardCenterY) > 0) {
        normalX = -normalX;
        normalY = -normalY;
      }
    }

    final labelWidth = math.max(28.0, (label.length * 5.6) + 8.0);
    final placement = layout.place(
      middle: _SvgPoint(middleX, middleY),
      normal: _SvgPoint(normalX, normalY),
      preferredOffset: offset,
      width: labelWidth,
      height: 12,
    );
    final labelX = placement.center.x;
    final labelY = placement.center.y;
    final actualOffset =
        ((labelX - middleX) * normalX) +
        ((labelY - middleY) * normalY);
    final extensionOffset = actualOffset.abs() < 4
        ? 4.0
        : actualOffset - (actualOffset.sign * 3.0);

    svg
      ..writeln(
        '<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" '
        'x2="${_svgNumber(start.x + (normalX * extensionOffset))}" '
        'y2="${_svgNumber(start.y + (normalY * extensionOffset))}" '
        'stroke="$color" stroke-width="0.7"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(end.x)}" y1="${_svgNumber(end.y)}" '
        'x2="${_svgNumber(end.x + (normalX * extensionOffset))}" '
        'y2="${_svgNumber(end.y + (normalY * extensionOffset))}" '
        'stroke="$color" stroke-width="0.7"/>',
      )
      ..writeln(
        '<rect x="${_svgNumber(labelX - (labelWidth / 2))}" '
        'y="${_svgNumber(labelY - 7)}" width="${_svgNumber(labelWidth)}" '
        'height="12" rx="2" fill="white" fill-opacity="0.9"/>',
      )
      ..writeln(
        '<text data-dimension-label="${_escapeSvg(label)}" '
        'data-layout-index="${placement.index}" '
        'x="${_svgNumber(labelX)}" y="${_svgNumber(labelY + 2)}" '
        'text-anchor="middle" font-family="Helvetica" font-size="8.5" '
        'font-weight="bold" fill="$color">${_escapeSvg(label)}</text>',      );
  }

  static String _wallKey(ARPoint first, ARPoint second) {
    String pointKey(ARPoint point) =>
        '${point.x.toStringAsFixed(4)}:${point.z.toStringAsFixed(4)}';
    final firstKey = pointKey(first);
    final secondKey = pointKey(second);
    return firstKey.compareTo(secondKey) <= 0
        ? '$firstKey|$secondKey'
        : '$secondKey|$firstKey';
  }

  static String _formatCompactLength(
    double meters,
    MeasurementSystem measurementSystem, {
    required String decimalSeparator,
  }) {
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

  static String _projectSvgMetadata(
    List<RoomModel> rooms,
    String projectName,
  ) {
    final json = jsonEncode(buildJsonData(rooms, projectName));
    final encoded = base64Encode(utf8.encode(json));
    return '<metadata id="archscan-project" '
        'data-format="json-base64-v1" data-generator="ARchScan">'
        '$encoded</metadata>';
  }

  static String _escapeSvg(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _roomDetails(
    RoomModel room,
    String areaText,
    String areaUnit,
    _PdfLabels labels,
  ) {
    final area = '$areaText $areaUnit';
    return room.type == RoomType.other
        ? area
        : '${labels.roomType(room.type)} · $area';
  }

  static pw.Widget _buildRoomReport(
    RoomModel room,
    MeasurementSystem measurementSystem,
    _PdfLabels labels,
  ) {
    final area = room.isClosed
        ? GeometryService.calculateArea(room.points)
        : 0.0;
    final perimeter = GeometryService.calculatePathLength(
      room.points,
      closePath: room.isClosed,
    );
    final wallCount = room.points.length < 2
        ? 0
        : room.isClosed
            ? room.points.length
            : room.points.length - 1;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 18),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            room.type == RoomType.other
                ? room.name
                : '${room.name} · ${labels.roomType(room.type)}',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '${labels.area}: '
            '${_formatArea(area, measurementSystem, labels)} · '
            '${labels.perimeter}: '
            '${_formatLength(perimeter, measurementSystem, labels)}',
          ),
          pw.Text('${labels.registeredCorners}: ${room.points.length}'),
          pw.SizedBox(height: 8),
          pw.Text(
            labels.wallMeasurements,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (wallCount == 0)
            pw.Text(labels.noMeasuredWalls)
          else
            ...List.generate(wallCount, (index) {
              final start = room.points[index];
              final end = room.points[(index + 1) % room.points.length];
              final length =
                  GeometryService.calculateDistance(start, end);
              return pw.Bullet(
                text: '${labels.wall} ${index + 1}: '
                    '${_formatLength(length, measurementSystem, labels)}',
              );
            }),
          pw.SizedBox(height: 8),
          pw.Text(
            labels.doorsAndWindows,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (room.features.isEmpty)
            pw.Text(labels.noOpenings)
          else
            ...room.features.map(
              (feature) => pw.Bullet(
                text: _featureDescription(
                  feature,
                  measurementSystem,
                  labels,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _featureDescription(
    WallFeature feature,
    MeasurementSystem measurementSystem,
    _PdfLabels labels,
  ) {
    final width = GeometryService.calculateDistance(
      feature.start,
      feature.end,
    );
    final type = feature.type == FeatureType.door
        ? labels.door
        : labels.window;
    final parts = <String>[
      '$type: ${_formatLength(width, measurementSystem, labels)} '
          '${labels.wide}',
      '${_formatLength(feature.openingHeightMeters, measurementSystem, labels)} '
          '${labels.high}',
    ];

    if (feature.type == FeatureType.window) {
      parts.add(
        '${_formatLength(feature.sillHeightMeters, measurementSystem, labels)} '
        '${labels.fromFloor}',
      );
      parts.add(
        width >= feature.openingHeightMeters
            ? labels.horizontalOrientation
            : labels.verticalOrientation,
      );
    } else {
      parts.add(
        feature.doorHingeSide == DoorHingeSide.start
            ? labels.hingeAtStart
            : labels.hingeAtEnd,
      );
      parts.add(
        feature.doorSwingSide == DoorSwingSide.left
            ? labels.leftSwing
            : labels.rightSwing,
      );
      parts.add(
        feature.doorOpeningDirection == DoorOpeningDirection.interior
            ? labels.interiorOpening
            : labels.exteriorOpening,
      );
    }

    return parts.join(' · ');
  }

  static String _formatLength(
    double meters,
    MeasurementSystem measurementSystem,
    _PdfLabels labels,
  ) {
    return MeasurementUnits.formatLength(
      meters,
      measurementSystem,
      metersLabel: labels.meters,
      feetLabel: labels.feet,
      inchesLabel: labels.inches,
      decimalSeparator: labels.decimalSeparator,
    );
  }

  static String _formatArea(
    double squareMeters,
    MeasurementSystem measurementSystem,
    _PdfLabels labels,
  ) {
    if (measurementSystem == MeasurementSystem.metric) {
      final value = squareMeters.toStringAsFixed(2).replaceAll(
            '.',
            labels.decimalSeparator,
          );
      return '$value ${labels.squareMeters}';
    }

    final squareFeet =
        MeasurementUnits.squareMetersToSquareFeet(squareMeters);
    final value = squareFeet.toStringAsFixed(2).replaceAll(
          '.',
          labels.decimalSeparator,
        );
    return '$value ${labels.squareFeet}';
  }
}

class _PdfLabels {
  final String languageCode;

  const _PdfLabels._(this.languageCode);

  factory _PdfLabels.forLanguage(String languageCode) {
    return _PdfLabels._(
      languageCode.toLowerCase().startsWith('en') ? 'en' : 'es',
    );
  }

  bool get isEnglish => languageCode == 'en';
  String get decimalSeparator => isEnglish ? '.' : ',';
  String get architecturalPlan =>
      isEnglish ? 'Architectural plan' : 'Plano arquitectónico';
  String get surveyedRooms =>
      isEnglish ? 'Surveyed rooms' : 'Ambientes relevados';
  String get generalPlan => isEnglish ? 'General plan' : 'Plano general';
  String get area => isEnglish ? 'Area' : 'Superficie';
  String get perimeter => isEnglish ? 'Perimeter' : 'Perímetro';
  String get registeredCorners =>
      isEnglish ? 'Registered corners' : 'Esquinas registradas';
  String get wallMeasurements =>
      isEnglish ? 'Wall measurements' : 'Medidas de paredes';
  String get noMeasuredWalls => isEnglish
      ? 'There are no measured walls.'
      : 'No hay paredes medidas.';
  String get doorsAndWindows =>
      isEnglish ? 'Doors and windows' : 'Puertas y ventanas';
  String get noOpenings => isEnglish
      ? 'There are no registered openings.'
      : 'No hay aberturas registradas.';
  String get wall => isEnglish ? 'Wall' : 'Pared';
  String get door => isEnglish ? 'Door' : 'Puerta';
  String get window => isEnglish ? 'Window' : 'Ventana';
  String get wide => isEnglish ? 'wide' : 'de ancho';
  String get high => isEnglish ? 'high' : 'de alto';
  String get fromFloor => isEnglish ? 'from the floor' : 'desde el piso';
  String get horizontalOrientation => isEnglish
      ? 'horizontal orientation'
      : 'orientación horizontal';
  String get verticalOrientation => isEnglish
      ? 'vertical orientation'
      : 'orientación vertical';
  String get hingeAtStart =>
      isEnglish ? 'hinge at the start' : 'bisagra en el inicio';
  String get hingeAtEnd =>
      isEnglish ? 'hinge at the end' : 'bisagra en el final';
  String get leftSwing =>
      isEnglish ? 'opens to the left' : 'giro hacia la izquierda';
  String get rightSwing =>
      isEnglish ? 'opens to the right' : 'giro hacia la derecha';
  String get interiorOpening =>
      isEnglish ? 'opens inward' : 'apertura hacia el interior';
  String get exteriorOpening =>
      isEnglish ? 'opens outward' : 'apertura hacia el exterior';
  String get meters => isEnglish ? 'meters' : 'metros';
  String get feet => isEnglish ? 'feet' : 'pies';
  String get inches => isEnglish ? 'inches' : 'pulgadas';
  String get squareMeters =>
      isEnglish ? 'square meters' : 'metros cuadrados';
  String get squareFeet =>
      isEnglish ? 'square feet' : 'pies cuadrados';
  String get documentSubject => isEnglish
      ? 'Two-dimensional architectural plan'
      : 'Plano arquitectónico 2D';
  String get documentKeywords => isEnglish
      ? 'plan, rooms, doors, windows, dimensions'
      : 'plano, ambientes, puertas, ventanas, cotas';

  String roomType(RoomType type) {
    if (!isEnglish) {
      return type.displayName;
    }

    switch (type) {
      case RoomType.living:
        return 'Living room';
      case RoomType.cocina:
        return 'Kitchen';
      case RoomType.bano:
        return 'Bathroom';
      case RoomType.dormitorio:
        return 'Bedroom';
      case RoomType.lavadero:
        return 'Laundry room';
      case RoomType.pasillo:
        return 'Hallway';
      case RoomType.comedor:
        return 'Dining room';
      case RoomType.comedorDiario:
        return 'Breakfast room';
      case RoomType.patio:
        return 'Patio';
      case RoomType.hall:
        return 'Hall';
      case RoomType.balcon:
        return 'Balcony';
      case RoomType.terraza:
        return 'Terrace';
      case RoomType.cochera:
        return 'Garage';
      case RoomType.playroom:
        return 'Playroom';
      case RoomType.other:
        return 'Other space';
    }
  }
}

class _SvgPoint {
  final double x;
  final double y;

  const _SvgPoint(this.x, this.y);
}

class _SvgLabelPlacement {
  final _SvgPoint center;
  final int index;

  const _SvgLabelPlacement({
    required this.center,
    required this.index,
  });
}

class _SvgLabelRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const _SvgLabelRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  bool overlaps(_SvgLabelRect other) {
    const separation = 2.0;
    return left < other.right + separation &&
        right > other.left - separation &&
        top < other.bottom + separation &&
        bottom > other.top - separation;
  }
}

class _SvgLabelLayout {
  final double canvasWidth;
  final double canvasHeight;
  final double bottomReserved;
  final List<_SvgLabelRect> _occupied = [];
  int _nextIndex = 0;

  _SvgLabelLayout({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.bottomReserved,
  });

  void reserve({
    required _SvgPoint center,
    required double width,
    required double height,
  }) {
    _occupied.add(_rectFor(center, width, height));
  }

  _SvgLabelPlacement place({
    required _SvgPoint middle,
    required _SvgPoint normal,
    required double preferredOffset,
    required double width,
    required double height,
  }) {
    final offsets = <double>[
      preferredOffset,
      -preferredOffset,
      preferredOffset + 14,
      -preferredOffset - 14,
      preferredOffset + 28,
      -preferredOffset - 28,
      preferredOffset + 42,
      -preferredOffset - 42,
      preferredOffset + 56,
      -preferredOffset - 56,
      preferredOffset + 70,
      -preferredOffset - 70,
      preferredOffset + 84,
      -preferredOffset - 84,
    ];

    _SvgPoint? selectedCenter;
    _SvgLabelRect? selectedRect;

    for (final offset in offsets) {
      final candidateCenter = _clampCenter(
        _SvgPoint(
          middle.x + (normal.x * offset),
          middle.y + (normal.y * offset),
        ),
        width,
        height,
      );
      final candidateRect = _rectFor(candidateCenter, width, height);

      if (_occupied.every((rect) => !rect.overlaps(candidateRect))) {
        selectedCenter = candidateCenter;
        selectedRect = candidateRect;
        break;
      }
    }

    selectedCenter ??= _clampCenter(
      _SvgPoint(
        middle.x + (normal.x * offsets.last),
        middle.y + (normal.y * offsets.last),
      ),
      width,
      height,
    );
    selectedRect ??= _rectFor(selectedCenter, width, height);
    _occupied.add(selectedRect);

    return _SvgLabelPlacement(
      center: selectedCenter,
      index: _nextIndex++,
    );
  }

  _SvgPoint _clampCenter(
    _SvgPoint center,
    double width,
    double height,
  ) {
    const margin = 3.0;
    final halfWidth = width / 2.0;
    final halfHeight = height / 2.0;
    return _SvgPoint(
      center.x.clamp(
        margin + halfWidth,
        canvasWidth - margin - halfWidth,
      ).toDouble(),
      center.y.clamp(
        margin + halfHeight,
        canvasHeight - bottomReserved - halfHeight,
      ).toDouble(),
    );
  }

  _SvgLabelRect _rectFor(
    _SvgPoint center,
    double width,
    double height,
  ) {
    return _SvgLabelRect(
      left: center.x - (width / 2.0),
      top: center.y - (height / 2.0),
      right: center.x + (width / 2.0),
      bottom: center.y + (height / 2.0),
    );
  }
}
