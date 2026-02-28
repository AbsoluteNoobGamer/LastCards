import 'dart:async';

class GameTurnTimer {
  static const int defaultDurationSeconds = 60;
  
  Timer? _timer;
  final _timeRemainingController = StreamController<int>.broadcast();
  
  int _currentSeconds = defaultDurationSeconds;

  // Return a stream that immediately emits the current value upon listening
  Stream<int> get timeRemainingStream async* {
    yield _currentSeconds;
    yield* _timeRemainingController.stream;
  }
  
  void start(void Function() onExpire) {
    cancel();
    _currentSeconds = defaultDurationSeconds;
    _timeRemainingController.add(_currentSeconds);
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentSeconds > 0) {
        _currentSeconds--;
        _timeRemainingController.add(_currentSeconds);
      } else {
        cancel();
        onExpire();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    cancel();
    _currentSeconds = defaultDurationSeconds;
    _timeRemainingController.add(_currentSeconds);
  }

  void dispose() {
    cancel();
    _timeRemainingController.close();
  }
}
