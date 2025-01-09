import 'dart:io';

import 'package:application_server/future_not_null.dart';
import 'package:application_server/global_state.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' hide showDialog, Colors;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';

class ExampleApplication extends StatelessWidget {
  const ExampleApplication({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Flutter Demo',
      theme: FluentThemeData(
        accentColor: SystemTheme.accentColor.accent.toAccentColor(),
        fontFamily: 'Segoe UI',
      ),
      home: const MyHomePage(),
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
    GlobalState globalState = context.read<GlobalState>();

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ValueListenableBuilder(
              valueListenable: globalState.mode,
              builder: (context, value, child) =>
                  Text('You are currently ${globalState.mode.value}'),
            ),
            ValueListenableBuilder(
              valueListenable: globalState.address,
              builder: (context, value, child) {
                if (value == null) {
                  return const SizedBox();
                }

                var (String ip, int port) = value;
                return Text('Currently hosting at http://$ip:$port');
              },
            ),
            ValueListenableBuilder(
              valueListenable: globalState.parentAddress,
              builder: (context, value, child) {
                if (value == null) {
                  return const SizedBox();
                }

                var (String ip, int port) = value;
                return Text('Currently connected to http://$ip:$port');
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button(
                  onPressed: _childPressed,
                  child: Text("Child"),
                ),
                Button(
                  onPressed: _parentPressed,
                  child: Text("Parent"),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'You have pushed the button this many times:',
                    ),
                    ValueListenableBuilder(
                      valueListenable: globalState.counter,
                      builder: (context, value, child) {
                        return Text(
                          '$value',
                          style: Theme.of(context).textTheme.headlineMedium,
                        );
                      },
                    ),
                    Button(
                      onPressed: () {
                        globalState.counter.value++;
                      },
                      child: const Icon(Icons.add),
                    )
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
    BuildContext context = this.context;
    GlobalState globalState = context.read<GlobalState>();
    globalState.mode.value = DeviceClassification.child;

    NetworkInfo network = NetworkInfo();
    String ip = await network.getWifiIP().notNull();

    if (!context.mounted) {
      return;
    }

    GlobalKey<FormState> formKey = GlobalKey<FormState>();
    TextEditingController ipTextController = TextEditingController()..text = "192.168";
    TextEditingController portTextController = TextEditingController();

    Stream<(String, Object)>? serverStartStream;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            content: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text("IP: "),
                      Expanded(
                        child: TextFormField(
                          autofocus: true,
                          controller: ipTextController,
                          validator: (String? value) {
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
                      Text("Port: "),
                      Expanded(
                        child: TextFormField(
                          controller: portTextController,
                          validator: (String? value) {
                            if (value == null || value.isEmpty) {
                              return "Please enter a port.";
                            }

                            if (int.tryParse(value) case null) {
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
                        child: Text("Cancel"),
                      ),
                      Button(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          String parentIp = ipTextController.text;
                          int parentPort = int.parse(portTextController.text);

                          setState(() {
                            serverStartStream = globalState.hostChild(ip, 0, parentIp, parentPort);
                          });
                        },
                        child: Text("Confirm"),
                      ),
                    ],
                  ),
                  Expanded(child: const SizedBox()),
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
        });
      },
    );
  }

  Future<void> _parentPressed() async {
    BuildContext context = this.context;
    GlobalState globalState = context.read<GlobalState>();
    globalState.mode.value = DeviceClassification.parent;

    NetworkInfo network = NetworkInfo();
    String ip = await network.getWifiIP().notNull();

    if (!context.mounted) {
      return;
    }

    GlobalKey<FormState> formKey = GlobalKey<FormState>();
    TextEditingController ipTextController = TextEditingController()..text = ip;
    TextEditingController portTextController = TextEditingController();

    Stream<(String, Object)>? serverStartStream;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            content: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text("IP: "),
                      Expanded(
                        child: TextFormField(
                          enabled: false,
                          controller: ipTextController,
                          validator: (String? value) {
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
                      Text("Port: "),
                      Expanded(
                        child: TextFormField(
                          autofocus: true,
                          controller: portTextController,
                          validator: (String? value) {
                            if (value == null || value.isEmpty) {
                              return "Please enter a port.";
                            }

                            if (int.tryParse(value) case null) {
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
                        child: Text("Cancel"),
                      ),
                      Button(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          String ip = ipTextController.text;
                          int port = int.parse(portTextController.text);

                          setState(() {
                            serverStartStream = globalState.hostParent(ip, port);
                          });
                        },
                        child: Text("Confirm"),
                      ),
                    ],
                  ),
                  Expanded(child: const SizedBox()),
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
        });
      },
    );
  }
}
