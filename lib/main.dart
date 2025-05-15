import "dart:async";
import "dart:convert" show jsonDecode, jsonEncode;
import "dart:io";

import "package:application_server/backend/server_manager.dart";
import "package:application_server/debug_print.dart";
import "package:application_server/global_state.dart";
import "package:application_server/isolate_dialog.dart";
import "package:application_server/network_tools.dart";
import "package:desktop_multi_window/desktop_multi_window.dart"
    show DesktopMultiWindow, WindowController;
import "package:file_picker/file_picker.dart" show FilePicker;
import "package:fluent_ui/fluent_ui.dart" hide ButtonStyle;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart" show AppBar, ButtonStyle, Icons, MenuStyle, Scaffold, Theme;
import "package:menu_bar/menu_bar.dart" show BarButton, MenuBarWidget, MenuButton, SubMenu;
import "package:provider/provider.dart";
import "package:scroll_animator/scroll_animator.dart"
    show AnimatedScrollController, ChromiumEaseInOut;
import "package:shared_preferences/shared_preferences.dart";
import "package:system_theme/system_theme.dart";

late final SharedPreferences sharedPreferences;

Future<void> main(List<String> args) async {
  if (args case ["multi_window", String windowId, String args]) {
    WidgetsFlutterBinding.ensureInitialized();
    DesktopMultiWindow.setMethodHandler(
      (method, args) async {
        printDebug("[SECONDARY WINDOW] Method: $method");
        printDebug("[SECONDARY WINDOW] Args: $args");
      },
    );

    runApp(
      ExampleSubWindow(
        windowController: WindowController.fromWindowId(int.parse(windowId)),
        args: jsonDecode(args) as Map<String, dynamic>,
      ),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    DesktopMultiWindow.setMethodHandler(
      (method, args) async {
        printDebug("[MAIN WINDOW] Method: $method");
        printDebug("[MAIN WINDOW] Args: $args");
      },
    );

    // /// Setup for shared preferences.
    sharedPreferences = await SharedPreferences.getInstance();

    // /// Setup for network tools
    await initializeNetworkTools();

    /// The only shared state between the main isolate and the server isolate.
    var globalState = GlobalState();
    var isolateDialog = IsolateDialog();
    var serverManager = ServerManager(isolateDialog, globalState);
    await serverManager.initialize();

    runApp(
      MultiProvider(
        providers: [
          Provider.value(value: isolateDialog),
          Provider.value(value: globalState),
          Provider.value(value: serverManager),
        ],
        child: const ApplicationWindow(),
      ),
    );
  }
}

class ApplicationWindow extends StatefulWidget {
  const ApplicationWindow({super.key});

  @override
  State<ApplicationWindow> createState() => _ApplicationWindowState();
}

class _ApplicationWindowState extends State<ApplicationWindow> {
  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      theme: FluentThemeData(
        accentColor: SystemTheme.accentColor.accent.toAccentColor(),
        fontFamily: "Segoe UI",
      ),
      home: NotificationListener<DeviceClassificationChangeNotification>(
        onNotification: (notification) {
          if (kDebugMode) {
            print(notification.mode);
          }
          unawaited(() async {
            var window = await DesktopMultiWindow.createWindow(
              jsonEncode({
                "args1": "Sub window",
                "args2": 100,
                "args3": true,
                "business": "business_test",
              }),
            );
            await window.setFrame(Offset.zero & const Size(480, 270));
            await window.center();
            if (Platform.isMacOS) {
              await window.resizable(false);
            }
            await window.setTitle("Another window");
            await window.show();
          }());
          return true;
        },
        child: _createWindowsMenuBar(context, const MyHomePage() as Widget),
      ),
    );
  }

  MenuBarWidget _createWindowsMenuBar(BuildContext context, Widget child) {
    return MenuBarWidget(
      barStyle: const MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
        fixedSize: WidgetStatePropertyAll(Size(double.infinity, 24.0)),
      ),
      barButtonStyle: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(TextStyle()),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.black.withValues(alpha: 0.05);
          }
          return Colors.white;
        }),
      ),
      menuButtonStyle: const ButtonStyle(
        textStyle: WidgetStatePropertyAll(TextStyle()),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12.0)),
        backgroundColor: WidgetStatePropertyAll(Colors.white),
        minimumSize: WidgetStatePropertyAll(Size.zero),
        iconSize: WidgetStatePropertyAll(16.0),
      ),
      // The buttons in this List are displayed as the buttons on the bar itself
      barButtons: [
        BarButton(
          text: const Text("File"),
          submenu: SubMenu(
            menuItems: [
              MenuButton(
                text: const Text("Open"),
                onTap: () async {
                  if (kDebugMode) {
                    printDebug("Opening a file.");
                  }

                  var result = await FilePicker.platform.pickFiles();
                  if (result == null) {
                    return;
                  }

                  if (kDebugMode) {
                    printDebug(result.names);
                  }
                },
                shortcutText: "Ctrl+O",
              ),
              MenuButton(
                text: const Text("Exit"),
                onTap: () {},
                shortcutText: "Ctrl+Q",
              ),
            ],
          ),
        ),
        BarButton(
          text: const Text("Help"),
          submenu: SubMenu(
            menuItems: [
              MenuButton(
                text: const Text("About"),
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
      child: child,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final AnimatedScrollController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimatedScrollController(animationFactory: const ChromiumEaseInOut());
  }

  @override
  Widget build(BuildContext context) {
    var globalState = context.read<GlobalState>();
    var serverManager = context.read<ServerManager>();

    return Scaffold(
      body: SingleChildScrollView(
        controller: controller,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder(
              valueListenable: serverManager.mode,
              builder: (_, value, __) => Text("You are currently $value"),
            ),
            ValueListenableBuilder(
              valueListenable: serverManager.address,
              builder: (_, value, __) => switch (value) {
                null => const SizedBox(),
                (var ip, var port) => Text("Currently hosting at ws://$ip:$port"),
              },
            ),
            ValueListenableBuilder(
              valueListenable: serverManager.parentAddress,
              builder: (_, value, __) => switch (value) {
                null => const SizedBox(),
                (var ip, var port) => Text("Currently connected to ws://$ip:$port"),
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button(
                  onPressed: () =>
                      const DeviceClassificationChangeNotification(DeviceClassification.child) //
                          .dispatch(context),
                  child: const Text("Child"),
                ),
                Button(
                  onPressed: () =>
                      const DeviceClassificationChangeNotification(DeviceClassification.parent) //
                          .dispatch(context),
                  child: const Text("Parent"),
                ),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: serverManager.mode,
              builder: (_, value, __) => Button(
                onPressed: switch (value) {
                  DeviceClassification.none => null,
                  _ => () =>
                      const DeviceClassificationChangeNotification(DeviceClassification.none) //
                          .dispatch(context),
                },
                child: const Text("Close"),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "You have pushed the button this many times:",
                    ),
                    ValueListenableBuilder(
                      valueListenable: globalState.counter,
                      builder: (_, value, __) => Text(
                        "$value",
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    Button(
                      onPressed: () {
                        globalState.counter.value++;
                      },
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExampleSubWindow extends StatelessWidget {
  const ExampleSubWindow({
    required this.windowController,
    required this.args,
    super.key,
  });

  final WindowController windowController;
  final Map<String, dynamic>? args;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: () {
          if (Platform.isMacOS) {
            return AppBar(
              title: const Text("Plugin example app", style: TextStyle(fontSize: 16.0)),
              toolbarHeight: 28.0,
            );
          }
          return null;
        }(),
        body: Column(
          children: [
            const Expanded(
              child: Row(
                children: [
                  Padding(padding: EdgeInsets.all(16.0), child: Icon(Icons.warning, size: 64.0)),
                  Expanded(
                    child: Text(
                      "This is a sub window. This can be used to prompt the user for input or require a decision.",
                    ),
                  ),
                ],
              ),
            ),
            ColoredBox(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8.0,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        await DesktopMultiWindow.invokeMethod(0, "my_method_test", {
                          "didCancel": false,
                        });
                        await windowController.close();
                      },
                      child: const Text("Invoke method"),
                    ),
                    FilledButton(
                      onPressed: () async {
                        await DesktopMultiWindow.invokeMethod(0, "my_method_test", {
                          "didCancel": true,
                        });
                        await windowController.close();
                      },
                      child: const Text("Close this window"),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
