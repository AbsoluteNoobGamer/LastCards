import 'dart:async';

import 'package:flutter/foundation.dart';

/// Pure push-to-talk timing: hard max transmit window, must release after auto-stop.
class PttController extends ChangeNotifier {
  PttController({this.maxSeconds = 10});

  final int maxSeconds;

  Timer? _timer;
  bool _transmitting = false;
  int _secondsRemaining = 0;

  /// After auto-stop at [maxSeconds], ignore further starts until [notifyPointerUp].
  bool _awaitingRelease = false;

  bool get isTransmitting => _transmitting;
  int get secondsRemaining => _secondsRemaining;
  bool get awaitingRelease => _awaitingRelease;

  /// Begin transmit. Returns false if already transmitting or awaiting release.
  bool startTransmit() {
    if (_awaitingRelease || _transmitting) return false;
    _transmitting = true;
    _secondsRemaining = maxSeconds;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining <= 1) {
        _autoStop();
        return;
      }
      _secondsRemaining -= 1;
      notifyListeners();
    });
    return true;
  }

  /// User released the PTT control.
  void stopTransmit() {
    _awaitingRelease = false;
    _stopInternal();
  }

  /// Call on pointer-up even when not transmitting (clears awaiting-release).
  void notifyPointerUp() {
    if (_transmitting) {
      stopTransmit();
    } else {
      _awaitingRelease = false;
      notifyListeners();
    }
  }

  void _autoStop() {
    _awaitingRelease = true;
    _stopInternal();
  }

  void _stopInternal() {
    _timer?.cancel();
    _timer = null;
    if (!_transmitting && _secondsRemaining == 0) {
      notifyListeners();
      return;
    }
    _transmitting = false;
    _secondsRemaining = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
