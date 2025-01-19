part of "shelf.dart";

final class ShelfParentServer implements ShelfServer {
  ShelfParentServer(
    this._globalState,
    this.ip,
    this.port,
  ) {
    receivePort.listen((message) async {
      assert(message is (String, Object?), "Each received data must have an identifier.");

      switch (message) {
        case (Requests.click, _):
          _globalState.counter.value++;
          serverSendPort.send(("requested", _globalState.counter.value));
        case (Requests.globalStateSnapshot, _):
          serverSendPort.send(("requested", jsonEncode(_globalState.toJson())));
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

  final GlobalState _globalState;

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

  @override
  Future<void> startServer() async {
    _globalState.counter.addListener(_clickListener);

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

    _globalState.counter.removeListener(_clickListener);
    serverSendPort.send(("stop", null));
    await closeCompleter.future;

    receivePort.close();
    _startupReceivePort.close();
    isStarted = false;
  }

  /// A field that indicates whether we should upload click changes to the child or not.
  ///   This is to prevent clicks sent from the child to be sent back to the child.
  final bool _clicksLock = false;

  void _clickListener() {
    if (_clicksLock) {
      return;
    }

    serverSendPort.send(("click", _globalState.counter.value));
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ShelfParentServer] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort, int) payload) async {
    var (token, sendPort, port) = payload;

    await _IsolatedParentServer().initialize(token, sendPort, port);
  }
}

final class _IsolatedParentServer implements IsolatedServer {
  _IsolatedParentServer()
      : assert(RootIsolateToken.instance == null, "This should be run in another isolate.");

  /// A catcher of sorts for the receivePort listener.
  /// Whenever we request something from the main isolate, we must assign a completer BEFOREHAND.
  Completer<Object?>? _receiveCompleter;

  final List<(String, String)> _childDevices = <(String, String)>[];

  final ReceivePort receivePort = ReceivePort();
  late final SendPort sendPort;

  late final AsyncQueue _jobQueue = AsyncQueue.autoStart();

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
      "/register_child_device",
      (Request request) => runJob(() async {
        switch (request.url.queryParameters) {
          case {"ip": var deviceIp, "port": var devicePort}:
            {
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

                var state = await requestFromMain<String>((Requests.globalStateSnapshot, null));
                if (kDebugMode) {
                  print("[PARENT] Received state snapshot $state");
                }
                var uri = Uri.parse("http://$deviceIp:$devicePort/confirm_parent_device");
                var response = await http.post(uri, body: state).timeout(250.milliseconds);
                if (response.statusCode != 200) {
                  return Response.badRequest(body: "Failed to confirm the device.");
                }

                _childDevices.add((deviceIp, devicePort));

                return Response.ok("Registered $deviceIp:$devicePort");
              } on TimeoutException {
                return Response.badRequest(
                  body: "Failed to ping the device at $deviceIp:$devicePort.",
                );
              }
            }
          case {"ip": _}:
            return Response.badRequest(body: "The port must be provided under the key 'ip'.");
          case {"port": _}:
            return Response.badRequest(body: "The IP must be provided under the key 'port'.");
          case Map():
            return Response.badRequest(
              body: "The IP and port must be provided under "
                  "the keys 'ip' and 'port' respectively.",
            );
        }
      }),
    )
    ..put(
      "/click",
      (Request request) => runJob(() async {
        if (await requestFromMain((Requests.click, null)) case int clicks) {
          return Response.ok(clicks.toString());
        }
        return Response.badRequest();
      }),
    );

  @override
  Future<Response> runJob(Future<Response> Function() job) async {
    var completer = Completer<Response>();
    _jobQueue.addJobThrow((_) async => completer.complete(await job()));

    return completer.future;
  }

  @override
  Future<void> sendToMain((String, Object?) request) async {
    sendPort.send(request);
  }

  /// Sends a request to the main isolate and returns the response.
  ///   This is a blocking operation.
  ///   There should be an appropriate handler in the main isolate.
  @override
  Future<T?> requestFromMain<T extends Object>((String, Object?) request) async {
    if (_receiveCompleter != null) {
      throw StateError("A completer is already assigned. Requests cannot be made concurrently.");
    }

    var completer = Completer<T>();
    _receiveCompleter = completer;
    sendPort.send(request);
    var response = await completer.future;
    _receiveCompleter = null;

    return response;
  }
}
