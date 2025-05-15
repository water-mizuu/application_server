part of "shelf.dart";

/// The main class handling the connection of the application to
///   the parent server.
final class HostServer implements ShelfServer {
  HostServer(
    this._dialog,
    this._globalState,
    this.ip,
    this.port,
  ) {
    _receivePort.listen(_handleMessagesFromIsolate);
  }

  final String ip;
  late final int port;

  final IsolateDialog _dialog;
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
    printDebug("Main Isolate Send Port received");

    var acknowledgement = await _startupReceivePort.next<Object>();
    printDebug("Acknowledgement received: $acknowledgement");

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
      case (int id, (Requests.showDialog, String message)):
        await _showDialog(id, message);
      case (Requests.confirmClose, _):
        closeCompleter.complete(0);
      case _:
        printDebug("Received message: $message");
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

  /// Prompts the application to show a message dialog.
  Future<void> _showDialog(int id, String message) async {
    await _dialog.showDialog(message);

    _serverSendPort.send(("requested", (id, true)));
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [HostServer] class.
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

  bool _isJobRunning = false;

  /// Runs a concurrent job in the isolate.
  /// This should only be used in tasks that are REQUIRED to be run ATOMICALLY.
  Future<T> runJob<T>(Future<T> Function() job) {
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

  /// A shortcut for the [requestFromMain] method.
  late final $ = requestFromMain;

  // ignore: prefer_function_declarations_over_variables
  late final $_ = <T extends Object>(Requests request) async => requestFromMain<T>((request, null));

  /// Handles messages from the main isolate.
  ///   This is the main handler for all messages from the main isolate.
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
        printDebug("[PARENT] Received request with id $id and data $v");

        receiveCompleters[id]!.complete(v);
        receiveCompleters.remove(id);
      case ("state", String encodedState):
        printDebug("[PARENT] Received state data: $encodedState");
        printDebug("[PARENT] There are currently child devices with IPs $connectedChannels");

        await Future.wait([
          for (var channel in connectedChannels.toList()) //
            Isolate.run(() => _updateChannel(channel, encodedState)),
        ]);
      case ("stop", _):
        printDebug("[PARENT] Stopping server.");

        // await serverInstance.close();
        receivePort.close();
        sendPort.send(("confirmClose", null));
      case _:
        throw StateError("[PARENT] Received unknown message: $data");
    }
  }

  /// Updates the channel with the new state.
  Future<void> _updateChannel(WebSocketChannel channel, String encodedState) async {
    var (error, _) = await throwableAsync(() => channel.ready);
    if (error case SocketException() || WebSocketException()) {
      printDebug("Removed channel due to error: $error.");

      connectedChannels.remove(channel);
    }

    channel.sink.add(encodedState);
  }

  /// Since the establishement of connections may require some time,
  ///   with requests done asynchronously, we must wait make sure that
  ///   establishing the connection is atomic.
  Future<void> handleWebSocketConnection(WebSocketChannel channel, [String? subprotocol]) {
    return runJob(() async {
      /// First, we wait for the channel connection to be ready.
      var (socketError, _) = await throwableAsync(() => channel.ready);
      if (socketError != null) {
        printDebug("Error encountered in opening socket: $socketError");

        return;
      }

      /// We add the channel to the list of connected channels.
      connectedChannels.add(channel);

      /// On first connection, we must send back the snapshot of data.
      var (snapshotError, snapshot) = await $_<String>(Requests.globalStateSnapshot);
      await showDialog("Received snapshot $snapshot");
      if (snapshotError != null) {
        printDebug("Failed to fetch the global state snapshot.");
        return;
      }

      /// After we get the state snapshot, we send it back to the child.
      channel.sink.add(jsonEncode({"state_snapshot": snapshot}));

      /// Now, we wait for messages from the connection.
      await for (var message in channel.stream) {
        assert(message is String);

        if (await handleSocketMessage(channel, message as String) case var value?) {
          channel.sink.add(value);
        }
      }
    });
  }

  /// Handles messages from a specific socket.
  Future<String?> handleSocketMessage(WebSocketChannel channel, String message) async {
    var decoded = jsonDecode(message);
    switch (decoded) {
      case {"id": int id, "updateMisc": 1}:
        return jsonEncode({"id": id, "success": true});
      case var message?:
        if (kDebugMode) {
          printDebug("Unknown message $message.");
          await showDialog("Unknown message $message");
        }

        return null;
    }
  }

  Future<void> showDialog(String message) async {
    /// Since we are in a separate isolate, we must use the bridge to prompt the main isolate to show the dialog.

    await requestFromMain<bool>((Requests.showDialog, message));
  }
}
