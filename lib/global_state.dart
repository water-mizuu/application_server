// ignore_for_file: parameter_assignments

import "dart:async";
import "dart:io";

import "package:application_server/shelf.dart";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;

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

  Stream<(String, Object)> hostParent(String ip, int port) async* {
    address.value = null;
    parentAddress.value = null;

    try {
      if (_currentServer case ShelfServer server when server.isStarted) {
        yield ("message", "Closing the existing server at http://${server.ip}:${server.port}");
        await server.stopServer();
        yield ("message", "Closed the server.");
      }

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

  Stream<(String, Object)> hostChild(String ip, int port, String parentIp, int parentPort) async* {
    address.value = null;
    parentAddress.value = null;

    try {
      if (_currentServer case ShelfServer server when server.isStarted) {
        yield ("message", "Closing the existing server at http://${server.ip}:${server.port}");
        await server.stopServer();
        yield ("message", "Closed the server.");
      }

      yield ("message", "Starting server at http://$ip:$port");
      _currentServer = ShelfChildServer(this, ip, parentIp, parentPort);
      await _currentServer!.startServer();
      port = _currentServer!.port;
      yield ("message", "Started server at http://$ip:$port");

      yield ("message", "Handshaking with the parent device at http://$parentIp:$parentPort");

      var uri = Uri.parse("http://$parentIp:$parentPort/register_child_device/$ip/$port");
      if (await http.post(uri) case http.Response response when response.statusCode != 200) {
        throw Exception("Failed to handshake with the parent device.");
      }
      yield ("message", "Handshaked with the parent device at http://$parentIp:$parentPort");
      yield ("done", "Connection established");
      address.value = (ip, port);
      parentAddress.value = (parentIp, parentPort);
    } on SocketException catch (e) {
      yield ("exception", e);
    } on Object catch (e) {
      yield ("error", e);
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
