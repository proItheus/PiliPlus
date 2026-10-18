/// Hybrid Logical Clock timestamp, ordered lexicographically by physical time
/// and logical counter.
final class HlcTimestamp implements Comparable<HlcTimestamp> {
  const HlcTimestamp({required this.physicalMs, required this.logical});

  static const int maxComponent = 0x7fffffffffffffff;

  final int physicalMs;
  final int logical;

  factory HlcTimestamp.fromJson(Map<String, dynamic> json) {
    if (json.length != 2 ||
        json['physical_ms'] is! int ||
        json['logical'] is! int) {
      throw const FormatException('Invalid HLC timestamp');
    }
    final physicalMs = json['physical_ms'] as int;
    final logical = json['logical'] as int;
    if (physicalMs < 0 ||
        logical < 0 ||
        physicalMs > maxComponent ||
        logical > maxComponent) {
      throw const FormatException('Invalid HLC components');
    }
    return HlcTimestamp(physicalMs: physicalMs, logical: logical);
  }

  Map<String, int> toJson() => {
    'physical_ms': physicalMs,
    'logical': logical,
  };

  @override
  int compareTo(HlcTimestamp other) {
    final physical = physicalMs.compareTo(other.physicalMs);
    return physical != 0 ? physical : logical.compareTo(other.logical);
  }

  @override
  bool operator ==(Object other) =>
      other is HlcTimestamp &&
      physicalMs == other.physicalMs &&
      logical == other.logical;

  @override
  int get hashCode => Object.hash(physicalMs, logical);
}

/// Mutable HLC arithmetic. Persistence is owned by the caller.
final class HybridLogicalClock {
  HybridLogicalClock([HlcTimestamp? initial])
    : _last = initial ?? const HlcTimestamp(physicalMs: 0, logical: 0);

  HlcTimestamp _last;

  HlcTimestamp get last => _last;

  HlcTimestamp tick(int nowMs) {
    if (nowMs > _last.physicalMs) {
      _last = HlcTimestamp(physicalMs: nowMs, logical: 0);
    } else {
      _last = HlcTimestamp(
        physicalMs: _last.physicalMs,
        logical: _increment(_last.logical),
      );
    }
    return _last;
  }

  HlcTimestamp observe(HlcTimestamp remote, int nowMs) {
    final physical = _max(nowMs, _last.physicalMs, remote.physicalMs);
    final logical =
        physical == _last.physicalMs && physical == remote.physicalMs
        ? _increment(
            _last.logical > remote.logical ? _last.logical : remote.logical,
          )
        : physical == _last.physicalMs
        ? _increment(_last.logical)
        : physical == remote.physicalMs
        ? _increment(remote.logical)
        : 0;
    _last = HlcTimestamp(physicalMs: physical, logical: logical);
    return _last;
  }

  static int _max(int a, int b, int c) =>
      a > b ? (a > c ? a : c) : (b > c ? b : c);

  static int _increment(int value) {
    if (value == HlcTimestamp.maxComponent) {
      throw StateError('HLC logical component overflow');
    }
    return value + 1;
  }
}
