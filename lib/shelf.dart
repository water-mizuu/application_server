import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:application_server/future_not_null.dart';
import 'package:application_server/global_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

sealed class ShelfServer {
  Future<void> startServer();
  Future<void> stopServer();

  String get ip;
  int get port;

  bool get isStarted;
  Completer<int> get startCompleter;
  Completer<int> get closeCompleter;
}

class ShelfParentServer implements ShelfServer {
  @override
  final String ip;

  @override
  late final int port;

  final GlobalState globalState;
  final ReceivePort receivePort = ReceivePort();
  late final SendPort _sendPort = receivePort.sendPort;
  late final SendPort serverSendPort;

  @override
  final Completer<int> startCompleter = Completer<int>();

  @override
  final Completer<int> closeCompleter = Completer<int>();

  @override
  bool isStarted = false;

  final bool _clicksLock = false;

  ShelfParentServer(this.globalState, this.ip, this.port) {
    receivePort.listen((message) {
      switch (message) {
        case "click":
          globalState.counter.value++;
          serverSendPort.send(("requested", globalState.counter.value));
          break;
        case ("confirmClose", _):
          closeCompleter.complete(0);
          break;
        case _:
          if (kDebugMode) {
            print("[PARENT:Main] Received: $message");
          }
      }
    });
  }

  @override
  Future<void> startServer() async {
    globalState.counter.addListener(_clickListener);

    assert(RootIsolateToken.instance != null, "This should be run in the root isolate.");
    RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;

    ReceivePort initReceivePort = ReceivePort();
    Isolate serverIsolate = await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, initReceivePort.sendPort, port),
    );

    int receiveCount = 0;
    initReceivePort.listen((data) {
      switch (receiveCount) {
        case 0:
          if (kDebugMode) {
            print("[PARENT:Main] Main Isolate Send Port received");
          }

          serverSendPort = data as SendPort;
          serverIsolate.addOnExitListener(serverSendPort, response: null);
          break;
        case 1:
          if (kDebugMode) {
            print("[PARENT:Main] Main Isolate Received acknowledgement: $data");
          }

          if (data == 1) {
            startCompleter.complete(1);
          } else {
            startCompleter.completeError(data);
          }
        case >= 2:
          if (kDebugMode) {
            print("[PARENT:Main] Server Isolate Received: $data");
          }

          _sendPort.send(data);
          break;
      }

      receiveCount++;
    });

    await startCompleter.future;

    isStarted = true;
  }

  @override
  Future<void> stopServer() async {
    if (!isStarted) return;

    globalState.counter.removeListener(_clickListener);
    serverSendPort.send(("stop", null));
    await closeCompleter.future;

    receivePort.close();
    isStarted = false;
  }

  void _clickListener() {
    if (_clicksLock) return;

    serverSendPort.send(("click", globalState.counter.value));
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ShelfParentServer] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort, int) payload) async {
    var (token, sendPort, port) = payload;

    await _IsolatedParentServer().init(token, sendPort, port);
  }
}

class _IsolatedParentServer {
  /// A catcher of sorts for the receivePort listener.
  /// Whenever we request something from the main isolate, we must assign a completer BEFOREHAND.
  Completer<dynamic>? _receiveCompleter;

  final List<(String, String)> _childDevices = [];

  final ReceivePort receivePort = ReceivePort();
  late final SendPort sendPort;

  _IsolatedParentServer()
      : assert(RootIsolateToken.instance == null, "This should be run in another isolate.");

  Future<void> init(RootIsolateToken token, SendPort mainIsolateSendPort, int port) async {
    try {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);

      sendPort = mainIsolateSendPort;
      sendPort.send(receivePort.sendPort);

      var (HttpServer serverInstance, int serverPort) = await _shelfInitiate(port);

      /// Initialize the receivePort listener.
      ///   I have no idea how to make this better.
      receivePort.listen((dynamic data) async {
        if (kDebugMode) {
          print("[PARENT] Server Isolate Received: $data");
        }

        if (data case ("requested", dynamic v)) {
          if (_receiveCompleter != null && !_receiveCompleter!.isCompleted) {
            _receiveCompleter!.complete(v);
          }
        }

        if (data case ("click", int clicks)) {
          if (kDebugMode) {
            print("[PARENT] Received click data: $clicks");
            print("[PARENT] There are currently child devices with IPs $_childDevices");
          }
          List<http.Response> results = await Future.wait([
            for (var (ip, port) in _childDevices)
              if (Uri.parse('http://$ip:$port/click') case var uri)
                http.put(uri, body: clicks.toString()),
          ]);

          if (kDebugMode) {
            print("[PARENT] Updated with result: $results");
          }
        }

        if (data case ("stop", _)) {
          await serverInstance.close();
          receivePort.close();
          sendPort.send(("confirmClose", null));
        }
      });

      sendPort.send(1);
    } catch (e) {
      sendPort.send(e);
    }
  }

  /// The router used by the shelf router. Define all routes here.
  late final Router router = Router() //
    ..post(
      r'/register_child_device/<deviceIp>/<devicePort:\d+>',
      (Request request, String deviceIp, String devicePort) async {
        /// Whenever a child device registers, we do a handshake.
        /// First, we ping the child device to confirm its existence.
        /// Then, we add it to the list of child devices.

        if (kDebugMode) {
          print("[PARENT] Received registration from $deviceIp:$devicePort");
        }

        if (_childDevices.contains((deviceIp, devicePort))) {
          return Response.badRequest(body: "Device already registered.");
        }

        Uri uri = Uri.parse('http://$deviceIp:$devicePort/confirm_parent_device');
        http.Response response = await http.post(uri);
        if (response.statusCode != 200) {
          return Response.badRequest(body: "Failed to confirm the device.");
        }

        _childDevices.add((deviceIp, devicePort));

        return Response.ok("Registered $deviceIp:$devicePort");
      },
    )
    ..put('/click', (Request request) async {
      if (await _request("click") case int clicks) {
        return Response.ok("Clicks: $clicks");
      }
      return Response.badRequest();
    });

  /// Initializes the shelf server, returning the server instance and the port.
  /// The port MAY need to be user modifiable.
  Future<(HttpServer, int)> _shelfInitiate(int port) async {
    NetworkInfo network = NetworkInfo();

    Handler handler = Cascade() //
        .add(router.call)
        .handler;

    String ip = await network.getWifiIP().notNull();
    HttpServer server = await shelf_io.serve(logRequests().addHandler(handler), ip, port);

    if (kDebugMode) {
      print("[PARENT] Serving at $ip:$port");
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
}

class ShelfChildServer implements ShelfServer {
  @override
  final String ip;

  @override
  late final int port;

  final String parentIp;
  final int parentPort;

  final GlobalState globalState;
  final ReceivePort receivePort = ReceivePort();
  late final SendPort _sendPort = receivePort.sendPort;
  late final SendPort serverSendPort;

  @override
  final Completer<int> startCompleter = Completer<int>();

  @override
  final Completer<int> closeCompleter = Completer<int>();

  @override
  bool isStarted = false;

  bool _clicksLock = false;

  ShelfChildServer(this.globalState, this.ip, this.parentIp, this.parentPort) {
    receivePort.listen((message) {
      switch (message) {
        case ("syncClicks", int newCount):
          _clicksLock = true;
          globalState.counter.value = newCount;
          serverSendPort.send(true);
          _clicksLock = false;
          break;
        case ("newClicks", int newCount):
          globalState.counter.value = newCount;
          serverSendPort.send(true);
          break;
        case ("confirmClose", _):
          closeCompleter.complete(0);
          break;
        case _:
          if (kDebugMode) {
            print("[CHILD:Main] Server Isolate Received: $message");
          }
      }
    });
  }

  @override
  Future<void> startServer() async {
    globalState.counter.addListener(_clickListener);

    assert(RootIsolateToken.instance != null, "This should be run in the root isolate.");
    RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;

    ReceivePort setupReceivePort = ReceivePort();
    Isolate serverIsolate = await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, setupReceivePort.sendPort, parentIp, parentPort),
    );

    int receiveCount = 0;
    setupReceivePort.listen((data) {
      switch (receiveCount) {
        case 0:
          if (kDebugMode) {
            print("[CHILD:Main] Send Port received");
          }

          serverSendPort = data as SendPort;
          serverIsolate.addOnExitListener(serverSendPort, response: null);
          break;
        case 1:
          if (kDebugMode) {
            print("[CHILD:Main] Server Port received");
          }
          port = data as int;
          break;
        case 2:
          if (kDebugMode) {
            print("[CHILD:Main] Acknowledgement received: $data");
          }
          if (data == 1) {
            startCompleter.complete(1);
          } else {
            startCompleter.completeError(data);
          }
          break;
        case >= 3:
          if (kDebugMode) {
            print("[CHILD:Main] Server Isolate Received: $data");
          }

          _sendPort.send(data);
          break;
      }

      receiveCount++;
    });

    await startCompleter.future;

    isStarted = true;
  }

  @override
  Future<void> stopServer() async {
    if (!isStarted) return;

    globalState.counter.removeListener(_clickListener);
    serverSendPort.send(("stop", null));
    await closeCompleter.future;

    receivePort.close();
    isStarted = false;
  }

  void _clickListener() {
    if (_clicksLock) return;

    serverSendPort.send(("click", globalState.counter.value));
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ShelfChildServer] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort, String, int) payload) async {
    var (token, sendPort, parentIp, parentPort) = payload;

    _IsolatedChildServer(parentIp, parentPort).init(token, sendPort);
  }
}

class _IsolatedChildServer {
  final String parentIp;
  final int parentPort;

  /// A catcher of sorts for the receivePort listener.
  /// Whenever we request something from the main isolate, we must assign a completer BEFOREHAND.
  Completer<dynamic>? _receiveCompleter;

  final ReceivePort receivePort = ReceivePort();
  late final SendPort sendPort;

  _IsolatedChildServer(this.parentIp, this.parentPort)
      : assert(RootIsolateToken.instance == null, "This should be run in another isolate.");

  Future<void> init(RootIsolateToken token, SendPort mainIsolateSendPort) async {
    try {
      sendPort = mainIsolateSendPort;

      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      sendPort.send(receivePort.sendPort);

      var (serverInstance, serverPort) = await _shelfInitiate();

      /// Initialize the receivePort listener.
      ///   I have no idea how to make this better.
      receivePort.listen((data) async {
        if (data case ("requested", dynamic v)) {
          if (_receiveCompleter != null && !_receiveCompleter!.isCompleted) {
            _receiveCompleter!.complete(v);
          } else {
            throw StateError("No completer was assigned for the received data: $v");
          }
        }

        if (data case ("click", int clicks)) {
          var uri = Uri.parse('http://$parentIp:$parentPort/click');
          var response = await http.put(uri, body: clicks.toString());

          if (kDebugMode) {
            print("[PARENT] Updated with result: ${response.body}");
          }
        }

        if (data case ("stop", _)) {
          await serverInstance.close();
          receivePort.close();
          sendPort.send(("confirmClose", null));
        }
      });
      sendPort.send(serverPort);
      sendPort.send(1);
    } catch (e) {
      sendPort.send(e);
    }
  }

  /// The router used by the shelf router. Define all routes here.
  late final Router router = Router() //
    ..post("/confirm_parent_device", (Request request) async {
      if (kDebugMode) {
        print(request.context);
      }
      return Response.ok("Confirmed parent device");
    })
    ..put("/click", (Request request) async {
      try {
        int newCount = await request.readAsString().then(int.parse);

        /// Update the local state.
        await _request<bool>(("syncClicks", newCount));

        return Response.ok(newCount);
      } catch (e) {
        return Response.internalServerError(body: e.toString());
      }
    });

  /// Initializes the shelf server, returning the server instance and the port.
  /// The port MAY need to be user modifiable.
  Future<(HttpServer, int)> _shelfInitiate() async {
    NetworkInfo network = NetworkInfo();
    String ip = await network.getWifiIP().notNull();

    Handler handler = Cascade() //
        .add(router.call)
        .handler;
    HttpServer server = await shelf_io.serve(logRequests().addHandler(handler), ip, 0);

    if (kDebugMode) {
      print("[CHILD:Server] Serving at $ip:${server.port}}");
    }

    return (server, server.port);
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
}
