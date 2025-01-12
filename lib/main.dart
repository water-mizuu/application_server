import "dart:async";
import "dart:io";

import "package:application_server/ui.dart";
import "package:bitsdojo_window/bitsdojo_window.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/material.dart";
import "package:macos_window_utils/window_manipulator.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS) {
    await WindowManipulator.initialize();
    // await WindowManipulator.hideTitle();
  }

  /// The only shared state between the main isolate and the server isolate.
  runApp(const ApplicationWindow());

  doWhenWindowReady(() {
    const initialSize = Size(600, 450);
    appWindow.minSize = initialSize;
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = "Application Server";
    appWindow.show();
  });
}
