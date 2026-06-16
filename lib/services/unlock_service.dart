import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'time_service.dart';

enum UnlockStatusType { locked, unlocked, gracePeriod }

class UnlockRecord {
  final int unlockTimestamp;
  final int expiryTimestamp;
  final String adUnitId;
  final String transactionId;
  final String hmac;

  const UnlockRecord({
    required this.unlockTimestamp,
    required this.expiryTimestamp,
    required this.adUnitId,
    required this.transactionId,
    required this.hmac,
  });

  Map<String, dynamic> toJson() => {
    'unlockTimestamp': unlockTimestamp,
    'expiryTimestamp': expiryTimestamp,
    'adUnitId': adUnitId,
    'transactionId': transactionId,
    'hmac': hmac,
  };

  factory UnlockRecord.fromJson(Map<String, dynamic> json) => UnlockRecord(
    unlockTimestamp: json['unlockTimestamp'] as int,
    expiryTimestamp: json['expiryTimestamp'] as int,
    adUnitId: json['adUnitId'] as String,
    transactionId: json['transactionId'] as String,
    hmac: json['hmac'] as String,
  );
}

class UnlockService {
  final TimeService _timeService;
  static const _boxName = 'unlock';
  static const _recordKey = 'unlock_record';
  static const _unlockDuration = Duration(hours: 2);
  static const _graceDuration = Duration(minutes: 20);
  final String _hmacSecret;

  UnlockService({
    required TimeService timeService,
    String? hmacSecret,
  }) : _timeService = timeService,
       _hmacSecret = hmacSecret ?? 'fautomatik_v1_hmac_secret';

  String _computeHmac(int unlockTimestamp, int expiryTimestamp, String transactionId) {
    final data = '$unlockTimestamp|$expiryTimestamp|$transactionId';
    final hmac = Hmac(sha256, utf8.encode(_hmacSecret));
    return base64.encode(hmac.convert(utf8.encode(data)).bytes);
  }

  String _generateTransactionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  Future<Box<String>> get _box => Hive.openBox<String>(_boxName);

  Future<UnlockRecord?> _loadRecord() async {
    final box = await _box;
    final raw = box.get(_recordKey);
    if (raw == null) return null;
    try {
      return UnlockRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRecord(UnlockRecord record) async {
    final box = await _box;
    await box.put(_recordKey, jsonEncode(record.toJson()));
  }

  bool _verifyHmac(UnlockRecord record) {
    final expected = _computeHmac(
      record.unlockTimestamp,
      record.expiryTimestamp,
      record.transactionId,
    );
    return record.hmac == expected;
  }

  Future<UnlockStatusType> checkStatus() async {
    try {
      final now = await _timeService.now();
      final record = await _loadRecord();

      if (record == null) return UnlockStatusType.locked;
      if (!_verifyHmac(record)) {
        await _clear();
        return UnlockStatusType.locked;
      }

      final expiry = DateTime.fromMillisecondsSinceEpoch(
        record.expiryTimestamp * 1000,
        isUtc: true,
      );

      if (now.isBefore(expiry)) return UnlockStatusType.unlocked;

      final graceEnd = expiry.add(_graceDuration);
      if (now.isBefore(graceEnd)) {
        final online = await _timeService.isOnline();
        if (!online) return UnlockStatusType.gracePeriod;
      }

      return UnlockStatusType.locked;
    } on TimeException {
      final record = await _loadRecord();
      if (record == null) return UnlockStatusType.locked;
      if (!_verifyHmac(record)) {
        await _clear();
        return UnlockStatusType.locked;
      }
      final deviceNow = DateTime.now().toUtc();
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        record.expiryTimestamp * 1000,
        isUtc: true,
      );

      if (deviceNow.isBefore(expiry)) return UnlockStatusType.unlocked;

      final graceEnd = expiry.add(_graceDuration);
      if (deviceNow.isBefore(graceEnd)) return UnlockStatusType.gracePeriod;

      return UnlockStatusType.locked;
    }
  }

  Future<DateTime?> getExpiryTime() async {
    final record = await _loadRecord();
    if (record == null) return null;
    if (!_verifyHmac(record)) {
      await _clear();
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      record.expiryTimestamp * 1000,
      isUtc: true,
    );
  }

  Future<UnlockRecord> unlock() async {
    final now = await _timeService.now();
    final unlockTs = now.millisecondsSinceEpoch ~/ 1000;
    final expiryTs = now.add(_unlockDuration).millisecondsSinceEpoch ~/ 1000;
    final transactionId = _generateTransactionId();
    final hmac = _computeHmac(unlockTs, expiryTs, transactionId);

    final record = UnlockRecord(
      unlockTimestamp: unlockTs,
      expiryTimestamp: expiryTs,
      adUnitId: '',
      transactionId: transactionId,
      hmac: hmac,
    );

    await _saveRecord(record);
    return record;
  }

  Future<void> revoke() async {
    await _clear();
  }

  Future<void> _clear() async {
    final box = await _box;
    await box.delete(_recordKey);
  }
}
