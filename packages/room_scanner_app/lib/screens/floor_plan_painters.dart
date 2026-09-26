part of 'floor_plan_viewer_screen.dart';

// Painters del plano técnico (renderizado, sin estado de sensores).

class _OpeningDirectionPainter extends CustomPainter {
  final Offset openingDirection;

  const _OpeningDirectionPainter({required this.openingDirection});
  @override
  void paint(Canvas canvas, Size size) {
    final midpoint = Offset(size.width / 2.0, size.height / 2.0);
    final length = openingDirection.distance;
    final tangent = length <= 0.000001
        ? const Offset(1, 0)
        : openingDirection / length;
    final normal = Offset(-tangent.dy, tangent.dx);
    final halfOpening = size.shortestSide * 0.42;
    final arrowLength = size.shortestSide * 0.35;
    final start = midpoint - tangent * halfOpening;
    final end = midpoint + tangent * halfOpening;

    final openingPaint = Paint()
      ..color = const Color(0xFFFF8A00)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final arrowPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, openingPaint);
    _drawArrow(canvas, midpoint, midpoint + normal * arrowLength, arrowPaint);
    _drawArrow(canvas, midpoint, midpoint - normal * arrowLength, arrowPaint);
    canvas.drawCircle(start, 9, Paint()..color = const Color(0xFF00C853));
    canvas.drawCircle(start, 3, Paint()..color = Colors.white);
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final delta = end - start;
    final length = delta.distance;

    if (length <= 0.000001) {
      return;
    }

    final direction = delta / length;
    final perpendicular = Offset(-direction.dy, direction.dx);
    canvas.drawLine(end, end - direction * 10 + perpendicular * 8, paint);
    canvas.drawLine(end, end - direction * 10 - perpendicular * 8, paint);
  }

  @override
  bool shouldRepaint(covariant _OpeningDirectionPainter oldDelegate) => false;
}

class _AlignmentPreviewPainter extends CustomPainter {
  final WallAlignmentPreview preview;

  const _AlignmentPreviewPainter({required this.preview});

  @override
  void paint(Canvas canvas, Size size) {
    final points = <ARPoint>[
      for (final room in preview.currentRooms) ...room.points,
      for (final room in preview.proposedRooms) ...room.points,
    ];
    if (points.isEmpty || size.isEmpty) {
      return;
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

    const padding = 18.0;
    final width = math.max(maxX - minX, 0.01);
    final height = math.max(maxZ - minZ, 0.01);
    final scale = math.min(
      (size.width - padding * 2) / width,
      (size.height - padding * 2) / height,
    );
    final drawingWidth = width * scale;
    final drawingHeight = height * scale;
    final origin = Offset(
      (size.width - drawingWidth) / 2,
      (size.height - drawingHeight) / 2,
    );

    Offset transform(ARPoint point) => Offset(
      origin.dx + (point.x - minX) * scale,
      origin.dy + (point.z - minZ) * scale,
    );

    void drawRoom(RoomModel room, Paint paint) {
      if (room.points.length < 2) {
        return;
      }
      final path = Path()
        ..moveTo(
          transform(room.points.first).dx,
          transform(room.points.first).dy,
        );
      for (final point in room.points.skip(1)) {
        final transformed = transform(point);
        path.lineTo(transformed.dx, transformed.dy);
      }
      if (room.isClosed && room.points.length >= 3) {
        path.close();
      }
      canvas.drawPath(path, paint);
    }

    final fixedPaint = Paint()
      ..color = const Color(0xFF7B8492).withOpacity(0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final currentPaint = Paint()
      ..color = const Color(0xFFFF8A00)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final proposedPaint = Paint()
      ..color = const Color(0xFF00A86B)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (final room in preview.currentRooms) {
      if (!preview.transformedRoomIds.contains(room.id)) {
        drawRoom(room, fixedPaint);
      }
    }
    for (final room in preview.currentRooms) {
      if (preview.transformedRoomIds.contains(room.id)) {
        drawRoom(room, currentPaint);
      }
    }
    for (final room in preview.proposedRooms) {
      if (preview.transformedRoomIds.contains(room.id)) {
        drawRoom(room, proposedPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AlignmentPreviewPainter oldDelegate) {
    return oldDelegate.preview != preview;
  }
}

class FloorPlanPainter extends CustomPainter {
  final List<RoomModel> rooms;

  final Offset Function(ARPoint) transform;
  final String? selectedRoomId;
  final String? selectedFeatureId;
  final String Function(double) formatLength;
  final String Function(WallFeature) formatOpeningDimensions;
  final String sharedWallLabel;
  final String partialSharedWallLabel;
  final String openRoomLabel;
  final bool continuationSelectionMode;

  final List<Rect> _occupiedLabelRects = <Rect>[];

  FloorPlanPainter({
    required this.rooms,
    required this.transform,
    required this.formatLength,
    required this.formatOpeningDimensions,
    required this.sharedWallLabel,
    required this.partialSharedWallLabel,
    this.openRoomLabel = '',
    this.continuationSelectionMode = false,
    this.selectedRoomId,
    this.selectedFeatureId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rooms.isEmpty) {
      return;
    }

    _occupiedLabelRects.clear();

    final wallPaint = Paint()
      ..color = const Color(0xFF448AFF)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final roomFill = Paint()
      ..color = const Color(0xFF448AFF).withOpacity(0.10)
      ..style = PaintingStyle.fill;

    final pointPaint = Paint()
      ..color = const Color(0xFF448AFF)
      ..style = PaintingStyle.fill;
    final doorPaint = Paint()
      ..color = const Color(0xFFFF8A00)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final windowPaint = Paint()
      ..color = const Color(0xFFD500F9)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final selectedPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 11.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final referencePaint = Paint()
      ..color = const Color(0xFF00C853)
      ..style = PaintingStyle.fill;
    if (continuationSelectionMode) {
      doorPaint
        ..color = const Color(0xFF00C853)
        ..strokeWidth = 9.0;
      windowPaint
        ..color = const Color(0xFF00C853)
        ..strokeWidth = 9.0;
    }
    final dimensionedFeatureIds = <String>{};
    final featureOwnerRoomIds = <String, String>{};
    final sharedWalls = SharedWallService.detect(rooms: rooms);
    final hiddenWallIntervals = _buildHiddenWallIntervals(sharedWalls);
    final hiddenDimensionWalls = hiddenWallIntervals.entries
        .where(
          (entry) => entry.value.any(
            (interval) =>
                interval.start <= 0.000001 && interval.end >= 0.999999,
          ),
        )
        .map((entry) => entry.key)
        .toSet();

    for (final room in rooms) {
      for (final feature in room.features) {
        featureOwnerRoomIds.putIfAbsent(feature.id, () => room.id);

        if (room.id == selectedRoomId && feature.id == selectedFeatureId) {
          featureOwnerRoomIds[feature.id] = room.id;
        }
      }
    }

    for (final room in rooms) {
      _drawRoom(
        canvas,
        room,
        wallPaint,
        roomFill,
        pointPaint,
        hiddenWallIntervals,
      );
    }

    _drawSharedWalls(canvas, sharedWalls);

    for (final room in rooms) {
      _drawRoomLabel(canvas, room);

      _drawFeatures(
        canvas,
        room,
        doorPaint,
        windowPaint,
        selectedPaint,
        referencePaint,
        featureOwnerRoomIds,
      );
      _drawCadDimensions(
        canvas: canvas,
        room: room,
        hiddenDimensionWalls: hiddenDimensionWalls,
        dimensionedFeatureIds: dimensionedFeatureIds,
      );
    }
  }

  // ===========================================================================
  // HABITACIÓN
  // ===========================================================================

  void _drawRoom(
    Canvas canvas,
    RoomModel room,
    Paint wallPaint,
    Paint roomFill,
    Paint pointPaint,
    Map<_WallIdentity, List<_WallInterval>> hiddenWallIntervals,
  ) {
    if (room.points.isEmpty) {
      return;
    }

    final path = Path();

    final start = transform(room.points.first);

    path.moveTo(start.dx, start.dy);

    for (int i = 1; i < room.points.length; i++) {
      final next = transform(room.points[i]);

      path.lineTo(next.dx, next.dy);
    }
    if (room.isClosed) {
      path.close();
    }
    if (room.isClosed && room.points.length >= 3) {
      canvas.drawPath(path, roomFill);
    }

    final wallCount = room.isClosed
        ? room.points.length
        : room.points.length - 1;
    for (var wallIndex = 0; wallIndex < wallCount; wallIndex++) {
      final wallStart = transform(room.points[wallIndex]);
      final wallEnd = transform(
        room.points[(wallIndex + 1) % room.points.length],
      );
      _drawVisibleWallParts(
        canvas: canvas,
        start: wallStart,
        end: wallEnd,
        paint: wallPaint,
        hiddenIntervals:
            hiddenWallIntervals[_WallIdentity(room.id, wallIndex)] ?? const [],
      );
    }

    for (final point in room.points) {
      canvas.drawCircle(transform(point), 4.0, pointPaint);
    }
  }

  Map<_WallIdentity, List<_WallInterval>> _buildHiddenWallIntervals(
    List<SharedWallSegment> sharedWalls,
  ) {
    final intervals = <_WallIdentity, List<_WallInterval>>{};
    for (final sharedWall in sharedWalls) {
      final room = rooms.firstWhere(
        (candidate) => candidate.id == sharedWall.secondRoomId,
      );
      final wallStart = room.points[sharedWall.secondWallIndex];
      final wallEnd =
          room.points[(sharedWall.secondWallIndex + 1) % room.points.length];
      final dx = wallEnd.x - wallStart.x;
      final dz = wallEnd.z - wallStart.z;
      final lengthSquared = dx * dx + dz * dz;
      if (lengthSquared <= 0.000001) {
        continue;
      }
      double projection(ARPoint point) {
        return (((point.x - wallStart.x) * dx + (point.z - wallStart.z) * dz) /
                lengthSquared)
            .clamp(0.0, 1.0)
            .toDouble();
      }

      final first = projection(sharedWall.start);
      final second = projection(sharedWall.end);
      intervals
          .putIfAbsent(
            _WallIdentity(sharedWall.secondRoomId, sharedWall.secondWallIndex),
            () => [],
          )
          .add(_WallInterval(math.min(first, second), math.max(first, second)));
    }
    return intervals;
  }

  void _drawVisibleWallParts({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint paint,
    required List<_WallInterval> hiddenIntervals,
  }) {
    if (hiddenIntervals.isEmpty) {
      canvas.drawLine(start, end, paint);
      return;
    }

    final sorted = List<_WallInterval>.from(hiddenIntervals)
      ..sort((first, second) => first.start.compareTo(second.start));
    var visibleStart = 0.0;
    for (final interval in sorted) {
      final hiddenStart = interval.start.clamp(0.0, 1.0).toDouble();
      final hiddenEnd = interval.end.clamp(0.0, 1.0).toDouble();
      if (hiddenStart > visibleStart + 0.000001) {
        canvas.drawLine(
          Offset.lerp(start, end, visibleStart)!,
          Offset.lerp(start, end, hiddenStart)!,
          paint,
        );
      }
      visibleStart = math.max(visibleStart, hiddenEnd);
    }
    if (visibleStart < 1.0 - 0.000001) {
      canvas.drawLine(Offset.lerp(start, end, visibleStart)!, end, paint);
    }
  }

  void _drawSharedWalls(Canvas canvas, List<SharedWallSegment> sharedWalls) {
    final completePaint = Paint()
      ..color = const Color(0xFF00695C)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final partialPaint = Paint()
      ..color = const Color(0xFF00897B)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final endpointPaint = Paint()
      ..color = const Color(0xFF00897B)
      ..style = PaintingStyle.fill;

    for (final sharedWall in sharedWalls) {
      final start = transform(sharedWall.start);
      final end = transform(sharedWall.end);
      final isPartial = sharedWall.coverage == SharedWallCoverage.partial;
      canvas.drawLine(start, end, isPartial ? partialPaint : completePaint);
      if (isPartial) {
        canvas.drawCircle(start, 3.5, endpointPaint);
        canvas.drawCircle(end, 3.5, endpointPaint);
      }
    }
  }

  // ===========================================================================
  // NOMBRE Y SUPERFICIE
  // ===========================================================================

  void _drawRoomLabel(Canvas canvas, RoomModel room) {
    if (room.points.isEmpty) {
      return;
    }

    double x = 0.0;
    double y = 0.0;

    for (final point in room.points) {
      final transformed = transform(point);

      x += transformed.dx;
      y += transformed.dy;
    }

    final center = Offset(x / room.points.length, y / room.points.length);

    final screenBounds = _boundsForPoints(
      room.points.map(transform).toList(growable: false),
    );
    final compact = screenBounds.width < 105 || screenBounds.height < 54;

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: room.name,
            style: TextStyle(
              color: Colors.black87,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!room.isClosed)
            TextSpan(
              text: '\n$openRoomLabel',
              style: TextStyle(
                color: Colors.black54,
                fontSize: compact ? 8 : 9,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: room.isClosed ? 1 : 2,
    )..layout(maxWidth: 112);
    final shiftY = math.min(18.0, screenBounds.height * 0.18);
    final shiftX = math.min(24.0, screenBounds.width * 0.16);
    final candidates = <Offset>[
      center,
      center + Offset(0, -shiftY),
      center + Offset(0, shiftY),
      center + Offset(-shiftX, 0),
      center + Offset(shiftX, 0),
    ];
    var labelCenter = center;
    var backgroundRect = Rect.fromCenter(
      center: center,
      width: textPainter.width + 10,
      height: textPainter.height + 6,
    );
    for (final candidate in candidates) {
      final candidateRect = Rect.fromCenter(
        center: candidate,
        width: textPainter.width + 14,
        height: textPainter.height + 10,
      );
      if (_isLabelAreaAvailable(candidateRect)) {
        labelCenter = candidate;
        backgroundRect = candidateRect;
        break;
      }
    }
    _occupiedLabelRects.add(backgroundRect.inflate(2));
    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.86)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, const Radius.circular(7)),
      backgroundPaint,
    );

    textPainter.paint(
      canvas,
      Offset(
        labelCenter.dx - textPainter.width / 2,
        labelCenter.dy - textPainter.height / 2,
      ),
    );
  }

  // ===========================================================================
  // COTAS CAD COMPARTIDAS
  // ===========================================================================

  void _drawCadDimensions({
    required Canvas canvas,
    required RoomModel room,
    required Set<_WallIdentity> hiddenDimensionWalls,
    required Set<String> dimensionedFeatureIds,
  }) {
    if (room.points.length < 2) {
      return;
    }

    final hiddenIndexes = <int>{
      for (final identity in hiddenDimensionWalls)
        if (identity.roomId == room.id) identity.wallIndex,
    };

    final dimensions = TechnicalDimensionLayout.forRoom(
      room: room,
      x: (point) => transform(point).dx,
      y: (point) => transform(point).dy,
      includeTotals: true,
      hiddenWallIndexes: hiddenIndexes,
    );

    final placements = DimensionLayout.layout(
      dimensions.map((dimension) {
        if (dimension.kind == DimensionKind.opening) {
          dimensionedFeatureIds.add(dimension.id);
        }
        return dimension;
      }),
      suppressRedundantOverallSegments: true,
      strictHierarchy: true,
    );

    final dimensionPaint = Paint()
      ..color = const Color(0xFF174EA6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    for (final placement in placements) {
      final dimension = placement.segment;
      final start = Offset(dimension.x1, dimension.y1);
      final end = Offset(dimension.x2, dimension.y2);
      final direction = end - start;
      final screenLength = direction.distance;
      if (screenLength < 8.0) {
        continue;
      }

      final tangent = Offset(placement.tangentX, placement.tangentY);
      final normal = Offset(placement.normalX, placement.normalY);
      final dimensionStart = start + normal * placement.offset;
      final dimensionEnd = end + normal * placement.offset;

      canvas.drawLine(
        start + normal * 5.0,
        start + normal * placement.offset,
        dimensionPaint,
      );
      canvas.drawLine(
        end + normal * 5.0,
        end + normal * placement.offset,
        dimensionPaint,
      );
      canvas.drawLine(dimensionStart, dimensionEnd, dimensionPaint);

      _drawIsoDimensionArrow(canvas, dimensionStart, tangent, dimensionPaint);
      _drawIsoDimensionArrow(
        canvas,
        dimensionEnd,
        tangent * -1,
        dimensionPaint,
      );

      final label = switch (dimension.kind) {
        DimensionKind.opening => _openingDimensionLabelForId(
          room,
          dimension.id,
        ),
        DimensionKind.wall => formatLength(
          _dimensionLengthMeters(room, dimension),
        ),
        DimensionKind.total => formatLength(
          _dimensionLengthMeters(room, dimension),
        ),
      };
      if (label.isEmpty) {
        continue;
      }

      final textPainter = _adaptiveTextPainter(
        text: label,
        color: const Color(0xFF174EA6),
        preferredFontSize: dimension.kind == DimensionKind.opening ? 9 : 10,
        minimumFontSize: 7,
        availableWidth: math.max(20.0, screenLength - 8.0),
        maxLines: dimension.kind == DimensionKind.opening ? 2 : 1,
      );
      if (textPainter == null) {
        continue;
      }

      var angle = math.atan2(tangent.dy, tangent.dx);
      if (angle > math.pi / 2 || angle < -math.pi / 2) {
        angle += math.pi;
      }

      final labelCenter = _findAvailableLabelCenter(
        preferredCenter: Offset(
          (dimensionStart.dx + dimensionEnd.dx) / 2.0,
          (dimensionStart.dy + dimensionEnd.dy) / 2.0,
        ),
        normal: normal,
        angle: angle,
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      );
      if (labelCenter == null) {
        continue;
      }

      _occupiedLabelRects.add(
        _rotatedLabelBounds(
          center: labelCenter,
          angle: angle,
          width: textPainter.width + 8,
          height: textPainter.height + 4,
        ).inflate(2),
      );

      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(angle);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2.0, -textPainter.height / 2.0),
      );
      canvas.restore();
    }
  }

  void _drawIsoDimensionArrow(
    Canvas canvas,
    Offset tip,
    Offset direction,
    Paint paint,
  ) {
    final length = direction.distance;
    if (length < 0.000001) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    const arrowLength = 7.0;
    const arrowHalfWidth = 2.4;
    final base = tip + unit * arrowLength;
    canvas.drawLine(tip, base + normal * arrowHalfWidth, paint);
    canvas.drawLine(tip, base - normal * arrowHalfWidth, paint);
  }

  String _openingDimensionLabelForId(RoomModel room, String dimensionId) {
    final marker = ':opening:';
    final markerIndex = dimensionId.indexOf(marker);
    if (markerIndex < 0) {
      return '';
    }
    final featureId = dimensionId.substring(markerIndex + marker.length);
    for (final feature in room.features) {
      if (feature.id == featureId) {
        return formatOpeningDimensions(feature);
      }
    }
    return '';
  }

  double _dimensionLengthMeters(RoomModel room, DimensionSegment dimension) {
    final pointByScreen = <ARPoint>[];
    for (final point in room.points) {
      final screen = transform(point);
      if ((screen.dx - dimension.x1).abs() < 0.01 &&
          (screen.dy - dimension.y1).abs() < 0.01) {
        pointByScreen.add(point);
      }
      if ((screen.dx - dimension.x2).abs() < 0.01 &&
          (screen.dy - dimension.y2).abs() < 0.01) {
        pointByScreen.add(point);
      }
    }

    if (pointByScreen.length >= 2) {
      return GeometryService.calculateDistance(
        pointByScreen.first,
        pointByScreen.last,
      );
    }

    final scale = _screenMetersScale(room);
    return dimension.length / math.max(scale, 0.000001);
  }

  double _screenMetersScale(RoomModel room) {
    for (var index = 0; index < room.points.length - 1; index++) {
      final first = transform(room.points[index]);
      final second = transform(room.points[index + 1]);
      final meters = GeometryService.calculateDistance(
        room.points[index],
        room.points[index + 1],
      );
      final pixels = (second - first).distance;
      if (meters > 0.000001 && pixels > 0.000001) {
        return pixels / meters;
      }
    }
    return 1.0;
  }

  Rect _boundsForPoints(List<Offset> points) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final point in points) {
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _isLabelAreaAvailable(Rect bounds) {
    return !_occupiedLabelRects.any(
      (occupied) => occupied.overlaps(bounds.inflate(2)),
    );
  }

  TextPainter? _adaptiveTextPainter({
    required String text,
    required Color color,
    required double preferredFontSize,
    required double minimumFontSize,
    required double availableWidth,
    int maxLines = 1,
  }) {
    if (availableWidth < 12) {
      return null;
    }
    var fontSize = preferredFontSize;
    while (fontSize >= minimumFontSize - 0.001) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
      )..layout(maxWidth: availableWidth);
      if (!painter.didExceedMaxLines &&
          painter.width <= availableWidth + 0.001) {
        return painter;
      }
      fontSize -= 0.5;
    }
    return null;
  }

  Rect _rotatedLabelBounds({
    required Offset center,
    required double angle,
    required double width,
    required double height,
  }) {
    final cosine = math.cos(angle).abs();
    final sine = math.sin(angle).abs();
    return Rect.fromCenter(
      center: center,
      width: width * cosine + height * sine,
      height: width * sine + height * cosine,
    );
  }

  Offset? _findAvailableLabelCenter({
    required Offset preferredCenter,
    required Offset normal,
    required double angle,
    required double width,
    required double height,
  }) {
    for (final offset in const [0.0, 12.0, 24.0]) {
      final center = preferredCenter + normal * offset;
      final bounds = _rotatedLabelBounds(
        center: center,
        angle: angle,
        width: width,
        height: height,
      );
      if (_isLabelAreaAvailable(bounds)) {
        return center;
      }
    }
    return null;
  }

  // ===========================================================================
  // PUERTAS Y VENTANAS
  // ===========================================================================

  void _drawFeatures(
    Canvas canvas,
    RoomModel room,
    Paint doorPaint,
    Paint windowPaint,
    Paint selectedPaint,
    Paint referencePaint,
    Map<String, String> featureOwnerRoomIds,
  ) {
    for (final feature in room.features) {
      if (featureOwnerRoomIds[feature.id] != room.id) {
        continue;
      }

      final start = transform(feature.start);

      final end = transform(feature.end);

      final isSelected =
          room.id == selectedRoomId && feature.id == selectedFeatureId;

      if (isSelected) {
        canvas.drawLine(start, end, selectedPaint);
      }

      switch (feature.type) {
        case FeatureType.door:
          _drawProfessionalDoor(
            canvas: canvas,
            feature: feature,
            start: start,
            end: end,
            paint: doorPaint,
          );
          break;

        case FeatureType.window:
          _drawProfessionalWindow(
            canvas: canvas,
            start: start,
            end: end,
            paint: windowPaint,
          );
          break;
      }

      if (continuationSelectionMode && feature.isConnected) {
        final unavailablePaint = Paint()
          ..color = Colors.grey.withOpacity(0.35)
          ..strokeWidth = 5.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(start, end, unavailablePaint);
      }

      if (!feature.isConnected) {
        _drawContinuationPoint(
          canvas,
          start,
          referencePaint,
          selected: isSelected,
        );
      }
    }
  }

  void _drawProfessionalDoor({
    required Canvas canvas,
    required WallFeature feature,
    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    final opening = end - start;
    final width = opening.distance;

    if (width <= 0.000001) {
      return;
    }

    final tangent = opening / width;
    final leftNormal = Offset(-tangent.dy, tangent.dx);
    final baseSwingNormal = feature.doorSwingSide == DoorSwingSide.left
        ? leftNormal
        : -leftNormal;
    final swingNormal =
        feature.doorOpeningDirection == DoorOpeningDirection.interior
        ? baseSwingNormal
        : -baseSwingNormal;
    final hinge = feature.doorHingeSide == DoorHingeSide.start ? start : end;
    final latch = feature.doorHingeSide == DoorHingeSide.start ? end : start;
    final closedDirection = (latch - hinge) / width;
    final erasePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final symbolPaint = Paint()
      ..color = paint.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final leafEnd = hinge + swingNormal * width;

    // Interrumpe gráficamente la pared en el ancho real de la puerta.
    canvas.drawLine(start, end, erasePaint);

    // Hoja abierta a 90 grados según la orientación elegida.
    canvas.drawLine(hinge, leafEnd, symbolPaint);
    canvas.drawCircle(
      hinge,
      2.5,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );

    final startAngle = math.atan2(closedDirection.dy, closedDirection.dx);
    final inwardAngle = math.atan2(swingNormal.dy, swingNormal.dx);
    final sweepAngle = _shortestSweep(startAngle, inwardAngle);

    canvas.drawArc(
      Rect.fromCircle(center: hinge, radius: width),
      startAngle,
      sweepAngle,
      false,
      symbolPaint,
    );
  }

  void _drawProfessionalWindow({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    final opening = end - start;
    final width = opening.distance;

    if (width <= 0.000001) {
      return;
    }

    final tangent = opening / width;
    final normal = Offset(-tangent.dy, tangent.dx);
    final erasePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final symbolPaint = Paint()
      ..color = paint.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    const railOffset = 2.5;

    canvas.drawLine(start, end, erasePaint);
    canvas.drawLine(
      start + normal * railOffset,
      end + normal * railOffset,
      symbolPaint,
    );
    canvas.drawLine(
      start - normal * railOffset,
      end - normal * railOffset,
      symbolPaint,
    );
    canvas.drawLine(start - normal * 5, start + normal * 5, symbolPaint);
    canvas.drawLine(end - normal * 5, end + normal * 5, symbolPaint);
  }

  double _shortestSweep(double startAngle, double endAngle) {
    var sweep = endAngle - startAngle;

    while (sweep > math.pi) {
      sweep -= math.pi * 2;
    }

    while (sweep < -math.pi) {
      sweep += math.pi * 2;
    }

    return sweep;
  }

  void _drawContinuationPoint(
    Canvas canvas,
    Offset point,
    Paint referencePaint, {
    required bool selected,
  }) {
    canvas.drawCircle(point, selected ? 10 : 8, referencePaint);

    canvas.drawCircle(point, selected ? 4 : 3, Paint()..color = Colors.white);
  }

  // REPAINT
  // ===========================================================================

  @override
  bool shouldRepaint(covariant FloorPlanPainter oldDelegate) {
    return true;
  }
}
