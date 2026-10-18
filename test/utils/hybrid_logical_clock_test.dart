import 'package:PiliPlus/utils/hybrid_logical_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HybridLogicalClock', () {
    test('ticks increase through repeated time and wall-clock rollback', () {
      final clock = HybridLogicalClock();
      final first = clock.tick(100);
      final second = clock.tick(100);
      final rollback = clock.tick(90);

      expect(first, const HlcTimestamp(physicalMs: 100, logical: 0));
      expect(second, const HlcTimestamp(physicalMs: 100, logical: 1));
      expect(rollback, const HlcTimestamp(physicalMs: 100, logical: 2));
      expect(first.compareTo(second), lessThan(0));
      expect(second.compareTo(rollback), lessThan(0));
    });

    test('observes remote future timestamp before next local tick', () {
      final clock = HybridLogicalClock(
        const HlcTimestamp(physicalMs: 10, logical: 4),
      );
      final observed = clock.observe(
        const HlcTimestamp(physicalMs: 500, logical: 7),
        20,
      );
      expect(observed, const HlcTimestamp(physicalMs: 500, logical: 8));
      expect(clock.tick(20), const HlcTimestamp(physicalMs: 500, logical: 9));
    });

    test('serializes and strictly validates timestamp components', () {
      const timestamp = HlcTimestamp(physicalMs: 1730000000000, logical: 3);
      expect(HlcTimestamp.fromJson(timestamp.toJson()), timestamp);
      expect(
        () => HlcTimestamp.fromJson({'physical_ms': -1, 'logical': 0}),
        throwsFormatException,
      );
      expect(
        () => HlcTimestamp.fromJson({
          'physical_ms': 1,
          'logical': 0,
          'extra': 1,
        }),
        throwsFormatException,
      );
    });

    test('observation handles equal physical components monotonically', () {
      final clock = HybridLogicalClock(
        const HlcTimestamp(physicalMs: 100, logical: 2),
      );
      expect(
        clock.observe(const HlcTimestamp(physicalMs: 100, logical: 7), 100),
        const HlcTimestamp(physicalMs: 100, logical: 8),
      );
    });
  });
}
