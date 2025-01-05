import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:application_server/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// TODO: Implement this class to handle two-way communication between the main isolate and the server isolate.
class ShelfServer {
  final ReceivePort mainIsolateReceivePort = ReceivePort();
  final SendPort mainIsolateSendPort;

  final ReceivePort serverIsolateSendPort = ReceivePort();
  late final SendPort serverIsolateReceivePort;

  ShelfServer(this.mainIsolateSendPort);
}

/// Starts the server isolate and returns the isolate instance.
/// This method handles the necessary communication between the main isolate and the server isolate.
Future<(Isolate, SendPort, ReceivePort)> startServer(RootIsolateToken rootIsolateToken) async {
  Completer<int?> portCompleter = Completer<int?>();
  port = portCompleter.future;

  ReceivePort freeReceivePort = ReceivePort();
  ReceivePort mainReceivePort = ReceivePort();
  late SendPort isolateSendPort;
  Isolate serverIsolate = await Isolate.spawn(
    _spawnIsolate,
    (rootIsolateToken, mainReceivePort.sendPort),
  );

  int receiveCount = 0;
  mainReceivePort.listen((message) {
    switch ((receiveCount, message)) {
      /// The first message we receive from the isolate is the send port.
      case (0, SendPort sendPort):
        {
          isolateSendPort = sendPort;
          serverIsolate.addOnExitListener(isolateSendPort, response: null);
          break;
        }
      case (1, int? port):
        {
          portCompleter.complete(port);
          break;
        }
      case (> 1, dynamic message):
        {
          freeReceivePort.sendPort.send(message);
        }
    }
    receiveCount++;
  });

  return (serverIsolate, isolateSendPort, freeReceivePort);
}

/// Initializes the shelf server, returning the server instance and the port.
/// The port MAY need to be user modifiable.
Future<(HttpServer, int)> _shelfInitiate() async {
  int port = 8080;

  NetworkInfo network = NetworkInfo();

  final router = Router()
    ..get(
      '/time',
      (Request request) => Response.ok(DateTime.now().toUtc().toIso8601String()),
    )
    ..get('/clicks', _clicksResponse);
  final cascade = Cascade()
      // If a corresponding file is not found, send requests to a `Router`
      .add(router.call);

  var ip = await network.getWifiIP().then((p) => p!);
  var server = await shelf_io.serve(logRequests().addHandler(cascade.handler), ip, port);

  if (kDebugMode) {
    print("Serving at $ip:$port");
  }

  return (server, port);
}

Future<void> _spawnIsolate((RootIsolateToken, SendPort) arguments) async {
  var (RootIsolateToken token, SendPort sendPort) = arguments;

  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  ReceivePort isolateReceivePort = ReceivePort();
  sendPort.send(isolateReceivePort.sendPort);

  if (kDebugMode) {
    print("Duplex communication established");
  }

  var (HttpServer server, int port) = await _shelfInitiate();

  int isolateReceiveCount = 0;
  await for (dynamic message in isolateReceivePort) {
    switch ((isolateReceiveCount, message)) {
      case (0, null):
        {
          await server.close(force: true);
          break;
        }
      case _:
        {
          throw Exception('Unexpected message from main isolate at count $isolateReceiveCount');
        }
    }
    isolateReceiveCount++;
  }

  sendPort.send(port);
}

Future<Response> _clicksResponse(Request request) async {
  /// We need to somehow communicate with the main isolate to get the current click count.

  return Response.ok("31");
}
