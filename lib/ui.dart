import "dart:async";
import "dart:io";

import "package:application_server/global_state.dart";
import "package:application_server/navigation_bar.dart";
import "package:file_picker/file_picker.dart";
import "package:fluent_ui/fluent_ui.dart" hide ButtonStyle;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart" hide Colors, Divider, NavigationBar, showDialog;
import "package:menu_bar/menu_bar.dart";
import "package:provider/provider.dart";
import "package:system_theme/system_theme.dart";

class ApplicationWindow extends StatefulWidget {
  const ApplicationWindow({super.key});

  @override
  State<ApplicationWindow> createState() => _ApplicationWindowState();
}

class _ApplicationWindowState extends State<ApplicationWindow> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();

    var exit = false;
    _listener = AppLifecycleListener(
      binding: WidgetsBinding.instance,
      onInactive: () {
        exit = true;
        Future.delayed(const Duration(milliseconds: 250), () {
          exit = false;
        });
      },
      onHide: () {
        if (exit) {
          if (kDebugMode) {
            print("We probably exited.");
          }

          exit = false;
        }
      },
      onStateChange: (value) {
        if (kDebugMode) {
          print("The state changed to $value");
        }
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      theme: FluentThemeData(
        accentColor: SystemTheme.accentColor.accent.toAccentColor(),
        fontFamily: "Segoe UI",
      ),
      home: Builder(
        builder: (context) {
          return NotificationListener<ServerNotification>(
            onNotification: (notification) {
              var globalState = context.read<GlobalState>();
          
              unawaited(() async {
                switch (notification.mode) {
                  case DeviceClassification.parent:
                    await globalState.parentPressed(context);
                  case DeviceClassification.child:
                    await globalState.childPressed(context);
                  case DeviceClassification.none:
                    await globalState.cancelPressed();
                }
              }());
          
              return true;
            },
            child: Column(
              children: [
                const NavigationBar(),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      var widget = const MyHomePage() as Widget;
          
                      if (Platform.isMacOS) {
                        /// This is the macOS menu bar.
                        widget = PlatformMenuBar(
                          menus: [
                            PlatformMenu(
                              label: "The first menu.",
                              menus: [
                                /// Apparently, if the first menu is empty,
                                ///   the application name is not displayed.
                                PlatformMenuItem(
                                  label: "About",
                                  onSelected: () {},
                                ),
                              ],
                            ),
                            PlatformMenu(
                              label: "File",
                              menus: [
                                PlatformMenuItemGroup(
                                  members: <PlatformMenuItem>[
                                    PlatformMenuItem(
                                      label: "Open",
                                      onSelected: () async {
                                        if (kDebugMode) {
                                          print("Opening a file.");
                                        }
          
                                        var result = await FilePicker.platform.pickFiles();
                                        if (result == null) {
                                          return;
                                        }
          
                                        if (kDebugMode) {
                                          print(result.names);
                                        }
                                      },
                                    ),
                                    PlatformMenuItem(
                                      label: "Exit",
                                      onSelected: () {
                                        if (kDebugMode) {
                                          print("Hi");
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                          child: widget,
                        );
                      } else if (Platform.isWindows) {
                        /// This is the Windows menu bar.
                        widget = MenuBarWidget(
                          barStyle: const MenuStyle(
                            padding: WidgetStatePropertyAll(EdgeInsets.zero),
                            backgroundColor: WidgetStatePropertyAll(Colors.white),
                            shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
                          ),
                          barButtonStyle: ButtonStyle(
                            textStyle: const WidgetStatePropertyAll(TextStyle()),
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.hovered)) {
                                return Colors.black.withValues(alpha: 0.05);
                              }
                              return Colors.white;
                            }),
                            minimumSize: const WidgetStatePropertyAll(Size.zero),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                                        print("Opening a file.");
                                      }
          
                                      var result = await FilePicker.platform.pickFiles();
                                      if (result == null) {
                                        return;
                                      }
          
                                      if (kDebugMode) {
                                        print(result.names);
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
                          child: widget,
                        );
                      }
          
                      return widget;
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var globalState = context.read<GlobalState>();

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder(
              valueListenable: globalState.mode,
              builder: (_, value, __) => Text("You are currently $value"),
            ),
            ValueListenableBuilder(
              valueListenable: globalState.address,
              builder: (_, value, __) => switch (value) {
                null => const SizedBox(),
                (var ip, var port) => Text("Currently hosting at http://$ip:$port"),
              },
            ),
            ValueListenableBuilder(
              valueListenable: globalState.parentAddress,
              builder: (_, value, __) => switch (value) {
                null => const SizedBox(),
                (var ip, var port) => Text("Currently connected to http://$ip:$port"),
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button(
                  onPressed: () => const ServerNotification(DeviceClassification.child) //
                      .dispatch(context),
                  child: const Text("Child"),
                ),
                Button(
                  onPressed: () => const ServerNotification(DeviceClassification.parent) //
                      .dispatch(context),
                  child: const Text("Parent"),
                ),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: globalState.mode,
              builder: (_, value, __) => Button(
                onPressed: switch (value) {
                  DeviceClassification.none => null,
                  _ => () => const ServerNotification(DeviceClassification.none) //
                      .dispatch(context),
                },
                child: const Text("Close"),
              ),
            ),
            Expanded(
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
