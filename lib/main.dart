import "dart:async";

import "package:application_server/global_state.dart";
import "package:application_server/ui.dart";
import "package:bitsdojo_window/bitsdojo_window.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// The only shared state between the main isolate and the server isolate.
  runApp(
    Provider(
      create: (_) => GlobalState(),
      dispose: (_, state) => state.dispose(),
      child: const ExampleApplication(),
    ),
  );

  doWhenWindowReady(() {
    const initialSize = Size(600, 450);
    appWindow.minSize = initialSize;
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = "Application Server";
    appWindow.show();
  });
}
