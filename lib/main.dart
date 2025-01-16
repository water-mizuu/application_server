import "dart:async";
import "dart:io";

import "package:application_server/global_state.dart";
import "package:application_server/server_manager.dart";
import "package:application_server/ui.dart";
import "package:bitsdojo_window/bitsdojo_window.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/material.dart";
import "package:macos_window_utils/window_manipulator.dart";
import "package:network_tools/network_tools.dart";
import "package:path_provider/path_provider.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

late final SharedPreferences sharedPreferences;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS) {
    await WindowManipulator.initialize();
  }

  /// Setup for shared preferences.
  sharedPreferences = await SharedPreferences.getInstance();

  /// Setup for network tools

  var appDocDirectory = await getApplicationDocumentsDirectory();
  await configureNetworkTools(appDocDirectory.path);

  /// The only shared state between the main isolate and the server isolate.
  var globalState = GlobalState();
  var serverManager = ServerManager(globalState);
  await serverManager.initialize();

  runApp(
    Provider.value(
      value: globalState,
      child: Provider.value(
        value: serverManager,
        child: const ApplicationWindow(),
      ),
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
