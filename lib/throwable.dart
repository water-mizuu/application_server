import "dart:async";

(Object?, T?) throwable<T>(T Function() callback) {
  try {
    var result = callback();

    return (null, result);
  } on Object catch (e) {
    return (e, null);
  }
}

Future<(Object?, T?)> throwableAsync<T>(FutureOr<T> Function() callback) async {
  try {
    var result = await callback();

    return (null, result);
  } on Object catch (e) {
    return (e, null);
  }
}
