import "dart:async";

import "package:application_server/backend/server_manager.dart";
import "package:application_server/global_state.dart";
import "package:application_server/network_tools.dart";
import "package:application_server/ui.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

late final SharedPreferences sharedPreferences;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Setup for shared preferences.
  sharedPreferences = await SharedPreferences.getInstance();

  // /// Setup for network tools
  // TODO: Create a fallback for when network tools takes too long.
  //  - Preferrably manual input.
  await initializeNetworkTools();

  /// The only shared state between the main isolate and the server isolate.
  var globalState = GlobalState();
  var serverManager = ServerManager(globalState);
  await serverManager.initialize();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: globalState),
        Provider.value(value: serverManager),
      ],
      child: const ApplicationWindow(),
    ),
  );
}
