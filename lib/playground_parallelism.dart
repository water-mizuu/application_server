// ignore_for_file: unreachable_from_main

import "dart:async";
import "dart:isolate";

import "package:flutter/foundation.dart";

extension type ListenedReceivePort._(ReceivePort _port) {
  factory ListenedReceivePort(
    ReceivePort receivePort,
    FutureOr<void> Function(Object? message)? fallbackListener,
  ) {
    var instance = ListenedReceivePort._(receivePort);

    _hosts[receivePort] = true;
    _fallbackListeners[receivePort] = fallbackListener;

    /// A helper function that gets the fallback listener for the [receivePort].
    ///   This is useful as the fallback listener can be added at a later time.
    FutureOr<void> Function(Object? message)? getFallbackListener() =>
        _fallbackListeners[receivePort];

    assert(!receivePort.isBroadcast, "The receive port must not be a broadcast stream.");

    receivePort.listen((message) async {
      var completer = _completers[receivePort];

      if (completer case Completer<void> completer) {
        if (completer.isCompleted) {
          if (kDebugMode) {
            print("Received a message $message but the completer is already completed.");
          }
        }

        completer.complete(message);
        return;
      }

      // if (kDebugMode) {
      //   print("Received a message $message but there is no completer to complete it.");

      //   if (getFallbackListener() != null) {
      //     print("The fallback listener will be called instead.");
      //   }
      // }

      if (getFallbackListener() case var fallbackListener?) {
        _completers[receivePort] = null;
        await fallbackListener(message);
        return;
      }
    });

    return instance;
  }

  /// This has the value of true for all ReceivePorts that can be listened to.
  ///   Since the ReceivePort is listened to, it can be used with the [next] extension method.
  ///   However, they cannot be listened to again.
  static Expando<bool> _hosts = Expando();

  static Expando<void Function(Object? message)> _fallbackListeners = Expando();

  static Expando<Completer<void>> _completers = Expando();

  Future<T> next<T>() async {
    assert(
      _hosts[_port] ?? false,
      "The [ReceivePort] must have [hostListener] called "
      "before using the [next] extension method.",
    );
    var completer = Completer<dynamic>();
    _completers[_port] = completer;
    var rawValue = await completer.future as Object?;
    assert(
      rawValue is T,
      "The value received from the [ReceivePort] must be of type $T. "
      "Got ${rawValue.runtimeType} instead",
    );

    var value = rawValue as T;
    _completers[_port] = null;

    return value;
  }

  /// Redirects all the messages received by the [ReceivePort] to the [sendPort].
  void redirectMessagesTo(SendPort sendPort) {
    _fallbackListeners[_port] = (message) {
      sendPort.send(message);
    };
  }

  /// Closes the [ReceivePort] and removes all the listeners.
  void close() {
    _hosts[_port] = false;
    _fallbackListeners[_port] = null;
    _completers[_port] = null;
    _port.close();
  }

  /// A [SendPort] which sends messages to this receive port.
  SendPort get sendPort => _port.sendPort;
}

extension ReceivePortExtension on ReceivePort {
  ListenedReceivePort hostListener([FutureOr<void> Function(Object?)? fallbackListener]) =>
      ListenedReceivePort(this, fallbackListener);
}
