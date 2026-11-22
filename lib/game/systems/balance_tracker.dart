import 'dart:math' as math;

/// Live combat measurements for balance tuning: rolling damage per second,
/// boss fight durations and damage taken. Cheap enough to always run; the
/// HUD only draws it when the "Combat stats" setting is on.
class BalanceTracker {
  static const _bucket = 0.25;
  static const _window = 12; // 12 × 0.25s = 3s rolling window

  final _buckets = List<double>.filled(_window, 0);
  int _head = 0;
  double _bucketT = 0;

  double damageTaken = 0;
  int hitsTaken = 0;
  String lastHitSource = 'unknown';

  /// Play-time when the current boss appeared (null outside boss fights).
  double? bossStartedAt;
  final List<int> bossSeconds = [];

  void dealt(double amount) => _buckets[_head] += amount;

  void took(double amount, String source) {
    damageTaken += amount;
    hitsTaken++;
    lastHitSource = source;
  }

  void tick(double dt) {
    _bucketT += dt;
    while (_bucketT >= _bucket) {
      _bucketT -= _bucket;
      _head = (_head + 1) % _window;
      _buckets[_head] = 0;
    }
  }

  /// Damage per second over the last ~3s.
  double get dps {
    var sum = 0.0;
    for (final b in _buckets) {
      sum += b;
    }
    return sum / (_window * _bucket);
  }

  void bossStarted(double playTime) => bossStartedAt = playTime;

  void bossEnded(double playTime) {
    final s = bossStartedAt;
    if (s != null) bossSeconds.add(math.max(0, (playTime - s).round()));
    bossStartedAt = null;
  }

  void reset() {
    _buckets.fillRange(0, _window, 0);
    _head = 0;
    _bucketT = 0;
    damageTaken = 0;
    hitsTaken = 0;
    lastHitSource = 'unknown';
    bossStartedAt = null;
    bossSeconds.clear();
  }
}
