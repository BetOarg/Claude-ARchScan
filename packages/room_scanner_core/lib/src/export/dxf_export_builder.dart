import 'dart:math' as math;

import '../models/room_model.dart';
import 'technical_drawing_geometry.dart';
import 'dimension_layout.dart';
import 'technical_dimension_layout.dart';

/// AutoCAD 2000 ASCII DXF. Spanish uses metres; English uses inches.
/// The visible drawing contains the plan, room names, openings and dimensions.
class DxfExportBuilder {
  static String build(List<RoomModel> rooms, {String languageCode = 'es'}) {
    final imperial =
        languageCode.toLowerCase().split(RegExp('[-_]')).first == 'en';
    final drawing = _DxfWriter(imperial: imperial);
    final drawingRooms =
        rooms.map(TechnicalDrawingGeometry.normalizeRoom).toList();
    final walls = <_Segment>[];
    final openings = <String, WallFeature>{};

    for (final room in drawingRooms) {
      for (final point in room.points) {
        _validate(point);
      }
      for (final feature in room.features) {
        _validate(feature.start);
        _validate(feature.end);
        openings.putIfAbsent(feature.id, () => feature);
      }
      final count = room.isClosed ? room.points.length : room.points.length - 1;
      for (var i = 0; i < count; i++) {
        walls.add(
          _Segment(
            room.points[i],
            room.points[(i + 1) % room.points.length],
          ),
        );
      }
    }

    final drawn = <String>{};
    for (final wall in walls) {
      final cuts = <double>[0, 1];
      for (final other in walls) {
        for (final point in [other.a, other.b]) {
          final t = wall.project(point);
          if (t > 0 && t < 1 && wall.onLine(point)) cuts.add(t);
        }
      }
      final gaps = <(double, double)>[];
      for (final opening in openings.values) {
        if (!wall.onLine(opening.start) || !wall.onLine(opening.end)) continue;
        final first = wall.project(opening.start);
        final last = wall.project(opening.end);
        final low = math.max(0.0, math.min(first, last));
        final high = math.min(1.0, math.max(first, last));
        if (high <= low) continue;
        cuts.addAll([low, high]);
        gaps.add((low, high));
      }
      cuts.sort();
      for (var i = 1; i < cuts.length; i++) {
        if (cuts[i] - cuts[i - 1] < 0.0000001) continue;
        final mid = (cuts[i] + cuts[i - 1]) / 2;
        if (gaps.any((gap) => mid > gap.$1 && mid < gap.$2)) continue;
        final part = _Segment(wall.at(cuts[i - 1]), wall.at(cuts[i]));
        if (drawn.add(part.key)) drawing.line('WALLS', part.a, part.b);
      }

    }

    for (final room in drawingRooms) {
      if (room.points.isEmpty || room.name.trim().isEmpty) continue;
      final x = room.points.fold<double>(0, (sum, p) => sum + p.x) /
          room.points.length;
      final z = room.points.fold<double>(0, (sum, p) => sum + p.z) /
          room.points.length;
      drawing.text(
        'ROOM_NAMES',
        x,
        z,
        room.name.trim(),
        0.18,
        centered: true,
      );
    }

    for (final feature in openings.values) {
      final segment = _Segment(feature.start, feature.end);
      if (segment.length <= 0.000001) continue;
      if (feature.type == FeatureType.window) {
        for (final offset in [-0.03, 0.0, 0.03]) {
          final dx = -segment.dz / segment.length * offset;
          final dz = segment.dx / segment.length * offset;
          drawing.line(
            'WINDOWS',
            ARPoint(x: segment.a.x + dx, y: 0, z: segment.a.z + dz),
            ARPoint(x: segment.b.x + dx, y: 0, z: segment.b.z + dz),
          );
        }
      } else {
        final hinge = feature.doorHingeSide == DoorHingeSide.start
            ? segment.a
            : segment.b;
        final end = feature.doorHingeSide == DoorHingeSide.start
            ? segment.b
            : segment.a;
        var sign = feature.doorSwingSide == DoorSwingSide.left ? 1.0 : -1.0;
        if (feature.doorOpeningDirection == DoorOpeningDirection.exterior) {
          sign = -sign;
        }
        final leaf = ARPoint(
          x: hinge.x - sign * (end.z - hinge.z),
          y: 0,
          z: hinge.z + sign * (end.x - hinge.x),
        );
        drawing.line('DOORS', hinge, leaf);
        final angle =
            math.atan2(end.z - hinge.z, end.x - hinge.x) * 180 / math.pi;
        drawing.arc(
          'DOORS',
          hinge,
          segment.length,
          sign > 0 ? angle : angle - 90,
          sign > 0 ? angle + 90 : angle,
        );
      }

    }

    // Use the same CAD dimension engine as the on-screen painter.
    // Geometry remains in metres; _DxfWriter applies the final unit scale.
    final cadDimensions = <DimensionSegment>[];
    for (final room in drawingRooms) {
      cadDimensions.addAll(
        TechnicalDimensionLayout.forRoom(
          room: room,
          x: (point) => point.x,
          y: (point) => point.z,
          includeTotals: true,
        ),
      );
    }

    final placements = DimensionLayout.layout(
      cadDimensions,
      baseOffset: 0.35,
      gap: 0.12,
      textHeight: 0.12,
      labelHalfWidth: 0.19,
    );
    for (final placement in placements) {
      final segment = placement.segment;
      if (segment.length <= 0.000001) continue;

      String? label;
      if (segment.kind == DimensionKind.opening) {
        final marker = ':opening:';
        final markerIndex = segment.id.indexOf(marker);
        if (markerIndex >= 0) {
          final featureId =
              segment.id.substring(markerIndex + marker.length);
          final feature = openings[featureId];
          if (feature != null) {
            label = _formatLength(
              math.sqrt(
                math.pow(feature.end.x - feature.start.x, 2) +
                    math.pow(feature.end.z - feature.start.z, 2),
              ),
              imperial,
            );
          }
        }
      } else {
        label = _formatLength(
          _segmentLengthMeters(segment),
          imperial,
        );
      }

      if (label == null || label.isEmpty) continue;
      drawing.dimension(
        ARPoint(x: segment.x1, y: 0, z: segment.y1),
        ARPoint(x: segment.x2, y: 0, z: segment.y2),
        label,
        offset: placement.offset,
        normalDirection: segment.normalDirection,
      );
    }

    return drawing.finish();
  }

  static double _segmentLengthMeters(DimensionSegment segment) {
    final dx = segment.x2 - segment.x1;
    final dz = segment.y2 - segment.y1;
    return math.sqrt(dx * dx + dz * dz);
  }

  static String _formatLength(double meters, bool imperial) {
    if (!imperial) return '${meters.toStringAsFixed(2)} m';
    final ticks = (meters / 0.0254 * 16).round();
    final feet = ticks ~/ 192;
    final inches = (ticks % 192) ~/ 16;
    var numerator = ticks % 16;
    var denominator = 16;
    if (numerator == 0) return '$feet ft $inches in';
    while (numerator.isEven && denominator > 1) {
      numerator ~/= 2;
      denominator ~/= 2;
    }
    return '$feet ft $inches $numerator/$denominator in';
  }

  static void _validate(ARPoint point) {
    if (!point.x.isFinite || !point.y.isFinite || !point.z.isFinite) {
      throw ArgumentError('DXF requires finite coordinates.');
    }
  }
}

class _Segment {
  final ARPoint a;
  final ARPoint b;
  _Segment(this.a, this.b);
  double get dx => b.x - a.x;
  double get dz => b.z - a.z;
  double get length => math.sqrt(dx * dx + dz * dz);
  double project(ARPoint p) =>
      ((p.x - a.x) * dx + (p.z - a.z) * dz) / (dx * dx + dz * dz);
  bool onLine(ARPoint p) =>
      ((p.x - a.x) * dz - (p.z - a.z) * dx).abs() / length < 0.00001;
  ARPoint at(double t) => ARPoint(x: a.x + dx * t, y: 0, z: a.z + dz * t);
  String get key {
    final ends = [
      '${(a.x * 1000000).round()},${(a.z * 1000000).round()}',
      '${(b.x * 1000000).round()},${(b.z * 1000000).round()}',
    ]..sort();
    return ends.join(':');
  }
}

class _DxfWriter {
  final bool imperial;
  _DxfWriter({required this.imperial});
  double get scale => imperial ? 1 / 0.0254 : 1;
  final _entities = StringBuffer();
  int _nextHandle = 0x100;
  String _handle() => (_nextHandle++).toRadixString(16).toUpperCase();
  void _pair(StringBuffer out, int code, Object value) {
    out.write('$code\r\n$value\r\n');
  }

  void _entity(String type, String layer, String subclass) {
    _pair(_entities, 0, type);
    _pair(_entities, 5, _handle());
    _pair(_entities, 330, '20');
    _pair(_entities, 100, 'AcDbEntity');
    _pair(_entities, 8, layer);
    _pair(_entities, 100, subclass);
  }

  void _point(ARPoint p, {int code = 10}) {
    _pair(_entities, code, p.x * scale);
    _pair(_entities, code + 10, p.z * scale);
    _pair(_entities, code + 20, 0.0);
  }

  void line(String layer, ARPoint a, ARPoint b) {
    _entity('LINE', layer, 'AcDbLine');
    _point(a);
    _point(b, code: 11);
  }

  void arc(
    String layer,
    ARPoint center,
    double radius,
    double start,
    double end,
  ) {
    _entity('ARC', layer, 'AcDbCircle');
    _point(center);
    _pair(_entities, 40, radius * scale);
    _pair(_entities, 100, 'AcDbArc');
    _pair(_entities, 50, start % 360);
    _pair(_entities, 51, end % 360);
  }

  void dimension(
    ARPoint a,
    ARPoint b,
    String value, {
    required double offset,
    ARPoint? center,
    double normalDirection = 1.0,
  }) {
    final dx = b.x - a.x;
    final dz = b.z - a.z;
    final length = math.sqrt(dx * dx + dz * dz);
    if (length < 0.000001) return;

    var normalX = -dz / length;
    var normalZ = dx / length;
    normalX *= normalDirection;
    normalZ *= normalDirection;
    final middleX = (a.x + b.x) / 2;
    final middleZ = (a.z + b.z) / 2;
    if (center != null) {
      final towardCenterX = center.x - middleX;
      final towardCenterZ = center.z - middleZ;
      if ((normalX * towardCenterX) + (normalZ * towardCenterZ) > 0) {
        normalX = -normalX;
        normalZ = -normalZ;
      }
    }

    final dimensionStart = ARPoint(
      x: a.x + normalX * offset,
      y: 0,
      z: a.z + normalZ * offset,
    );
    final dimensionEnd = ARPoint(
      x: b.x + normalX * offset,
      y: 0,
      z: b.z + normalZ * offset,
    );

    line('MEASUREMENTS', a, dimensionStart);
    line('MEASUREMENTS', b, dimensionEnd);
    line('MEASUREMENTS', dimensionStart, dimensionEnd);
    text(
      'MEASUREMENTS',
      (dimensionStart.x + dimensionEnd.x) / 2,
      (dimensionStart.z + dimensionEnd.z) / 2,
      value,
      0.12,
      centered: true,
    );
  }

  void text(
    String layer,
    double x,
    double y,
    String value,
    double height, {
    bool centered = false,
  }) {
    _entity('TEXT', layer, 'AcDbText');
    _point(ARPoint(x: x, y: 0, z: y));
    _pair(_entities, 40, height * scale);
    final escaped = StringBuffer();
    for (final unit in value.codeUnits) {
      if (unit < 32 || unit == 127) {
        escaped.write(' ');
      } else if (unit > 126 || unit == 92 || unit == 37) {
        escaped.write(
          '\\U+${unit.toRadixString(16).padLeft(4, '0').toUpperCase()}',
        );
      } else {
        escaped.writeCharCode(unit);
      }
    }
    _pair(_entities, 1, escaped);
    _pair(_entities, 7, 'STANDARD');
    if (centered) {
      _pair(_entities, 72, 1);
      _point(ARPoint(x: x, y: 0, z: y), code: 11);
    }
    _pair(_entities, 100, 'AcDbText');
  }

  String finish() {
    final out = StringBuffer();
    void p(int code, Object value) => _pair(out, code, value);
    void table(String name, String handle, int count) {
      p(0, 'TABLE');
      p(2, name);
      p(5, handle);
      p(330, '0');
      p(100, 'AcDbSymbolTable');
      p(70, count);
    }

    p(0, 'SECTION');
    p(2, 'HEADER');
    p(999, 'Generated by ARchScan');
    p(9, '\$ACADVER');
    p(1, 'AC1015');
    p(9, '\$DWGCODEPAGE');
    p(3, 'ANSI_1252');
    p(9, '\$INSUNITS');
    p(70, imperial ? 1 : 6);
    p(9, '\$MEASUREMENT');
    p(70, imperial ? 0 : 1);
    p(9, '\$LUNITS');
    p(70, imperial ? 4 : 2);
    p(9, '\$HANDSEED');
    p(5, _nextHandle.toRadixString(16).toUpperCase());
    p(0, 'ENDSEC');

    p(0, 'SECTION');
    p(2, 'TABLES');
    table('LTYPE', '1', 1);
    p(0, 'LTYPE');
    p(5, '2');
    p(330, '1');
    p(100, 'AcDbSymbolTableRecord');
    p(100, 'AcDbLinetypeTableRecord');
    p(2, 'CONTINUOUS');
    p(70, 0);
    p(3, 'Solid line');
    p(72, 65);
    p(73, 0);
    p(40, 0.0);
    p(0, 'ENDTAB');

    const layers = {
      '0': 0,
      'WALLS': 35,
      'DOORS': 13,
      'WINDOWS': 13,
      'ROOM_NAMES': 13,
      'MEASUREMENTS': 13,
    };
    table('LAYER', '3', layers.length);
    var layerHandle = 4;
    for (final entry in layers.entries) {
      p(0, 'LAYER');
      p(5, (layerHandle++).toRadixString(16));
      p(330, '3');
      p(100, 'AcDbSymbolTableRecord');
      p(100, 'AcDbLayerTableRecord');
      p(2, entry.key);
      p(70, 0);
      p(62, 7);
      p(6, 'CONTINUOUS');
      p(370, entry.value);
    }
    p(0, 'ENDTAB');

    table('STYLE', 'A', 1);
    p(0, 'STYLE');
    p(5, 'B');
    p(330, 'A');
    p(100, 'AcDbSymbolTableRecord');
    p(100, 'AcDbTextStyleTableRecord');
    p(2, 'STANDARD');
    p(70, 0);
    p(40, 0.0);
    p(41, 1.0);
    p(50, 0.0);
    p(71, 0);
    p(42, 0.18 * scale);
    p(3, 'txt');
    p(4, '');
    p(0, 'ENDTAB');

    table('BLOCK_RECORD', 'C', 2);
    for (final entry in {'20': '*Model_Space', '21': '*Paper_Space'}.entries) {
      p(0, 'BLOCK_RECORD');
      p(5, entry.key);
      p(330, 'C');
      p(100, 'AcDbSymbolTableRecord');
      p(100, 'AcDbBlockTableRecord');
      p(2, entry.value);
    }
    p(0, 'ENDTAB');
    p(0, 'ENDSEC');

    p(0, 'SECTION');
    p(2, 'BLOCKS');
    var blockHandle = 0x30;
    for (final entry in {'20': '*Model_Space', '21': '*Paper_Space'}.entries) {
      p(0, 'BLOCK');
      p(5, (blockHandle++).toRadixString(16));
      p(330, entry.key);
      p(100, 'AcDbEntity');
      p(8, '0');
      p(100, 'AcDbBlockBegin');
      p(2, entry.value);
      p(70, 0);
      p(10, 0.0);
      p(20, 0.0);
      p(30, 0.0);
      p(3, entry.value);
      p(1, '');
      p(0, 'ENDBLK');
      p(5, (blockHandle++).toRadixString(16));
      p(330, entry.key);
      p(100, 'AcDbEntity');
      p(8, '0');
      p(100, 'AcDbBlockEnd');
    }
    p(0, 'ENDSEC');

    p(0, 'SECTION');
    p(2, 'ENTITIES');
    out.write(_entities);
    p(0, 'ENDSEC');
    p(0, 'EOF');
    return out.toString();
  }
}
