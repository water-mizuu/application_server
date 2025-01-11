import "dart:io";

import "package:application_server/future_not_null.dart";
import "package:application_server/global_state.dart";
import "package:bitsdojo_window/bitsdojo_window.dart";
import "package:file_picker/file_picker.dart";
import "package:fluent_ui/fluent_ui.dart" hide ButtonStyle;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart" hide Colors, Divider, showDialog;
import "package:material_symbols_icons/symbols.dart";
import "package:menu_bar/menu_bar.dart";
import "package:network_info_plus/network_info_plus.dart";
import "package:provider/provider.dart";
import "package:system_theme/system_theme.dart";

class ExampleApplication extends StatelessWidget {
  const ExampleApplication({super.key});

  @override
  Widget build(BuildContext context) {
    (_) = TextButton.styleFrom();

    return FluentApp(
      title: "Flutter Demo",
      debugShowCheckedModeBanner: false,
      theme: FluentThemeData(
        accentColor: SystemTheme.accentColor.accent.toAccentColor(),
        fontFamily: "Segoe UI",
      ),
      home: Column(
        children: [
          const NavigationBar(),
          Expanded(
            child: MenuBarWidget(
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
              child: const MyHomePage(),
            ),
          ),
        ],
      ),
    );
  }
}

class NavigationBar extends StatelessWidget {
  const NavigationBar({super.key});

  static final buttonColors = WindowButtonColors(
    iconNormal: const Color(0xFF000000),
    mouseOver: const Color(0x22000000),
    mouseDown: const Color(0x33000000),
    iconMouseOver: const Color(0xAA000000),
    iconMouseDown: const Color(0xBB000000),
  );

  static final closeButtonColors = WindowButtonColors(
    mouseOver: const Color(0xFFD32F2F),
    mouseDown: const Color(0xFFB71C1C),
    iconNormal: const Color(0xFF000000),
    iconMouseOver: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        appWindow.startDragging();
      },
      child: WindowTitleBarBox(
        child: ColoredBox(
          color: Colors.white,
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(Symbols.flutter),
              ),
              const Text(
                "Application Server",
                style: TextStyle(
                  fontFamily: "Segoe UI",
                  fontSize: 12.0,
                ),
              ),
              const Expanded(child: SizedBox()),
              MinimizeWindowButton(colors: buttonColors, animate: true),
              MaximizeOrRestoreButton(colors: buttonColors, animate: true),
              CloseWindowButton(
                colors: closeButtonColors,
                animate: true,
                onPressed: () async {
                  if (kDebugMode) {
                    print("Closing the window.");
                  }

                  await context.read<GlobalState>().closeServer();
                  appWindow.close();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MaximizeOrRestoreButton extends StatelessWidget {
  const MaximizeOrRestoreButton({
    required this.colors,
    this.onPressed,
    this.animate = false,
    super.key,
  });

  final WindowButtonColors colors;
  final VoidCallback? onPressed;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    MediaQuery.sizeOf(context);

    return WindowButton(
      colors: colors,
      iconBuilder: (context) {
        return appWindow.isMaximized
            ? RestoreIcon(color: colors.iconNormal)
            : MaximizeIcon(color: colors.iconNormal);
      },
      onPressed: onPressed ?? () => appWindow.maximizeOrRestore(),
      animate: animate,
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
              builder: (context, value, child) =>
                  Text("You are currently ${globalState.mode.value}"),
            ),
            ValueListenableBuilder(
              valueListenable: globalState.address,
              builder: (context, value, child) {
                if (value == null) {
                  return const SizedBox();
                }

                var (ip, port) = value;
                return Text("Currently hosting at http://$ip:$port");
              },
            ),
            ValueListenableBuilder(
              valueListenable: globalState.parentAddress,
              builder: (context, value, child) {
                if (value == null) {
                  return const SizedBox();
                }

                var (String ip, int port) = value;
                return Text("Currently connected to http://$ip:$port");
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button(
                  onPressed: _childPressed,
                  child: const Text("Child"),
                ),
                Button(
                  onPressed: _parentPressed,
                  child: const Text("Parent"),
                ),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: globalState.mode,
              builder: (context, value, _) => Button(
                onPressed: value == DeviceClassification.unspecified //
                    ? null
                    : globalState.closeServer,
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
                      builder: (context, value, child) {
                        return Text(
                          "$value",
                          style: Theme.of(context).textTheme.headlineMedium,
                        );
                      },
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
    globalState.mode.value = DeviceClassification.child;

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
                              serverStartStream =
                                  globalState.hostChild(ip, 0, parentIp, parentPort);
                            });
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
                              serverStartStream = globalState.hostParent(ip, port);
                            });
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
}
