import 'dart:async';

import 'package:application_server/global_state.dart';
import 'package:application_server/ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

late Future<int?> port;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// The only shared state between the main isolate and the server isolate.
  GlobalState globalState = GlobalState();

  runApp(
    Provider.value(
      value: globalState,
      child: const ExampleApplication(),
    ),
  );
}
