import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/time_service.dart';
import '../services/ad_service.dart';
import '../services/unlock_service.dart';
import '../services/unlock_notifier.dart';

const _testAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

final timeServiceProvider = Provider<TimeService>((ref) => TimeService());

final adServiceProvider = Provider<AdService>((ref) {
  return AdService(adUnitId: _testAdUnitId);
});

final unlockServiceProvider = Provider<UnlockService>((ref) {
  return UnlockService(
    timeService: ref.watch(timeServiceProvider),
  );
});

final unlockNotifierProvider = StateNotifierProvider<UnlockNotifier, UnlockState>((ref) {
  return UnlockNotifier(
    unlockService: ref.watch(unlockServiceProvider),
    adService: ref.watch(adServiceProvider),
    timeService: ref.watch(timeServiceProvider),
  );
});
