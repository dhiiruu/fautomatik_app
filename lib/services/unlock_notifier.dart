import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'unlock_service.dart';
import 'ad_service.dart';
import 'time_service.dart';

enum UnlockStatus { locked, unlocked, gracePeriod, initializing }

class UnlockState {
  final UnlockStatus status;
  final DateTime? expiryTime;
  final Duration? timeRemaining;
  final bool isLoading;
  final bool adAvailable;
  final String? error;
  final bool isGracePeriod;

  const UnlockState({
    required this.status,
    this.expiryTime,
    this.timeRemaining,
    this.isLoading = false,
    this.adAvailable = false,
    this.error,
    this.isGracePeriod = false,
  });

  static const initializing = UnlockState(status: UnlockStatus.initializing, isLoading: true);
  static const locked = UnlockState(status: UnlockStatus.locked);

  factory UnlockState.unlocked(DateTime expiryTime) {
    final remaining = expiryTime.difference(DateTime.now().toUtc());
    return UnlockState(
      status: UnlockStatus.unlocked,
      expiryTime: expiryTime,
      timeRemaining: remaining.isNegative ? Duration.zero : remaining,
    );
  }

  factory UnlockState.gracePeriod({DateTime? expiryTime, String? error}) {
    return UnlockState(
      status: UnlockStatus.gracePeriod,
      expiryTime: expiryTime,
      isGracePeriod: true,
      error: error,
    );
  }

  UnlockState copyWith({
    UnlockStatus? status,
    DateTime? expiryTime,
    Duration? timeRemaining,
    bool? isLoading,
    bool? adAvailable,
    String? error,
    bool? isGracePeriod,
  }) {
    return UnlockState(
      status: status ?? this.status,
      expiryTime: expiryTime ?? this.expiryTime,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      isLoading: isLoading ?? this.isLoading,
      adAvailable: adAvailable ?? this.adAvailable,
      error: error ?? this.error,
      isGracePeriod: isGracePeriod ?? this.isGracePeriod,
    );
  }
}

class UnlockNotifier extends StateNotifier<UnlockState> {
  final UnlockService _unlockService;
  final AdService _adService;
  final TimeService _timeService;
  Timer? _countdownTimer;
  Timer? _preloadTimer;
  Timer? _statusCheckTimer;

  UnlockNotifier({
    required UnlockService unlockService,
    required AdService adService,
    required TimeService timeService,
  }) : _unlockService = unlockService,
       _adService = adService,
       _timeService = timeService,
       super(UnlockState.initializing) {
    _init();
  }

  Future<void> _init() async {
    try {
      await _adService.initialize();
      _adService.loadAd();
    } catch (_) {
      // Ad init paused — non-blocking
    }

    try {
      await _checkAndUpdateState().timeout(const Duration(seconds: 15));
    } catch (_) {
      state = UnlockState.locked;
    }

    _statusCheckTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _checkAndUpdateState(),
    );
  }

  Future<void> _checkAndUpdateState() async {
    final statusType = await _unlockService.checkStatus();
    final adAvailable = _adService.isAdAvailable;

    switch (statusType) {
      case UnlockStatusType.unlocked:
        final expiry = await _unlockService.getExpiryTime();
        if (expiry != null) {
          state = UnlockState.unlocked(expiry);
          _startCountdown(expiry);
          _schedulePreload(expiry);
        } else {
          state = UnlockState.locked.copyWith(adAvailable: adAvailable);
        }
      case UnlockStatusType.gracePeriod:
        final expiry = await _unlockService.getExpiryTime();
        state = UnlockState.gracePeriod(expiryTime: expiry);
      case UnlockStatusType.locked:
        state = UnlockState.locked.copyWith(adAvailable: adAvailable);
    }
  }

  void _startCountdown(DateTime expiry) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = expiry.difference(DateTime.now().toUtc());
      if (remaining.isNegative) {
        _countdownTimer?.cancel();
        _onExpiry();
      } else {
        state = state.copyWith(timeRemaining: remaining);
      }
    });
  }

  void _schedulePreload(DateTime expiry) {
    _preloadTimer?.cancel();
    final preloadTime = expiry.subtract(const Duration(minutes: 5));
    final delay = preloadTime.difference(DateTime.now().toUtc());

    if (delay.isNegative) {
      _adService.loadAd();
      return;
    }

    _preloadTimer = Timer(delay, () {
      _adService.loadAd();
    });
  }

  Future<void> _onExpiry() async {
    _countdownTimer?.cancel();
    _preloadTimer?.cancel();

    try {
      final online = await _timeService.isOnline();

      if (!online) {
        final expiry = await _unlockService.getExpiryTime();
        state = UnlockState.gracePeriod(expiryTime: expiry);

        Timer(const Duration(minutes: 2), () async {
          final stillOnline = await _timeService.isOnline();
          if (stillOnline) {
            await _checkAndUpdateState();
          }
        });
      } else {
        state = UnlockState.locked.copyWith(adAvailable: _adService.isAdAvailable);
        _adService.loadAd();
      }
    } catch (_) {
      state = UnlockState.gracePeriod();
    }
  }

  Future<void> watchAd() async {
    state = state.copyWith(isLoading: true, error: null);

    if (!_adService.isAdAvailable) {
      _adService.loadAd();
      state = state.copyWith(isLoading: false, error: 'Ad not ready yet. Please try again.');
      return;
    }

    final rewarded = await _adService.showAd();

    if (rewarded) {
      await _unlockService.unlock();
      final expiry = await _unlockService.getExpiryTime();
      if (expiry != null) {
        state = UnlockState.unlocked(expiry);
        _startCountdown(expiry);
        _schedulePreload(expiry);
      }
    } else {
      state = state.copyWith(
        isLoading: false,
        error: 'Ad was not completed. Please try again.',
      );
    }
  }

  void dismissError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _preloadTimer?.cancel();
    _statusCheckTimer?.cancel();
    _adService.dispose();
    super.dispose();
  }
}
