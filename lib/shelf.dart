/// This file contains all the code for the server-side part of the application.
///   The server is split into two parts: the parent server and the child server.
///   The parent server is the main server that controls the child servers.
///   The child servers are the servers that are controlled by the parent server.
///
/// However, the initialization of the said servers reside in global_state file.
///
/// CRUD Operations in HTTP:
///   - Create: POST
///   - Read: GET
///   - Update: PUT
///   - Delete: DELETE
library;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:isolate";

import "package:application_server/future_not_null.dart";
import "package:application_server/global_state.dart";
import "package:application_server/playground_parallelism.dart";
import "package:application_server/server_manager.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:http/http.dart" as http;
import "package:network_info_plus/network_info_plus.dart";
import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart" as shelf_io;
import "package:shelf_router/shelf_router.dart";
import "package:time/time.dart";

sealed class ShelfServer {
  Future<void> startServer();
  Future<void> stopServer();

  String get ip;
  int get port;

  bool get isStarted;
  Completer<int> get startCompleter;
  Completer<int> get closeCompleter;
}

final class ShelfParentServer implements ShelfServer {
  ShelfParentServer(
    this.globalState,
    this.serverManager,
    this.ip,
    this.port,
  ) {
    receivePort.listen((message) async {
      assert(message is (String, Object?), "Each received data must have an identifier.");

      switch (message) {
        case (Requests.click, _):
          globalState.counter.value++;
          serverSendPort.send(("requested", globalState.counter.value));
        case (Requests.globalStateSnapshot, _):
          serverSendPort.send(("requested", jsonEncode(globalState.toJson())));
        case (Requests.requestClose, _):
          await stopServer();
        case (Requests.confirmClose, _):
          closeCompleter.complete(0);
        case _:
          if (kDebugMode) {
            print("[PARENT:Main] Received: $message");
          }
      }
    });
  }

  @override
  final String ip;

  @override
  late final int port;

  final GlobalState globalState;
  final ServerManager serverManager;

  final ListenedReceivePort _startupReceivePort = ReceivePort().hostListener();
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

  @override
  Future<void> startServer() async {
    globalState.counter.addListener(_clickListener);

    assert(RootIsolateToken.instance != null, "This should be run in the root isolate.");
    var rootIsolateToken = RootIsolateToken.instance!;

    var serverIsolate = await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, _startupReceivePort.sendPort, port),
    );

    serverSendPort = await _startupReceivePort.next<SendPort>();
    if (kDebugMode) {
      print("[PARENT:Main] Main Isolate Send Port received");
    }
    serverIsolate.addOnExitListener(serverSendPort);

    var acknowledgement = await _startupReceivePort.next<Object>();
    if (kDebugMode) {
      print("[PARENT:Main] Acknowledgement received: $acknowledgement");
    }

    if (acknowledgement == 1) {
      startCompleter.complete(1);
    } else {
      startCompleter.completeError(acknowledgement);
    }

    _startupReceivePort.redirectMessagesTo(_sendPort);
    isStarted = true;
  }

  @override
  Future<void> stopServer() async {
    if (!isStarted) {
      return;
    }

    globalState.counter.removeListener(_clickListener);
    serverSendPort.send(("stop", null));
    await closeCompleter.future;

    receivePort.close();
    _startupReceivePort.close();
    isStarted = false;
  }

  void _clickListener() {
    if (_clicksLock) {
      return;
    }

    serverSendPort.send(("click", globalState.counter.value));
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ShelfParentServer] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort, int) payload) async {
    var (token, sendPort, port) = payload;

    await _IsolatedParentServer().initialize(token, sendPort, port);
  }
}

final class _IsolatedParentServer {
  _IsolatedParentServer()
      : assert(RootIsolateToken.instance == null, "This should be run in another isolate.");

  /// A catcher of sorts for the receivePort listener.
  /// Whenever we request something from the main isolate, we must assign a completer BEFOREHAND.
  Completer<Object?>? _receiveCompleter;

  final List<(String, String)> _childDevices = <(String, String)>[];

  final ReceivePort receivePort = ReceivePort();
  late final SendPort sendPort;

  Future<void> initialize(RootIsolateToken token, SendPort mainIsolateSendPort, int port) async {
    try {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);

      sendPort = mainIsolateSendPort;
      sendPort.send(receivePort.sendPort);

      var (serverInstance, serverPort) = await _shelfInitiate(router, port);

      /// Initialize the receivePort listener.
      ///   I have no idea how to make this better.
      receivePort.listen((data) async {
        assert(
          data is (String, Object?),
          "Each received data must have an identifier. "
          "However, the received data was: $data",
        );

        switch (data) {
          case ("requested", var v):
            if (_receiveCompleter != null && !_receiveCompleter!.isCompleted) {
              _receiveCompleter!.complete(v);
            }
          case ("click", int clicks):
            if (kDebugMode) {
              print("[PARENT] Received click data: $clicks");
              print("[PARENT] There are currently child devices with IPs $_childDevices");
            }

            for (var (ip, port) in _childDevices.toList()) {
              try {
                var uri = Uri.parse("http://$ip:$port/sync_click");
                var response = await http
                    .post(uri, body: clicks.toString()) //
                    .timeout(1.seconds);

                if (kDebugMode) {
                  print("[PARENT] Response returned with status code ${response.statusCode}");
                }

                if (response.statusCode != 200) {
                  throw http.ClientException("Failed to update the child device.");
                }
              } on TimeoutException {
                /// The child device did not respond.
                ///   We assume that the child device is no longer available.

                if (kDebugMode) {
                  print("[PARENT] Removing device $ip:$port due to timeout.");
                }

                _childDevices.remove((ip, port));
              } on http.ClientException catch (e) {
                if (kDebugMode) {
                  print("[PARENT] Removing device $ip:$port due to ${e.runtimeType} ${e.message}");
                }

                _childDevices.remove((ip, port));
              }
            }

            if (kDebugMode) {
              print("[PARENT] Updated with result.");
            }
          case ("stop", _):
            if (kDebugMode) {
              print("[PARENT] Stopping server.");
            }

            await serverInstance.close();
            receivePort.close();
            sendPort.send(("confirmClose", null));
        }
      });

      sendPort.send(1);
    } on Object catch (e) {
      sendPort.send(e);
    }
  }

  /// The router used by the shelf router. Define all routes here.
  late final Router router = Router() //
    ..post(
      r"/register_child_device/<deviceIp>/<devicePort:\d+>",
      (Request request, String deviceIp, String devicePort) async {
        try {
          /// Whenever a child device registers, we do a handshake.
          /// First, we ping the child device to confirm its existence.
          /// Then, we add it to the list of child devices.

          if (kDebugMode) {
            print("[PARENT] Received registration from $deviceIp:$devicePort");
          }

          if (_childDevices.contains((deviceIp, devicePort))) {
            return Response.badRequest(body: "Device already registered.");
          }

          var state = await _request<String>((Requests.globalStateSnapshot, null));
          if (kDebugMode) {
            print("[PARENT] Received state snapshot $state");
          }
          var uri = Uri.parse("http://$deviceIp:$devicePort/confirm_parent_device");
          var response = await http.post(uri, body: state).timeout(1.seconds);
          if (response.statusCode != 200) {
            return Response.badRequest(body: "Failed to confirm the device.");
          }

          _childDevices.add((deviceIp, devicePort));

          return Response.ok("Registered $deviceIp:$devicePort");
        } on TimeoutException {
          return Response.badRequest(body: "Confirmation timed out.");
        }
      },
    )
    ..put(
      "/click",
      (Request request) async {
        if (await _request((Requests.click, null)) case int clicks) {
          return Response.ok(clicks.toString());
        }
        return Response.badRequest();
      },
    );

  Future<void> _send((String, Object?) request) async {
    sendPort.send(request);
  }

  /// Sends a request to the main isolate and returns the response.
  ///   This is a blocking operation.
  ///   There should be an appropriate handler in the main isolate.
  Future<T?> _request<T extends Object>((String, Object?) request) async {
    var completer = Completer<T>();
    _receiveCompleter = completer;
    sendPort.send(request);
    var response = await completer.future;
    _receiveCompleter = null;

    return response;
  }
}

final class ShelfChildServer implements ShelfServer {
  ShelfChildServer(
    this.globalState,
    this.serverManager,
    this.ip,
    this.parentIp,
    this.parentPort,
  ) {
    receivePort.listen((message) async {
      assert(message is (String, Object?), "Each received data must have an identifier.");

      switch (message) {
        case (Requests.syncClicks, int newCount):
          _lockClicks = true;
          globalState.counter.value = newCount;
          _lockClicks = false;
        case (Requests.overrideGlobalState, String snapshot):
          var json = jsonDecode(snapshot) as Map<String, Object?>;
          _lockClicks = true;
          await globalState.synchronizeFromJson(json);
          _lockClicks = false;
        case (Requests.requestClose, _):
          await stopServer();

        /// After [stopServer], the receivePort of the server isolate is closed.
        ///   So, we don't need to send anything back.
        case (Requests.confirmClose, _):
          closeCompleter.complete(0);
        case _:
          throw StateError("Unrecognized message: $message");
      }
    });
  }

  @override
  final String ip;

  @override
  late final int port;

  final String parentIp;
  final int parentPort;

  final GlobalState globalState;
  final ServerManager serverManager;
  final ReceivePort receivePort = ReceivePort();
  late final SendPort _sendPort = receivePort.sendPort;
  late final SendPort serverSendPort;

  @override
  final Completer<int> startCompleter = Completer<int>();

  @override
  final Completer<int> closeCompleter = Completer<int>();

  @override
  bool isStarted = false;

  bool _lockClicks = false;
  final ListenedReceivePort _setupReceivePort = ReceivePort().hostListener();

  @override
  Future<void> startServer() async {
    globalState.counter.addListener(_clickListener);

    assert(RootIsolateToken.instance != null, "This should be run in the root isolate.");
    var rootIsolateToken = RootIsolateToken.instance!;

    var serverIsolate = await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, _setupReceivePort.sendPort, parentIp, parentPort),
    );

    // Our first expected value is the send port from the server isolate.
    serverSendPort = await _setupReceivePort.next<SendPort>();
    if (kDebugMode) {
      print("[CHILD:Main] Send Port received:${serverSendPort.hashCode}");
    }
    serverIsolate.addOnExitListener(serverSendPort);

    // Afterwards, the ACTUAL port of the server is received.
    port = await _setupReceivePort.next<int>();
    if (kDebugMode) {
      print("[CHILD:Main] Server Port received: $port");
    }

    // Lastly, we expect an [Object] which will describe the status of the server.
    var acknowledgement = await _setupReceivePort.next<Object>();

    if (kDebugMode) {
      print("[CHILD:Main] Acknowledgement received: $acknowledgement");
    }

    if (acknowledgement == 1) {
      startCompleter.complete(1);
    } else {
      startCompleter.completeError(acknowledgement);
    }

    _setupReceivePort.redirectMessagesTo(_sendPort);
    isStarted = true;
  }

  @override
  Future<void> stopServer() async {
    if (!isStarted) {
      return;
    }

    globalState.counter.removeListener(_clickListener);
    serverSendPort.send(("stop", null));
    await closeCompleter.future;

    _setupReceivePort.close();
    receivePort.close();
    isStarted = false;
  }

  void _clickListener() {
    if (_lockClicks) {
      return;
    }

    serverSendPort.send(("click", globalState.counter.value));
  }

  void sendRequested(Object? value) {
    serverSendPort.send(("requested", value));
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ShelfChildServer] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort, String, int) payload) async {
    var (token, sendPort, parentIp, parentPort) = payload;

    unawaited(_IsolatedChildServer(parentIp, parentPort).initialize(token, sendPort));
  }
}

final class _IsolatedChildServer {
  _IsolatedChildServer(this.parentIp, this.parentPort)
      : assert(RootIsolateToken.instance == null, "This should be run in another isolate.");

  final String parentIp;
  final int parentPort;

  /// A catcher of sorts for the receivePort listener.
  /// Whenever we request something from the main isolate, we must assign a completer BEFOREHAND.
  Completer<Object?>? _receiveCompleter;

  final ReceivePort receivePort = ReceivePort();
  late final SendPort sendPort;

  Future<void> initialize(RootIsolateToken token, SendPort mainIsolateSendPort) async {
    try {
      sendPort = mainIsolateSendPort;

      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      sendPort.send(receivePort.sendPort);

      var (serverInstance, serverPort) = await _shelfInitiate(router, 0);

      /// Initialize the receivePort listener.
      ///   I have no idea how to make this better.
      receivePort.listen(
        (data) async {
          assert(
            data is (String, Object?),
            "Each received data must have an identifier. "
            "However, the received data was: $data",
          );

          if (kDebugMode) {
            print("[CHILD] Received: $data");
          }

          switch (data) {
            case ("requested", var v):
              if (_receiveCompleter != null && !_receiveCompleter!.isCompleted) {
                _receiveCompleter!.complete(v);
              } else {
                throw StateError("No completer was assigned for the received data: $v");
              }
            case ("click", int clicks):
              try {
                var uri = Uri.parse("http://$parentIp:$parentPort/click");
                var response = await http //
                    .put(uri, body: clicks.toString())
                    .timeout(1.seconds);

                if (kDebugMode) {
                  print("[CHILD] Updated with result: ${response.body}");
                }

                if (response.statusCode != 200) {
                  throw http.ClientException("Failed to update the parent device.");
                }

                var value = int.parse(response.body);
                await _send((Requests.syncClicks, value));
              } on TimeoutException catch (e) {
                if (kDebugMode) {
                  print("[CHILD] $e");
                  print("[CHILD] Failed to update the CHILD device.");
                }
              } on http.ClientException catch (e) {
                if (kDebugMode) {
                  print(
                    "[CHILD] Failed to update the parent "
                    "device due to ${e.runtimeType} ${e.message}",
                  );
                }
              }
            case ("stop", _):
              if (kDebugMode) {
                print("[CHILD] Stopping server.");
              }

              await serverInstance.close();
              receivePort.close();
              sendPort.send(("confirmClose", null));
          }
        },
        onDone: () {},
      );

      sendPort.send(serverPort);
      sendPort.send(1);
    } on Object catch (e) {
      sendPort.send(e);
    }
  }

  /// The router used by the shelf router. Define all routes here.
  late final Router router = Router() //
    ..post(
      "/confirm_parent_device",
      (Request request) async {
        if (kDebugMode) {
          print("[CHILD] Received confirmation from parent device.");
        }

        var snapshot = await request.readAsString();
        await _send((Requests.overrideGlobalState, snapshot));

        return Response.ok("Confirmed parent device");
      },
    )
    ..post(
      "/sync_click",
      (Request request) async {
        try {
          var newCount = await request.readAsString().then(int.parse);

          /// Update the local state.
          await _send((Requests.syncClicks, newCount));

          return Response.ok(newCount.toString());
        } on Exception catch (e) {
          return Response.internalServerError(body: e.toString());
        }
      },
    );

  Future<void> _send((String, Object?) request) async {
    sendPort.send(request);
  }

  /// Sends a request to the main isolate and returns the response.
  ///   This is a blocking operation.
  ///   There should be an appropriate handler in the main isolate.
  Future<T?> _request<T extends Object>((String, Object?) request) async {
    var completer = Completer<T>();
    _receiveCompleter = completer;
    sendPort.send(request);
    var response = await completer.future;
    _receiveCompleter = null;

    return response;
  }
}

class Requests {
  static const String globalStateSnapshot = "globalStateSnapshot";
  static const String overrideGlobalState = "overrideGlobalState";
  static const String click = "click";
  static const String syncClicks = "syncClicks";
  static const String requestClose = "requestClose";
  static const String confirmClose = "confirmClose";
}

/// Initializes the shelf server, returning the server instance and the port.
/// The port MAY need to be user modifiable.
///   There is no guarantee that the port will be the same as the one provided.
///   (i.e if the [port] is 0, the port will be randomly assigned.
///    Otherwise, the port will be the same as the one provided.)
Future<(HttpServer, int)> _shelfInitiate(Router router, int port) async {
  var network = NetworkInfo();

  var cascade = Cascade() //
      .add(router.call);

  var handler = logRequests() //
      .addHandler(cascade.handler);

  var ip = await network.getWifiIP().notNull();
  var server = await shelf_io.serve(handler, ip, port);

  if (kDebugMode) {
    print("[:Server] Serving at $ip:$port");
  }

  return (server, server.port);
}
