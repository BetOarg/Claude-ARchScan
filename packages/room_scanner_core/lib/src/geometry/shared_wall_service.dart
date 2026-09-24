import 'dart:math' as math;

import '../models/room_model.dart';
import '../utils/geometry_tolerance.dart';

enum SharedWallCoverage { complete, partial }

class SharedWallSegment {
  static const double _coverageToleranceMeters = 0.001;

  final String firstRoomId;
  final int firstWallIndex;
  final String secondRoomId;
  final int secondWallIndex;
  final ARPoint start;
  final ARPoint end;
  final double firstWallLengthMeters;
  final double secondWallLengthMeters;

  const SharedWallSegment({
    required this.firstRoomId,
    required this.firstWallIndex,
    required this.secondRoomId,
    required this.secondWallIndex,
    required this.start,
    required this.end,
    required this.firstWallLengthMeters,
    required this.secondWallLengthMeters,
  });

  double get lengthMeters {
    final dx = end.x - start.x;
    final dz = end.z - start.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  double get firstWallCoverage =>
      firstWallLengthMeters <= _coverageToleranceMeters
      ? 0
      : (lengthMeters / firstWallLengthMeters).clamp(0.0, 1.0).toDouble();

  double get secondWallCoverage =>
      secondWallLengthMeters <= _coverageToleranceMeters
      ? 0
      : (lengthMeters / secondWallLengthMeters).clamp(0.0, 1.0).toDouble();

  bool get coversFirstWall =>
      lengthMeters >= firstWallLengthMeters - _coverageToleranceMeters;

  bool get coversSecondWall =>
      lengthMeters >= secondWallLengthMeters - _coverageToleranceMeters;

  SharedWallCoverage get coverage => coversFirstWall && coversSecondWall
      ? SharedWallCoverage.complete
      : SharedWallCoverage.partial;
}

class SharedWallService {
  const SharedWallService._();

  static List<SharedWallSegment> detect({
    required List<RoomModel> rooms,
    double lineToleranceMeters = 0.025,
    double angleToleranceDegrees = 1.0,
    double minimumOverlapMeters = 0.20,
  }) {
    if (rooms.length < 2) {
      return const [];
    }

    final matches = <SharedWallSegment>[];
    final maximumCross = math.sin(angleToleranceDegrees * math.pi / 180.0);

    for (
      var firstRoomIndex = 0;
      firstRoomIndex < rooms.length - 1;
      firstRoomIndex++
    ) {
      final firstRoom = rooms[firstRoomIndex];
      if (firstRoom.points.length < 2) {
        continue;
      }

      for (
        var secondRoomIndex = firstRoomIndex + 1;
        secondRoomIndex < rooms.length;
        secondRoomIndex++
      ) {
        final secondRoom = rooms[secondRoomIndex];
        if (secondRoom.points.length < 2) {
          continue;
        }

        final firstWallCount = firstRoom.isClosed
            ? firstRoom.points.length
            : firstRoom.points.length - 1;
        final secondWallCount = secondRoom.isClosed
            ? secondRoom.points.length
            : secondRoom.points.length - 1;

        for (
          var firstWallIndex = 0;
          firstWallIndex < firstWallCount;
          firstWallIndex++
        ) {
          final firstStart = firstRoom.points[firstWallIndex];
          final firstEnd =
              firstRoom.points[(firstWallIndex + 1) % firstRoom.points.length];
          final firstDx = firstEnd.x - firstStart.x;
          final firstDz = firstEnd.z - firstStart.z;
          final firstLength = math.sqrt(firstDx * firstDx + firstDz * firstDz);
          if (firstLength <= kGeometryEpsilon) {
            continue;
          }
          final unitX = firstDx / firstLength;
          final unitZ = firstDz / firstLength;

          for (
            var secondWallIndex = 0;
            secondWallIndex < secondWallCount;
            secondWallIndex++
          ) {
            final secondStart = secondRoom.points[secondWallIndex];
            final secondEnd = secondRoom
                .points[(secondWallIndex + 1) % secondRoom.points.length];
            final secondDx = secondEnd.x - secondStart.x;
            final secondDz = secondEnd.z - secondStart.z;
            final secondLength = math.sqrt(
              secondDx * secondDx + secondDz * secondDz,
            );
            if (secondLength <= kGeometryEpsilon) {
              continue;
            }
            final secondUnitX = secondDx / secondLength;
            final secondUnitZ = secondDz / secondLength;
            final directionCross = (unitX * secondUnitZ - unitZ * secondUnitX)
                .abs();
            if (directionCross > maximumCross) {
              continue;
            }

            final startDistance =
                ((secondStart.x - firstStart.x) * -unitZ +
                        (secondStart.z - firstStart.z) * unitX)
                    .abs();
            final endDistance =
                ((secondEnd.x - firstStart.x) * -unitZ +
                        (secondEnd.z - firstStart.z) * unitX)
                    .abs();
            if (startDistance > lineToleranceMeters ||
                endDistance > lineToleranceMeters) {
              continue;
            }

            final secondStartProjection =
                (secondStart.x - firstStart.x) * unitX +
                (secondStart.z - firstStart.z) * unitZ;
            final secondEndProjection =
                (secondEnd.x - firstStart.x) * unitX +
                (secondEnd.z - firstStart.z) * unitZ;
            final overlapStart = math.max(
              0.0,
              math.min(secondStartProjection, secondEndProjection),
            );
            final overlapEnd = math.min(
              firstLength,
              math.max(secondStartProjection, secondEndProjection),
            );
            if (overlapEnd - overlapStart < minimumOverlapMeters) {
              continue;
            }

            ARPoint pointAt(double distance) {
              final fraction = distance / firstLength;
              return ARPoint(
                x: firstStart.x + unitX * distance,
                y: firstStart.y + (firstEnd.y - firstStart.y) * fraction,
                z: firstStart.z + unitZ * distance,
              );
            }

            matches.add(
              SharedWallSegment(
                firstRoomId: firstRoom.id,
                firstWallIndex: firstWallIndex,
                secondRoomId: secondRoom.id,
                secondWallIndex: secondWallIndex,
                start: pointAt(overlapStart),
                end: pointAt(overlapEnd),
                firstWallLengthMeters: firstLength,
                secondWallLengthMeters: secondLength,
              ),
            );
          }
        }
      }
    }

    return matches;
  }
}
