part of "shelf.dart";

final class ChildConnection implements ShelfServer {
  ChildConnection(
    this._globalState,
    this.ip,
    this.port,
  ) {
    _receivePort.listen(_handleMessagesFromIsolate);
  }

  final String ip;
  late final int port;

  final GlobalState _globalState;

  final ListenedReceivePort _startupReceivePort = ReceivePort().hostListener();
  final ReceivePort _receivePort = ReceivePort();
  late final SendPort _sendPort = _receivePort.sendPort;
  late final SendPort _serverSendPort;
  late final Isolate _serverIsolate;

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

    _serverIsolate = await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, _startupReceivePort.sendPort, port),
    );

    _serverSendPort = await _startupReceivePort.next<SendPort>();
    if (kDebugMode) {
      print("[PARENT:Main] Main Isolate Send Port received");
    }

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

    /// Clear all the listeners.
    _globalState.counter.removeListener(_clickListener);

    /// Give the isolate the stop signal, and wait for its response.
    _serverSendPort.send(("stop", null));
    unawaited(
      closeCompleter.future.timeout(5.seconds).catchError((_) async {
        _serverIsolate.kill(priority: Isolate.immediate);
        return 0;
      }),
    );

    _receivePort.close();
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

    _serverSendPort.send(("click", _globalState.counter.value));
  }

  Future<void> _handleMessagesFromIsolate(Object? message) async {
    assert(
      message is (int, (String, Object?)) || message is (String, Object?),
      "Each received data must have an identifier.",
    );

    switch (message) {
      case (int id, (Requests.click, _)):
        _incrementCounter(id);
      case (int id, (Requests.globalStateSnapshot, _)):
        _sendBackGlobalState(id);
      case (Requests.confirmClose, _):
        closeCompleter.complete(0);
      case _:
        if (kDebugMode) {
          print("[PARENT:Main] Received message: $message");
        }
    }
  }

  /// Increments the global counter, and sends the new value to the child
  void _incrementCounter(int id) {
    _globalState.counter.value++;
    _serverSendPort.send(("requested", (id, _globalState.counter.value)));
  }

  /// Gets the global state and sends it back to the child.
  void _sendBackGlobalState(int id) {
    var json = jsonEncode(_globalState.toJson());

    _serverSendPort.send(("requested", (id, json)));
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ChildConnection] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort, int) payload) async {
    var (token, sendPort, port) = payload;

    var server = _IsolatedParentServer(token, sendPort, port);
    sendPort.send(server.receivePort.sendPort);

    await server.initialize();
  }
}

final class _IsolatedParentServer {
  _IsolatedParentServer(
    RootIsolateToken token,
    this.sendPort,
    this.port,
  ) : assert(RootIsolateToken.instance == null, "This should be run in another isolate.") {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  /// A catcher of sorts for the receivePort listener.
  /// Whenever we request something from the main isolate, we must assign a completer BEFOREHAND.
  // Completer<Object?>? _receiveCompleter;
  late final Map<int, Completer<Object?>> receiveCompleters = {};
  final List<WebSocketChannel> connectedChannels = [];

  final ReceivePort receivePort = ReceivePort();
  final SendPort sendPort;
  int port;

  late final AsyncQueue _jobQueue = AsyncQueue.autoStart();

  Future<void> initialize() async {
    try {
      port = await _shelfInitiate(handleWebSocketConnection, port);
      receivePort.listen(handleMessagesFromMainIsolate);
      sendPort.send(1);
    } on Object catch (e) {
      sendPort.send(e);
    }
  }

  // /// The router used by the shelf router. Define all routes here.
  // late final Router router = Router() //
  //   ..post(
  //     "/register_child_device",
  //     (Request request) => runJob(() async {
  //       switch (request.url.queryParameters) {
  //         case {"ip": var deviceIp, "port": var devicePort}:
  //           {
  //             try {
  //               /// Whenever a child device registers, we do a handshake.
  //               /// First, we ping the child device to confirm its existence.
  //               /// Then, we add it to the list of child devices.

  //               if (kDebugMode) {
  //                 print("[PARENT] Received registration from $deviceIp:$devicePort");
  //               }

  //               if (childDevices.contains((deviceIp, devicePort))) {
  //                 return Response.badRequest(body: "Device already registered.");
  //               }

  //               var state = await requestFromMain<String>((Requests.globalStateSnapshot, null));
  //               if (kDebugMode) {
  //                 print("[PARENT] Received state snapshot $state");
  //               }
  //               var uri = Uri.parse("http://$deviceIp:$devicePort/confirm_parent_device");
  //               var response = await http.post(uri, body: state).timeout(250.milliseconds);
  //               if (response.statusCode != 200) {
  //                 return Response.badRequest(body: "Failed to confirm the device.");
  //               }

  //               childDevices.add((deviceIp, devicePort));

  //               return Response.ok("Registered $deviceIp:$devicePort");
  //             } on TimeoutException {
  //               return Response.badRequest(
  //                 body: "Failed to ping the device at $deviceIp:$devicePort.",
  //               );
  //             }
  //           }
  //         case {"ip": _}:
  //           return Response.badRequest(body: "The port must be provided under the key 'ip'.");
  //         case {"port": _}:
  //           return Response.badRequest(body: "The IP must be provided under the key 'port'.");
  //         case Map():
  //           return Response.badRequest(
  //             body: "The IP and port must be provided under "
  //                 "the keys 'ip' and 'port' respectively.",
  //           );
  //       }
  //     }),
  //   )
  //   ..put(
  //     "/click",
  //     (Request request) => runJob(() async {
  //       if (await requestFromMain((Requests.click, null)) case int clicks) {
  //         return Response.ok(clicks.toString());
  //       }
  //       return Response.badRequest();
  //     }),
  //   );

  bool _isJobRunning = false;
  Future<T> runJob<T>(Future<T> Function() job) async {
    assert(!_isJobRunning, "[runJob] must not be called inside another job.");

    var completer = Completer<T>.sync();
    _jobQueue.addJobThrow((_) async {
      _isJobRunning = true;
      var result = await job();
      _isJobRunning = false;
      completer.complete(result);
    });

    return completer.future;
  }

  Future<void> sendToMain((Requests, Object?) request) async {
    sendPort.send(request);
  }

  int _requestId = 0;

  /// Sends a request to the main isolate and returns the response.
  ///   This is a blocking operation.
  ///   There should be an appropriate handler in the main isolate.

  Future<(Object?, T?)> requestFromMain<T extends Object>((Requests, Object?) request) async {
    var completer = Completer<T>();
    var id = _requestId++;
    receiveCompleters[id] = completer;
    sendPort.send((id, request));
    var response = await throwableAsync(() => completer.future);
    receiveCompleters.remove(id);

    return response;
  }

  Future<void> handleMessagesFromMainIsolate(Object? data) async {
    assert(
      data is (String, Object?),
      "Each received data must have an identifier. "
      "However, the received data was: $data",
    );

    switch (data) {
      case ("requested", (int id, var v)):
        assert(
          receiveCompleters.containsKey(id),
          "The completer must be assigned before the request.",
        );
        if (kDebugMode) {
          print("[PARENT] Received request with id $id and data $v");
        }

        receiveCompleters[id]!.complete(v);
      case ("click", int clicks):
        if (kDebugMode) {
          print("[PARENT] Received click data: $clicks");
          print("[PARENT] There are currently child devices with IPs $connectedChannels");
        }

        await Future.wait([
          for (var channel in connectedChannels.toList())
            () async {
              var errorEncountered = false;
              var (error, _) = await throwableAsync(() => channel.ready);
              if (error case SocketException() || WebSocketException()) {
                errorEncountered = true;
              }

              if (errorEncountered) {
                if (kDebugMode) {
                  print("Removed channel due to error: $error.");
                }

                connectedChannels.remove(channel);
              }

              channel.sink.add(clicks.toString());
            }(),
        ]);
      case ("stop", _):
        if (kDebugMode) {
          print("[PARENT] Stopping server.");
        }

        // await serverInstance.close();
        receivePort.close();
        sendPort.send(("confirmClose", null));
    }
  }

  Future<void> handleWebSocketConnection(WebSocketChannel channel) => runJob(() async {
        /// First, we wait for the channel connection to be ready.
        var (socketError, _) = await throwableAsync(() => channel.ready);
        if (socketError case SocketException() || WebSocketException()) {
          if (kDebugMode) {
            print("Channel was not ready. $socketError");
          }
          return;
        } else if (socketError case var v?) {
          if (kDebugMode) {
            print("Error encountered in opening socket: $v");
          }

          return;
        }

        connectedChannels.add(channel);

        /// On first connection, we must send back the snapshot of data.
        var (snapshotError, snapshot) =
            await requestFromMain<String>((Requests.globalStateSnapshot, null));
        if (snapshotError case != null) {
          if (kDebugMode) {
            print("Failed to fetch the global state snapshot.");
          }

          return;
        }

        channel.sink.add(jsonEncode({"state_snapshot": snapshot}));
        await for (var message in channel.stream) {
          assert(message is String);
          var decoded = jsonDecode(message as String);

          switch (decoded) {
            case {"id": int id, "updateMisc": 1}:
              channel.sink.add(jsonEncode({"id": id, "success": true}));
            case var message?:
              if (kDebugMode) {
                print("Unknown message $message");
              }
          }
        }
      });
}
