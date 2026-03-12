import 'dart:async';

class GameTurnTimer {
  static const int defaultDurationSeconds = 60;
  
  Timer? _timer;
  final _timeRemainingController = StreamController<int>.broadcast();
  
  int _currentSeconds = defaultDurationSeconds;

  // Returns a multicast-safe stream: each subscriber gets the current value
  // immediately, then receives all subsequent controller emissions.
  // Using Stream.multi avoids creating a new async* generator chain on every
  // access while still delivering the buffered snapshot to late listeners.
  Stream<int> get timeRemainingStream => Stream.multi((controller) {
    controller.add(_currentSeconds);
    final sub = _timeRemainingController.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });
  
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
