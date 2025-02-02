import "dart:async";
import "dart:io";

import "package:application_server/backend/shelf.dart";
import "package:application_server/global_state.dart";
import "package:application_server/main.dart";
import "package:application_server/network_tools.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart" hide Colors, Divider, NavigationBar, showDialog;
import "package:time/time.dart";

enum DeviceClassification {
  parent,
  child,
  none,
}

typedef Address = (String, int);
typedef DeferredHostInfo = (Future<String>, String);

class ServerNotification extends Notification {
  const ServerNotification(this.mode);

  final DeviceClassification mode;
}

/// The server manager is responsible for creating, hosting, and closing the server.
class ServerManager {
  ServerManager(this.globalState);

  final GlobalState globalState;

  /// The mode of the device. It should be either parent or child, or unspecified at the start.
  /// In the future, this will be assigned only at first,
  ///   then it will be read from shared preferences.
  final ValueNotifier<DeviceClassification> mode = ValueNotifier(DeviceClassification.none);

  // Relevant attributes for the parent device.
  late final ValueNotifier<Address?> address = ValueNotifier(null);

  /// The address of the parent device.
  late final ValueNotifier<Address?> parentAddress = ValueNotifier(null);

  late final ValueNotifier<bool> isServerRunning = ValueNotifier(false);

  /// Indicate that the attempt to start the server based on the previous session failed.
  late final bool shouldPromptServerStartOnBoot;

  Future<void> initialize() async {
    /// Read the mode from shared preferences.
    /// If it is stored:
    ///    - Host the server again.
    ///    - Set the mode to the stored value.
    /// If it is not stored:
    ///    - Set the mode to unspecified.
    if (sharedPreferences.getInt("mode") case var storedMode?) {
      mode.value = DeviceClassification.values[storedMode];

      switch (mode.value) {
        case DeviceClassification.parent:
          var ip = sharedPreferences.getString("ip")!;
          var port = sharedPreferences.getInt("port")!;

          var encounteredError = true;
          if (ip != deviceIp) {
            encounteredError = true;
          } else {
            await for (var (type, _) in hostParent((ip, port))) {
              if (type == "done") {
                encounteredError = false;
              }
            }
          }

          shouldPromptServerStartOnBoot = encounteredError;
        case DeviceClassification.child:
          var parentIp = sharedPreferences.getString("parent_ip")!;
          var parentPort = sharedPreferences.getInt("parent_port")!;

          var encounteredError = true;
          await for (var (type, _) in hostChild((parentIp, parentPort))) {
            if (type == "done") {
              encounteredError = false;
            }
          }

          if (kDebugMode) {
            print("Encountered error: $encounteredError");
          }

          shouldPromptServerStartOnBoot = encounteredError;
        case DeviceClassification.none:
          shouldPromptServerStartOnBoot = false;
      }
    } else {
      mode.value = DeviceClassification.none;
      shouldPromptServerStartOnBoot = false;
    }
  }

  Stream<(String, Object)> _hostParent(Address local) async* {
    var (ip, port) = local;
    address.value = null;
    parentAddress.value = null;

    var completedWithError = true;
    try {
      switch (_currentServer) {
        case ChildConnection server:
          yield ("message", "Closing the existing server at ws://${server.ip}:${server.port}");
          await server.stopServer();
          yield ("message", "Closed the server.");
        case ShelfChildServer server:
          await server.stopServer();
        case null:
          break;
      }

      _currentServer = ChildConnection(globalState, ip, port);
      await _currentServer!.startServer();
      yield ("message", "Started server at http://$ip:$port");
      yield ("done", "Server started");
      address.value = (ip, port);
      parentAddress.value = null;
      mode.value = DeviceClassification.parent;
      await (
        sharedPreferences.setInt("mode", DeviceClassification.parent.index),
        sharedPreferences.setString("ip", ip),
        sharedPreferences.setInt("port", port),
        sharedPreferences.remove("parent_ip"),
        sharedPreferences.remove("parent_port"),
      ).wait;
      completedWithError = false;
    } on SocketException catch (e) {
      yield ("exception", e);
    } on Object catch (e) {
      yield ("error", (e.runtimeType, e));
    } finally {
      if (completedWithError) {
        address.value = null;
        parentAddress.value = null;
        mode.value = DeviceClassification.none;
        await stopServer();
        await (
          sharedPreferences.remove("mode"),
          sharedPreferences.remove("ip"),
          sharedPreferences.remove("port"),
          sharedPreferences.remove("parent_ip"),
          sharedPreferences.remove("parent_port"),
        ).wait;
      }
    }
  }

  Stream<(String, Object)> hostParent(Address local) async* {
    await for (var (type, message) in _hostParent(local)) {
      if (kDebugMode) {
        print("[MAIN\$$type] $message");
      }
      yield (type, message);
    }
  }

  Stream<(String, Object)> _hostChild(Address parent) async* {
    var (parentIp, parentPort) = parent;

    address.value = null;
    parentAddress.value = null;

    var completedWithError = true;
    try {
      switch (_currentServer) {
        case ChildConnection server:
          yield ("message", "Closing the existing server at ws://${server.ip}:${server.port}");
          await server.stopServer();
          yield ("message", "Closed the server.");
        case ShelfChildServer server:
          await server.stopServer();
        case null:
          break;
      }

      _currentServer = ShelfChildServer(globalState, parentIp, parentPort);
      await _currentServer!.startServer();

      address.value = null;
      parentAddress.value = (parentIp, parentPort);
      mode.value = DeviceClassification.child;
      await (
        sharedPreferences.setInt("mode", DeviceClassification.child.index),
        sharedPreferences.setString("parent_ip", parentIp),
        sharedPreferences.setInt("parent_port", parentPort),
      ).wait;
      completedWithError = false;
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        print("The connection timed out. ${e.message}");
      }

      yield ("timeout_exception", e);
    } on SocketException catch (e) {
      yield ("exception", e);
    } on ArgumentError catch (e) {
      yield ("argument_error", e);
    } on Object catch (e) {
      yield ("error", (e.runtimeType, e));
    } finally {
      /// If we had an error, we need to make sure that there is no server lingering.
      if (completedWithError) {
        address.value = null;
        parentAddress.value = null;
        mode.value = DeviceClassification.none;
        await (
          sharedPreferences.remove("mode"),
          sharedPreferences.remove("ip"),
          sharedPreferences.remove("port"),
          sharedPreferences.remove("parent_ip"),
          sharedPreferences.remove("parent_port"),
        ).wait;
        await stopServer();
      }
    }
  }

  Stream<(String, Object)> hostChild(Address parent) async* {
    await for (var (type, message) in _hostChild(parent)) {
      if (kDebugMode) {
        print("[MAIN\$$type] $message");
      }
      yield (type, message);
    }
  }

  Future<void> parentPressed(BuildContext context) async {
    var formKey = GlobalKey<FormState>();
    var ipTextController = TextEditingController()..text = deviceIp;
    var portTextController = TextEditingController();
    if (parentAddress.value case (_, var port)) {
      portTextController.text = port.toString();
    }

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

                              if (value != deviceIp) {
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
                          onPressed: () async {
                            await cancelPressed();
                            if (!context.mounted) {
                              return;
                            }

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
                              serverStartStream = hostParent((ip, port));
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

  Future<void> childPressed(BuildContext context) async {
    // We delay if for a few milliseconds as to not block the UI thread.
    var ips = scanIps().timeout(5.seconds);

    var formKey = GlobalKey<FormState>();
    var ipTextController = TextEditingController();
    var portTextController = TextEditingController();

    Stream<(String, Object)>? serverStartStream;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.transparent,
              content: AnimatedContainer(
                duration: 200.milliseconds,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 250, 242).withAlpha(180),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: formKey,
                    child: Column(
                      children: [
                        const Text("Connect to a parent device:"),
                        const Text("Please refer to its IP address and port, "
                            "found in Info > Server Information."),
                        Row(
                          children: [
                            const Stack(
                              children: [
                                Text("IP: "),
                                IgnorePointer(
                                  child: Opacity(
                                    opacity: 0.0,
                                    child: Text("Port: "),
                                  ),
                                ),
                              ],
                            ),
                            Expanded(
                              child: FutureBuilder(
                                future: ips,
                                builder: (context, snapshot) {
                                  switch (snapshot) {
                                    case AsyncSnapshot(connectionState: ConnectionState.none):
                                    case AsyncSnapshot(connectionState: ConnectionState.waiting):
                                    case AsyncSnapshot(connectionState: ConnectionState.active):
                                    case AsyncSnapshot(connectionState: ConnectionState.done):
                                      if (snapshot.hasError) {
                                        return TextFormField(
                                          controller: ipTextController,
                                          validator: (ip) {
                                            if (ip == null || ip.isEmpty) {
                                              return "Please select an IP address.";
                                            }

                                            if (ip == deviceIp) {
                                              return "You cannot connect to yourself.";
                                            }

                                            return null;
                                          },
                                        );
                                      }
                                      if (!snapshot.hasData) {
                                        return const SizedBox();
                                      }
                                      var arps = snapshot.data!;

                                      return DropdownButtonFormField(
                                        hint: const Text("Select a device"),
                                        validator: (ip) {
                                          if (ip == null || ip.isEmpty) {
                                            return "Please select an IP address.";
                                          }

                                          if (ip == deviceIp) {
                                            return "You cannot connect to yourself.";
                                          }

                                          return null;
                                        },
                                        items: [
                                          for (var (name, ip) in arps)
                                            DropdownMenuItem(
                                              value: ip,
                                              child: Row(
                                                children: [
                                                  FutureBuilder(
                                                    future: name,
                                                    builder: (context, snapshot) {
                                                      if (snapshot.data case String data) {
                                                        return Text(data);
                                                      }

                                                      return const CircularProgressIndicator();
                                                    },
                                                  ),
                                                  Text(" ($ip)"),
                                                ],
                                              ),
                                            ),
                                        ],
                                        onChanged: (newValue) {
                                          if (newValue case var _?) {
                                            ipTextController.text = newValue;
                                          }
                                        },
                                      );
                                    // This is a Dart bug.
                                    // ignore: unreachable_switch_case
                                    case _:
                                      throw UnimplementedError();
                                  }
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
                        const SizedBox(height: 18.0),
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
                                  serverStartStream = hostChild(
                                    (parentIp, parentPort),
                                  );
                                });
                              },
                              child: const Text("Confirm"),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: serverStartStream == null
                                ? const SizedBox()
                                : const CircularProgressIndicator(),
                          ),
                        ),
                        if (serverStartStream case var serverStartStream?)
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
                                  case (
                                      "exception",
                                      SocketException(osError: OSError(errorCode: 13))
                                    ):
                                    return Text(
                                      "Permission denied. Either the port is already in use"
                                      " or you don't have permission to use it. Try another port.",
                                      style: TextStyle(color: Colors.red),
                                    );
                                  case ("timeout_exception", TimeoutException()):
                                    return Text(
                                      "Connection timed out. Please check the IP address and the port.",
                                      style: TextStyle(color: Colors.red),
                                    );
                                  case ("argument_error", ArgumentError(:var message)):
                                    return Text(
                                      "$message",
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> cancelPressed() async {
    /// Close the existing server (if there is one.)
    await stopServer();

    /// Update the saved addresses and mode.
    address.value = null;
    parentAddress.value = null;
    mode.value = DeviceClassification.none;

    /// Update shared preferences
    await (
      sharedPreferences.setInt("mode", DeviceClassification.none.index),
      sharedPreferences.remove("ip"),
      sharedPreferences.remove("port"),
      sharedPreferences.remove("parent_ip"),
      sharedPreferences.remove("parent_port"),
    ).wait;

    ///   set the state.
    globalState.counter.value = 0;
  }

  Future<void> stopServer() async {
    switch (_currentServer) {
      case ChildConnection server:
        await server.stopServer();
      case ShelfChildServer server:
        await server.stopServer();
      case null:
        break;
    }

    isServerRunning.value = false;
    await _currentServer?.stopServer();
  }

  Future<void> cleanLingering() async {
    address.value = null;
    parentAddress.value = null;
    mode.value = DeviceClassification.none;
    await (
      sharedPreferences.remove("mode"),
      sharedPreferences.remove("ip"),
      sharedPreferences.remove("port"),
      sharedPreferences.remove("parent_ip"),
      sharedPreferences.remove("parent_port"),
    ).wait;

    await stopServer();
  }

  Future<void> dispose() async {
    await stopServer();
  }

  ShelfServer? _currentServer;
}
