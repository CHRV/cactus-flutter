import 'dart:async';

/// A mutual-exclusion lock for asynchronous code.
///
/// Ensures that only one [synchronized] operation runs at a time.
/// Subsequent callers wait until the running operation completes.
class AsyncLock {
  Completer<void>? _completer;

  /// Runs [fn] exclusively, waiting for any previously scheduled
  /// operation to finish first.
  ///
  /// [fn]: The asynchronous function to execute under the lock.
  /// Returns: The value returned by [fn].
  Future<T> synchronized<T>(Future<T> Function() fn) async {
    while (_completer != null) {
      await _completer!.future;
    }

    _completer = Completer<void>();

    try {
      return await fn();
    } finally {
      final completer = _completer;
      _completer = null;
      completer?.complete();
    }
  }
}
