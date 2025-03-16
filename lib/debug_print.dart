import "dart:ui";

import "package:flutter/foundation.dart";

@pragma("vm:prefer-inline")
void printDebug([Object? message]) {
  if (kDebugMode) {
    var token = RootIsolateToken.instance;
    var prefix = switch (token) {
      RootIsolateToken() => "MAIN",
      null => "ISOLATE",
    };

    print("[$prefix] $message");
  }
}
