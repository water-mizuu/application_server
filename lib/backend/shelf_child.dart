part of "shelf.dart";

final class ShelfChildServer implements ShelfServer {
  ShelfChildServer(
    this.globalState,
    this.ip,
    this.parentIp,
    this.parentPort,
  ) {
    receivePort.listen((message) async {
      assert(
        message is (int, (String, Object?)) || message is (String, Object?),
        "Each received data must have an identifier.",
      );
      switch (message) {
        case (Requests.syncClicks, int newCount):
          _lockClicks = true;
          globalState.counter.value = newCount;
          _lockClicks = false;
        case (Requests.overrideGlobalState, String snapshot):
          var json = await compute(jsonDecode, snapshot) as Map<String, Object?>;
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
  final ReceivePort receivePort = ReceivePort();
  late final SendPort _sendPort = receivePort.sendPort;
  late final SendPort serverSendPort;

  @override
  final Completer<int> startCompleter = Completer<int>();

  @override
  final Completer<int> closeCompleter = Completer<int>();

  @override
  bool isStarted = false;

  /// A flag that prevents the server from sending clicks to the parent device.
  bool _lockClicks = false;

  final ListenedReceivePort _setupReceivePort = ReceivePort().hostListener();

  @override
  Future<void> startServer() async {
    globalState.counter.addListener(_clickListener);

    assert(RootIsolateToken.instance != null, "This should be run in the root isolate.");
    var rootIsolateToken = RootIsolateToken.instance!;

    await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, _setupReceivePort.sendPort, parentIp, parentPort),
    );

    // Our first expected value is the send port from the server isolate.
    serverSendPort = await _setupReceivePort.next<SendPort>();
    if (kDebugMode) {
      print("[CHILD:Main] Send Port received:${serverSendPort.hashCode.bitLength}");
    }

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

    await _IsolatedChildServer(token, sendPort, parentIp, parentPort).initialize();
  }
}

final class _IsolatedChildServer implements IsolatedServer {
  _IsolatedChildServer(
    RootIsolateToken token,
    this.sendPort,
    this.parentIp,
    this.parentPort,
  ) : assert(RootIsolateToken.instance == null, "This should be run in another isolate.") {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  final String parentIp;
  final int parentPort;

  late final Map<int, Completer<Object?>> receiveCompleters = {};
  final List<(String, String)> childDevices = [];

  final ReceivePort receivePort = ReceivePort();
  final SendPort sendPort;

  late final AsyncQueue _jobQueue = AsyncQueue.autoStart();

  Future<void> initialize() async {
    try {
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
                await sendToMain((Requests.syncClicks, value));
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
      (Request request) => runJob(() async {
        if (kDebugMode) {
          print("[CHILD] Received confirmation from parent device.");
        }

        var snapshot = await request.readAsString();
        await sendToMain((Requests.overrideGlobalState, snapshot));

        return Response.ok("Confirmed parent device");
      }),
    )
    ..post(
      "/sync_click",
      (Request request) => runJob(() async {
        try {
          var newCount = await request.readAsString().then(int.parse);

          /// Update the local state.
          await sendToMain((Requests.syncClicks, newCount));

          return Response.ok(newCount.toString());
        } on Exception catch (e) {
          return Response.internalServerError(body: e.toString());
        }
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

  int _requestId = 0;

  /// Sends a request to the main isolate and returns the response.
  ///   This is a blocking operation.
  ///   There should be an appropriate handler in the main isolate.
  @override
  Future<T?> requestFromMain<T extends Object>((String, Object?) request) async {
    var completer = Completer<T>();
    var id = _requestId++;
    receiveCompleters[id] = completer;
    sendPort.send((id, request));
    var response = await completer.future;
    receiveCompleters.remove(id);

    return response;
  }
}
