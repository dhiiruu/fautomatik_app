import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum AdStatus { uninitialized, loading, loaded, failed }

class AdService {
  RewardedAd? _rewardedAd;
  AdStatus _status = AdStatus.uninitialized;
  Completer<bool>? _showCompleter;
  bool _initialized = false;
  int _loadAttempts = 0;
  static const _maxRetries = 5;

  final String adUnitId;

  AdService({required this.adUnitId});

  AdStatus get status => _status;
  bool get isAdAvailable => _rewardedAd != null;
  int get loadAttempts => _loadAttempts;

  Future<void> initialize() async {
    if (_initialized) return;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await MobileAds.instance.initialize();
      } catch (_) {
        // Paused: ad initialization failure is non-critical at startup
      }
    }
    _initialized = true;
  }

  bool get _isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> loadAd() async {
    if (!_isMobilePlatform) return;
    if (!_initialized) await initialize();
    if (_status == AdStatus.loading) return;

    _status = AdStatus.loading;

    await RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _status = AdStatus.loaded;
          _loadAttempts = 0;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              _onAdDismissed();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              _onAdFailedToShow(error);
            },
            onAdImpression: (ad) {},
            onAdClicked: (ad) {},
          );
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _status = AdStatus.failed;
          _loadAttempts++;
          if (_loadAttempts < _maxRetries) {
            Future.delayed(
              Duration(seconds: _loadAttempts * 2),
              loadAd,
            );
          }
        },
      ),
    );
  }

  Future<bool> showAd() {
    if (!_isMobilePlatform) return Future.value(true);

    final ad = _rewardedAd;
    if (ad == null) {
      return Future.value(false);
    }

    _showCompleter = Completer<bool>();
    _rewardedAd = null;
    _status = AdStatus.uninitialized;

    ad.show(
      onUserEarnedReward: (ad, reward) {
        if (!_showCompleter!.isCompleted) {
          _showCompleter!.complete(true);
        }
      },
    );

    return _showCompleter!.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        if (!_showCompleter!.isCompleted) {
          _showCompleter!.complete(false);
        }
        return false;
      },
    );
  }

  void _onAdDismissed() {
    if (!_showCompleter!.isCompleted) {
      _showCompleter!.complete(false);
    }
    _showCompleter = null;
    _rewardedAd = null;
    _status = AdStatus.uninitialized;
    loadAd();
  }

  void _onAdFailedToShow(AdError error) {
    if (!_showCompleter!.isCompleted) {
      _showCompleter!.complete(false);
    }
    _showCompleter = null;
    _rewardedAd = null;
    _status = AdStatus.failed;
    Future.delayed(Duration(seconds: _loadAttempts * 2), loadAd);
  }

  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }
}
