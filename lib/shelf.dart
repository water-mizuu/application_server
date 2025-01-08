import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:application_server/future_not_null.dart';
import 'package:application_server/global_state.dart';
import 'package:application_server/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class ShelfServer {
  final GlobalState globalState;
  final ReceivePort receivePort = ReceivePort();
  late final SendPort _sendPort = receivePort.sendPort;
  late final SendPort serverSendPort;

  ShelfServer(this.globalState) {
    receivePort.listen((message) {
      switch (message) {
        case "clickData":
          serverSendPort.send(globalState.counter.value);
          break;
        case "clickOnce":
          globalState.counter.value++;
          serverSendPort.send(globalState.counter.value);
          break;
        case _:
          if (kDebugMode) {
            print("[UNKNOWN] Server Isolate Received: $message");
          }
      }
    });
  }

  Future<void> startServer() async {
    assert(RootIsolateToken.instance != null, "This should be run in the root isolate.");
    RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;

    Completer<int?> portCompleter = Completer<int?>();
    port = portCompleter.future;

    ReceivePort mainReceivePort = ReceivePort();
    Isolate serverIsolate = await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, mainReceivePort.sendPort),
    );

    int receiveCount = 0;
    mainReceivePort.listen((data) {
      switch (receiveCount) {
        case 0:
          if (kDebugMode) {
            print("Server Isolate Send Port received");
          }

          serverSendPort = data as SendPort;
          serverIsolate.addOnExitListener(serverSendPort, response: null);
          break;
        case 1:
          if (kDebugMode) {
            print("Server Isolate Port received: $data");
          }

          portCompleter.complete(data as int);
          break;
        case >= 2:
          if (kDebugMode) {
            print("Server Isolate Received: $data");
          }

          _sendPort.send(data);
          break;
      }

      receiveCount++;
    });
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ShelfServer] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort) payload) async {
    var (token, sendPort) = payload;

    IsolatedServer().init(token, sendPort);
  }
}

class IsolatedServer {
  Completer<dynamic>? _receiveCompleter;

  final ReceivePort receivePort = ReceivePort();
  late final SendPort sendPort;

  IsolatedServer()
      : assert(RootIsolateToken.instance == null, "This should be run in another isolate.");

  Future<void> init(RootIsolateToken token, SendPort mainIsolateSendPort) async {
    sendPort = mainIsolateSendPort;

    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    sendPort.send(receivePort.sendPort);

    /// Initialize the receivePort listener.
    ///   I have no idea how to make this better.
    receivePort.listen((data) {
      if (kDebugMode) {
        print("Server Isolate Received: $data");
      }

      if (_receiveCompleter != null && !_receiveCompleter!.isCompleted) {
        _receiveCompleter!.complete(data);
      }
    });

    var (serverInstance, serverPort) = await _shelfInitiate();
    sendPort.send(serverPort);
  }

  /// Initializes the shelf server, returning the server instance and the port.
  /// The port MAY need to be user modifiable.
  Future<(HttpServer, int)> _shelfInitiate() async {
    int port = 8080;

    NetworkInfo network = NetworkInfo();

    Router router = Router() //
      ..get('/clicks', _getClicks)
      ..get('/clickOnce', _getClickOnce)
      ..get('/<a|.*>', (Request r, String a) => Response.notFound("Request '/$a' not found"));

    Handler handler = Cascade() //
        .add(router.call)
        .handler;

    String ip = await network.getWifiIP().notNull();
    HttpServer server = await shelf_io.serve(logRequests().addHandler(handler), ip, port);

    if (kDebugMode) {
      print("Serving at $ip:$port");
    }

    return (server, port);
  }

  /// Sends a request to the main isolate and returns the response.
  ///   This is a blocking operation.
  ///   There should be an appropriate handler in the main isolate.
  Future<T?> _request<T extends Object>(Object? request) async {
    Completer<T> completer = Completer<T>();
    _receiveCompleter = completer;
    sendPort.send(request);
    T response = await completer.future;
    _receiveCompleter = null;

    return response;
  }

  Future<Response> _getClicks(Request request) async {
    if (await _request("clickData") case int clicks) {
      return Response.ok("Clicks: $clicks");
    }

    return Response.badRequest();
  }

  Future<Response> _getClickOnce(Request request) async {
    if (await _request("clickOnce") case int clicks) {
      return Response.ok("Clicks: $clicks");
    }
    return Response.badRequest();
  }
}
