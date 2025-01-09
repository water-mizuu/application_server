import 'dart:async';
import 'dart:io';

import 'package:application_server/shelf.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum DeviceClassification {
  parent,
  child,
  unspecified,
}

class GlobalState {
  static final GlobalState _instance = GlobalState._internal();
  factory GlobalState() => _instance;
  GlobalState._internal();

  /// An example value that can be shared between the main isolate and the server isolate.
  final ValueNotifier<int> counter = ValueNotifier<int>(0);

  /// The mode of the device. It should be either parent or child, or unspecified at the start.
  /// In the future, this will be assigned only at first,
  ///   then it will be read from shared preferences.
  final ValueNotifier<DeviceClassification> mode =
      ValueNotifier<DeviceClassification>(DeviceClassification.unspecified);

  // Relevant attributes for the parent device.
  late final ValueNotifier<(String, int)?> address = ValueNotifier<(String, int)?>(null);

  /// The address of the parent device.
  late final ValueNotifier<(String, int)?> parentAddress = ValueNotifier<(String, int)?>(null);

  Stream<(String, Object)> hostParent(String ip, int port) async* {
    address.value = null;
    parentAddress.value = null;

    try {
      if (_currentServer case ShelfServer server when server.isStarted) {
        yield ("message", "Closing the existing server at http://${server.ip}:${server.port}");
        await Future.delayed(Duration(seconds: 1));
        await server.stopServer();
        await Future.delayed(Duration(seconds: 1));
        yield ("message", "Closed the server.");
      }

      yield ("message", "Starting server at http://$ip:$port");
      await Future.delayed(Duration(seconds: 1));
      _currentServer = ShelfParentServer(this, ip, port);
      await _currentServer!.startServer();
      yield ("message", "Started server at http://$ip:$port");
      await Future.delayed(Duration(seconds: 1));
      yield ("done", "Server started");
      address.value = (ip, port);
      parentAddress.value = null;
    } on SocketException catch (e) {
      yield ("exception", e);
    } catch (e) {
      yield ("error", e);
    }
  }

  Stream<(String, Object)> hostChild(String ip, int port, String parentIp, int parentPort) async* {
    address.value = null;
    parentAddress.value = null;

    try {
      if (_currentServer case ShelfServer server when server.isStarted) {
        yield ("message", "Closing the existing server at http://${server.ip}:${server.port}");
        await Future.delayed(Duration(seconds: 1));
        await server.stopServer();
        await Future.delayed(Duration(seconds: 1));
        yield ("message", "Closed the server.");
      }

      yield ("message", "Starting server at http://$ip:$port");
      await Future.delayed(Duration(seconds: 1));
      _currentServer = ShelfChildServer(this, ip, port);
      await _currentServer!.startServer();
      yield ("message", "Started server at http://$ip:$port");
      await Future.delayed(Duration(seconds: 1));

      yield ("message", "Handshaking with the parent device at http://$parentIp:$parentPort");
      await _childHandshake(parentIp, parentPort);
      yield ("message", "Handshaked with the parent device at http://$parentIp:$parentPort");
      await Future.delayed(Duration(seconds: 1));
      yield ("done", "Connection established");
      address.value = (ip, port);
      parentAddress.value = (parentIp, parentPort);
    } on SocketException catch (e) {
      yield ("exception", e);
    } catch (e) {
      yield ("error", e);
    }
  }

  ShelfServer? _currentServer;

  Future<void> _childHandshake(String ip, int port) async {
    final response = await http.get(Uri.parse("http://$ip:$port/handshake"));
    if (response.statusCode != 200) {
      throw Exception("Failed to handshake with the parent device.");
    }
  }
}
