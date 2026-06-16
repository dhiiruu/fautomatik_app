import 'dart:async';
import 'package:ntp/ntp.dart';

class TimeException implements Exception {
  final String message;
  TimeException(this.message);
  @override
  String toString() => 'TimeException: $message';
}

class TimeService {
  Duration? _cachedOffset;
  DateTime _offsetCachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _offsetCacheDuration = Duration(minutes: 5);
  static const _ntpTimeout = Duration(seconds: 5);
  int _consecutiveNtpFailures = 0;
  static const _maxConsecutiveFailures = 3;

  Duration? get cachedOffset => _cachedOffset;
  DateTime get offsetCachedAt => _offsetCachedAt;

  Future<DateTime> now() async {
    try {
      final ntpTime = await NTP.now().timeout(_ntpTimeout);
      final deviceUtc = DateTime.now().toUtc();
      _cachedOffset = ntpTime.difference(deviceUtc);
      _offsetCachedAt = deviceUtc;
      _consecutiveNtpFailures = 0;
      return ntpTime;
    } catch (e) {
      _consecutiveNtpFailures++;
      if (_cachedOffset != null) {
        final elapsed = DateTime.now().toUtc().difference(_offsetCachedAt);
        final tooLongSinceSync = elapsed > _offsetCacheDuration * (_consecutiveNtpFailures + 1);
        if (tooLongSinceSync && _consecutiveNtpFailures > _maxConsecutiveFailures) {
          throw TimeException('NTP unavailable and cached offset is too old');
        }
        return DateTime.now().toUtc().add(_cachedOffset!);
      }
      return DateTime.now().toUtc();
    }
  }

  Future<bool> isOnline() async {
    try {
      await NTP.now().timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Duration> ntpOffset() async {
    await now();
    return _cachedOffset ?? Duration.zero;
  }
}
