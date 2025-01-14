import "dart:async";
import "dart:io";

import "package:application_server/future_not_null.dart";
import "package:application_server/global_state.dart";
import "package:application_server/navigation_bar.dart";
import "package:file_picker/file_picker.dart";
import "package:fluent_ui/fluent_ui.dart" hide ButtonStyle;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart" hide Colors, Divider, NavigationBar, showDialog;
import "package:menu_bar/menu_bar.dart";
import "package:network_info_plus/network_info_plus.dart";
import "package:provider/provider.dart";
import "package:system_theme/system_theme.dart";

class ApplicationWindow extends StatefulWidget {
  const ApplicationWindow({super.key});

  @override
  State<ApplicationWindow> createState() => _ApplicationWindowState();
}

class _ApplicationWindowState extends State<ApplicationWindow> {
  late final AppLifecycleListener _listener;

  bool _exit = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      binding: WidgetsBinding.instance,
      onInactive: () {
        if (kDebugMode) {
          print("On inactive");
        }

        _exit = true;
        Future.delayed(const Duration(milliseconds: 250), () {
          _exit = false;
        });
      },
      onHide: () {
        if (kDebugMode) {
          print("On hide");
        }

        if (_exit) {
          if (kDebugMode) {
            print("We probably exited.");
          }

          _exit = false;
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
    return Provider(
      create: (_) => GlobalState(),
      dispose: (_, state) async => await state.dispose(),
      child: FluentApp(
        debugShowCheckedModeBanner: false,
        theme: FluentThemeData(
          accentColor: SystemTheme.accentColor.accent.toAccentColor(),
          fontFamily: "Segoe UI",
        ),
        home: Column(
          children: [
            const NavigationBar(),
            Expanded(
              child: Builder(
                builder: (context) {
                  var app = const MyHomePage() as Widget;

                  if (Platform.isMacOS) {
                    /// This is the macOS menu bar.
                    app = PlatformMenuBar(
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
                      child: app,
                    );
                  } else if (Platform.isWindows) {
                    /// This is the Windows menu bar.
                    app = MenuBarWidget(
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
                      child: app,
                    );
                  }

                  return app;
                },
              ),
            ),
          ],
        ),
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
                Button(onPressed: _childPressed, child: const Text("Child")),
                Button(onPressed: _parentPressed, child: const Text("Parent")),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: globalState.mode,
              builder: (_, value, __) => Button(
                onPressed: switch (value) {
                  DeviceClassification.unspecified => null,
                  _ => _clearPressed,
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

  Future<void> _childPressed() async {
    var context = this.context;
    var globalState = context.read<GlobalState>();

    var network = NetworkInfo();
    var ip = await network.getWifiIP().notNull();

    if (!context.mounted) {
      return;
    }

    var formKey = GlobalKey<FormState>();
    var ipTextController = TextEditingController()..text = "192.168";
    var portTextController = TextEditingController();

    Stream<(String, Object)>? serverStartStream;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              content: Form(
                key: formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text("IP: "),
                        Expanded(
                          child: TextFormField(
                            autofocus: true,
                            controller: ipTextController,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Please enter an IP address.";
                              }

                              if (value == ip) {
                                return "You cannot connect to yourself.";
                              }

                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text("Port: "),
                        Expanded(
                          child: TextFormField(
                            controller: portTextController,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Please enter a port.";
                              }

                              if (int.tryParse(value) case int v) {
                                if (v == 0) {
                                  return "Please enter a non-zero port.";
                                }
                              } else {
                                return "Please enter a valid port.";
                              }

                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Button(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text("Cancel"),
                        ),
                        Button(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) {
                              return;
                            }

                            var parentIp = ipTextController.text;
                            var parentPort = int.parse(portTextController.text);

                            setState(() {
                              serverStartStream = globalState
                                  .hostChild(ip, 0, parentIp, parentPort)
                                  .asBroadcastStream();
                            });

                            if (await serverStartStream?.drain<void>() case _?) {
                              globalState.mode.value = DeviceClassification.child;
                            }
                          },
                          child: const Text("Confirm"),
                        ),
                      ],
                    ),
                    const Expanded(child: SizedBox()),
                    if (serverStartStream case Stream<(String, Object)> serverStartStream)
                      StreamBuilder(
                        stream: serverStartStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text("Error: ${snapshot.error}");
                          }

                          if (snapshot.hasData) {
                            switch (snapshot.data) {
                              case ("message", String message):
                                return Text("Message: $message");

                              /// Error Code 13: Permission denied.
                              case ("exception", SocketException(osError: OSError(errorCode: 13))):
                                return Text(
                                  "Permission denied. Either the port is already in use"
                                  " or you don't have permission to use it.",
                                  style: TextStyle(color: Colors.red),
                                );
                              case ("timeout_exception", TimeoutException()):
                                return Text(
                                  "Connection timed out. This means that something went wrong while trying to connect to the parent device. Please check the IP address and the port.",
                                  style: TextStyle(color: Colors.red),
                                );
                              case ("exception", SocketException(:var message)):
                                return Text(
                                  "Something went wrong. $message",
                                  style: TextStyle(color: Colors.red),
                                );
                              case ("done", _):
                                Navigator.of(context).pop();

                                return const SizedBox();
                            }
                          }
                          return const CircularProgressIndicator();
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _parentPressed() async {
    var context = this.context;
    var globalState = context.read<GlobalState>();
    globalState.mode.value = DeviceClassification.parent;

    var network = NetworkInfo();
    var ip = await network.getWifiIP().notNull();

    if (!context.mounted) {
      return;
    }

    var formKey = GlobalKey<FormState>();
    var ipTextController = TextEditingController()..text = ip;
    var portTextController = TextEditingController();

    Stream<(String, Object)>? serverStartStream;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              content: Form(
                key: formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text("IP: "),
                        Expanded(
                          child: TextFormField(
                            enabled: false,
                            controller: ipTextController,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Please enter an IP address.";
                              }

                              if (value != ip) {
                                return "You cannot host to other but yourself.";
                              }

                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text("Port: "),
                        Expanded(
                          child: TextFormField(
                            autofocus: true,
                            controller: portTextController,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Please enter a port.";
                              }

                              if (int.tryParse(value) case int v) {
                                if (v == 0) {
                                  return "Please enter a non-zero port.";
                                }
                              } else {
                                return "Please enter a valid port.";
                              }

                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Button(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text("Cancel"),
                        ),
                        Button(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) {
                              return;
                            }

                            var ip = ipTextController.text;
                            var port = int.parse(portTextController.text);

                            setState(() {
                              serverStartStream = globalState //
                                  .hostParent(ip, port)
                                  .asBroadcastStream();
                            });
                            if (await serverStartStream?.drain<void>() case _?) {
                              globalState.mode.value = DeviceClassification.child;
                            }
                          },
                          child: const Text("Confirm"),
                        ),
                      ],
                    ),
                    const Expanded(child: SizedBox()),
                    if (serverStartStream case Stream<(String, Object)> serverStartStream)
                      StreamBuilder(
                        stream: serverStartStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text("Error: ${snapshot.error}");
                          }

                          if (snapshot.hasData) {
                            switch (snapshot.data) {
                              case ("message", String message):
                                return Text("Message: $message");

                              /// Error Code 13: Permission denied.
                              case ("exception", SocketException(osError: OSError(errorCode: 13))):
                                return Text(
                                  "Permission denied. Either the port is already in use"
                                  " or you don't have permission to use it.",
                                  style: TextStyle(color: Colors.red),
                                );
                              case ("timeout_exception", TimeoutException(:var message)):
                                if (message case String message) {
                                  return Text(
                                    "Timeout: $message",
                                    style: TextStyle(color: Colors.red),
                                  );
                                } else {
                                  return Text("Timeout", style: TextStyle(color: Colors.red));
                                }
                              case ("done", _):
                                Navigator.of(context).pop();
                                return const SizedBox();
                            }
                          }

                          return const CircularProgressIndicator();
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _clearPressed() async {
    var globalState = context.read<GlobalState>();

    await globalState.closeServer();

    globalState.mode.value = DeviceClassification.unspecified;
    globalState.counter.value = 0;
  }
}
