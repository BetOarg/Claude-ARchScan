import 'package:test/test.dart';

import 'package:room_scanner_core/src/export/dimension_layout.dart';

void main() {
  test('orders openings, wall segments, then totals', () {
    final dimensions = [
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 4,
        y2: 0,
        kind: DimensionKind.total,
        id: 'total',
      ),
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 2,
        y2: 0,
        kind: DimensionKind.wall,
        id: 'wall',
      ),
      const DimensionSegment(
        x1: 0,
        y1: 0,
        x2: 0.8,
        y2: 0,
        kind: DimensionKind.opening,
        id: 'door',
      ),
    ];

    expect(
      DimensionLayout.sort(dimensions).map((d) => d.id).toList(),
      ['door', 'wall', 'total'],
    );
  });

  test('removes reversed duplicates on the same axis', () {
    const original = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 2,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'a',
    );
    const reversed = DimensionSegment(
      x1: 2,
      y1: 0,
      x2: 0,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'b',
    );

    expect(DimensionLayout.deduplicate([original, reversed]), hasLength(1));
  });

  test('moves a colliding parallel dimension to the next level', () {
    const first = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 3,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'first',
      centerX: 1.5,
      centerY: 1,
    );
    const second = DimensionSegment(
      x1: 0.5,
      y1: 0,
      x2: 2.5,
      y2: 0,
      kind: DimensionKind.wall,
      id: 'second',
      centerX: 1.5,
      centerY: 1,
    );

    final placements = DimensionLayout.layout([first, second]);

    expect(placements, hasLength(2));
    expect(placements[0].level, 0);
    expect(placements[1].level, greaterThan(0));
    expect(placements[1].offset, greaterThan(placements[0].offset));
  });

  test('keeps shorter dimensions closer than totals', () {
    const opening = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 0.8,
      y2: 0,
      kind: DimensionKind.opening,
      id: 'opening',
      centerX: 2,
      centerY: 2,
    );
    const total = DimensionSegment(
      x1: 0,
      y1: 0,
      x2: 4,
      y2: 0,
      kind: DimensionKind.total,
      id: 'total',
      centerX: 2,
      centerY: 2,
    );

    final placements = DimensionLayout.layout([total, opening]);

    expect(placements.first.segment.id, 'opening');
    expect(placements.last.segment.id, 'total');
    expect(placements.last.offset, greaterThan(placements.first.offset));
  });
}
