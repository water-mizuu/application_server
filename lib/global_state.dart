// ignore_for_file: parameter_assignments

import "dart:async";
import "dart:io";

import "package:application_server/shelf.dart";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";
import "package:time/time.dart";

enum DeviceClassification {
  parent,
  child,
  unspecified,
}

typedef Address = (String, int);

class GlobalState {
  factory GlobalState() => _instance;
  GlobalState._internal();
  static final GlobalState _instance = GlobalState._internal();

  late final SharedPreferences sharedPreferences;

  /// An example value that can be shared between the main isolate and the server isolate.
  final ValueNotifier<int> counter = ValueNotifier<int>(0);

  /// The mode of the device. It should be either parent or child, or unspecified at the start.
  /// In the future, this will be assigned only at first,
  ///   then it will be read from shared preferences.
  final ValueNotifier<DeviceClassification> mode = ValueNotifier(DeviceClassification.unspecified);

  // Relevant attributes for the parent device.
  late final ValueNotifier<Address?> address = ValueNotifier(null);

  /// The address of the parent device.
  late final ValueNotifier<Address?> parentAddress = ValueNotifier(null);

  late final ValueNotifier<bool> isServerRunning = ValueNotifier(false);

  Future<void> initialize() async {
    sharedPreferences = await SharedPreferences.getInstance();

    /// Read the mode from shared preferences.
    /// If it is stored:
    ///    - Host the server again.
    ///    - Set the mode to the stored value.
    /// If it is not stored:
    ///    - Set the mode to unspecified.
    if (sharedPreferences.getInt("mode") case int storedMode) {
      mode.value = DeviceClassification.values[storedMode];

      switch (mode.value) {
        case DeviceClassification.parent:
          if ((
            sharedPreferences.getString("ip"),
            sharedPreferences.getInt("port"),
          )
              case (var ip?, var port?)) {
            await hostParent(ip, port).drain<void>();
          }
        case DeviceClassification.child:
          // if ((
          //   sharedPreferences.getString("ip"),
          //   sharedPreferences.getInt("port"),
          //   sharedPreferences.getString("parent_ip"),
          //   sharedPreferences.getInt("parent_port"),
          // )
          //     case (var ip?, var port?, var parentIp?, var parentPort?)) {
          //   await hostChild(ip, port, parentIp, parentPort).drain<void>();
          // }
        case DeviceClassification.unspecified:
          break;
      }
    } else {
      mode.value = DeviceClassification.unspecified;
    }
  }

  Stream<(String, Object)> _hostParent(String ip, int port) async* {
    address.value = null;
    parentAddress.value = null;

    try {
      if (_currentServer case ShelfServer server when server.isStarted) {
        yield ("message", "Closing the existing server at http://${server.ip}:${server.port}");
        await server.stopServer();
        yield ("message", "Closed the server.");
      }

      await (
        sharedPreferences.setInt("mode", DeviceClassification.parent.index),
        sharedPreferences.setString("ip", ip),
        sharedPreferences.setInt("port", port),
        sharedPreferences.remove("parent_ip"),
        sharedPreferences.remove("parent_port"),
      ).wait;

      yield ("message", "Starting server at http://$ip:$port");
      _currentServer = ShelfParentServer(this, ip, port);
      await _currentServer!.startServer();
      yield ("message", "Started server at http://$ip:$port");
      yield ("done", "Server started");
      address.value = (ip, port);
      parentAddress.value = null;
    } on SocketException catch (e) {
      yield ("exception", e);
    } on Object catch (e) {
      yield ("error", e);
    }
  }

  Stream<(String, Object)> hostParent(String ip, int port) async* {
    await for (var (type, message) in _hostParent(ip, port)) {
      if (kDebugMode) {
        print("[MAIN\$$type] $message");
      }
      yield (type, message);
    }
  }

  Stream<(String, Object)> _hostChild(String ip, int port, String parentIp, int parentPort) async* {
    address.value = null;
    parentAddress.value = null;

    try {
      if (_currentServer case ShelfServer server when server.isStarted) {
        yield ("message", "Closing the existing server at http://${server.ip}:${server.port}");
        await server.stopServer();
        yield ("message", "Closed the server.");
      }

      await (
        sharedPreferences.setInt("mode", DeviceClassification.child.index),
        sharedPreferences.setString("ip", ip),
        sharedPreferences.setInt("port", port),
        sharedPreferences.setString("parent_ip", parentIp),
        sharedPreferences.setInt("parent_port", parentPort),
      ).wait;

      yield ("message", "Starting server at http://$ip:$port");
      _currentServer = ShelfChildServer(this, ip, parentIp, parentPort);
      await _currentServer!.startServer();
      port = _currentServer!.port;
      yield ("message", "Started server at http://$ip:$port");

      if (kDebugMode) {
        print("Server started at http://$ip:$port");
        print("Handshaking with the parent device at http://$parentIp:$parentPort");
      }
      yield ("message", "Handshaking with the parent device at http://$parentIp:$parentPort");
      var uri = Uri.parse("http://$parentIp:$parentPort/register_child_device/$ip/$port");
      var response = await http.post(uri).timeout(1.seconds);
      if (response.statusCode != 200) {
        throw Exception("Failed to handshake with the parent device.");
      }

      /// Synchronize the data with the parent device.

      yield ("message", "Handshaked with the parent device at http://$parentIp:$parentPort");
      yield ("done", "Connection established");

      address.value = (ip, port);
      parentAddress.value = (parentIp, parentPort);
    } on TimeoutException catch (e) {
      yield ("timeout_exception", e);
    } on SocketException catch (e) {
      yield ("exception", e);
    } on Object catch (e) {
      yield ("error", e);
    }
  }

  Stream<(String, Object)> hostChild(String ip, int port, String parentIp, int parentPort) async* {
    await for (var (type, message) in _hostChild(ip, port, parentIp, parentPort)) {
      if (kDebugMode) {
        print("[MAIN\$$type] $message");
      }
      yield (type, message);
    }
  }

  Future<void> closeServer() async {
    isServerRunning.value = false;
    await _currentServer?.stopServer();
  }

  Future<void> dispose() async {
    await closeServer();
  }

  ShelfServer? _currentServer;
}
