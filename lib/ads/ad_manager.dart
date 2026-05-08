import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../audio/audio_manager.dart';

class AdManager {
  static final AdManager instance = AdManager._();
  AdManager._();

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;

  final ValueNotifier<bool> rewardedAdReady = ValueNotifier(false);

  static String get _rewardedAdUnitId => Platform.isIOS
      ? 'ca-app-pub-7289760521218684/2091997829'
      : 'ca-app-pub-3940256099942544/5224354917'; // TODO: replace with Android unit ID

  static String get _interstitialAdUnitId => Platform.isIOS
      ? 'ca-app-pub-7289760521218684/6268642442'
      : 'ca-app-pub-3940256099942544/1033173712'; // TODO: replace with Android unit ID

  Future<void> init() async {
    await MobileAds.instance.initialize();
    _loadRewardedAd();
    _loadInterstitialAd();
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          rewardedAdReady.value = true;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: $error');
          rewardedAdReady.value = false;
        },
      ),
    );
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial ad failed to load: $error');
          _interstitialAd = null;
        },
      ),
    );
  }

  void showRewardedAd({
    required VoidCallback onRewarded,
    VoidCallback? onDismissed,
  }) {
    final ad = _rewardedAd;
    if (ad == null) return;
    _rewardedAd = null;
    rewardedAdReady.value = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => AudioManager.instance.stop(),
      onAdDismissedFullScreenContent: (ad) {
        onDismissed != null
            ? onDismissed()
            : AudioManager.instance.playGame();
        ad.dispose();
        _loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewardedAd();
      },
    );
    ad.show(onUserEarnedReward: (_, __) => onRewarded());
  }

  void showInterstitialAd({VoidCallback? onDismissed}) {
    final ad = _interstitialAd;
    if (ad == null) {
      onDismissed?.call();
      return;
    }
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => AudioManager.instance.stop(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitialAd();
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitialAd();
        onDismissed?.call();
      },
    );
    ad.show();
  }
}
