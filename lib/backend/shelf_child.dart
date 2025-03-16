part of "shelf.dart";

final class ClientConnection implements ShelfServer {
  ClientConnection(
    this.globalState,
    this.parentIp,
    this.parentPort,
  ) {
    receivePort.listen(_handleMessagesFromIsolate);
  }
  final String parentIp;
  final int parentPort;

  final GlobalState globalState;
  final ReceivePort receivePort = ReceivePort();
  late final SendPort _sendPort = receivePort.sendPort;
  late final SendPort serverSendPort;

  @override
  final Completer<void> startCompleter = Completer<void>();

  @override
  final Completer<void> closeCompleter = Completer<void>();

  @override
  bool isStarted = false;

  /// A flag that prevents the server from sending clicks to the parent device.
  ///  This is necessary to prevent infinite loops.
  bool _lockClicks = false;

  final ListenedReceivePort _setupReceivePort = ReceivePort().hostListener();
  late final Isolate _serverIsolate;

  @override
  Future<void> startServer() async {
    globalState.counter.addListener(_clickListener);

    assert(RootIsolateToken.instance != null, "This should be run in the root isolate.");
    var rootIsolateToken = RootIsolateToken.instance!;

    _serverIsolate = await Isolate.spawn(
      _spawnIsolate,
      (rootIsolateToken, _setupReceivePort.sendPort, parentIp, parentPort),
    );

    // Our first expected value is the send port from the server isolate.
    serverSendPort = await _setupReceivePort.next<SendPort>();
    printDebug("Send Port received:${serverSendPort.hashCode.bitLength}");

    // Lastly, we expect an [Object] which will describe the status of the server.
    var acknowledgement = await _setupReceivePort.next<Object>();

    printDebug("Acknowledgement received: $acknowledgement");

    if (acknowledgement == 1) {
      startCompleter.complete();
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

    // We don't have to wait for the isolate to close, as it should on its own.
    unawaited(
      closeCompleter.future.timeout(5.seconds).catchError((_) async {
        _serverIsolate.kill(priority: Isolate.immediate);
        return;
      }),
    );

    _setupReceivePort.close();
    receivePort.close();
    isStarted = false;
  }

  void _clickListener() {
    // TODO(water-mizuu): Implement a way to prevent infinite loops without the need for an explicit lock.
    if (_lockClicks) {
      return;
    }

    serverSendPort.send(("click", globalState.counter.value));
  }

  /// Sends an object to the server isolate with the "requested" identifier.
  void sendRequested(Object? value) {
    serverSendPort.send(("requested", value));
  }

  /// Handles messages from the server isolate.
  ///   Each message must have an identifier.
  Future<void> _handleMessagesFromIsolate(Object? message) async {
    assert(
      message is (int, (String, Object?)),
      "Each received data must have an identifier.",
    );

    switch (message) {
      case (int _, (Requests.syncClicks, int newCount)):
        _lockClicks = true;
        globalState.counter.value = newCount;
        _lockClicks = false;
      case (int _, (Requests.overrideGlobalState, String snapshot)):
        var json = await compute(jsonDecode, snapshot) as Map<String, Object?>;
        _lockClicks = true;
        await globalState.synchronizeFromJson(json);
        _lockClicks = false;

      /// After [stopServer], the receivePort of the server isolate is closed.
      ///   So, we don't need to send anything back.
      case (int _, (Requests.confirmClose, _)):
        closeCompleter.complete();
      case _:
        throw StateError("Unrecognized message: $message");
    }
  }

  /// Spawns the server in another isolate.
  ///   It is critical that this METHOD does not see any of the fields of the [ClientConnection] class.
  static Future<void> _spawnIsolate((RootIsolateToken, SendPort, String, int) payload) async {
    var (token, sendPort, parentIp, parentPort) = payload;

    await SocketConnectionHandler(token, sendPort, parentIp, parentPort).initialize();
  }
}

class SocketConnectionHandler {
  SocketConnectionHandler(
    RootIsolateToken token,
    this.sendPort,
    this.parentIp,
    this.parentPort,
  ) : assert(RootIsolateToken.instance != null, "This should be run in another isolate.") {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }

  final String parentIp;
  final int parentPort;

  final ReceivePort receivePort = ReceivePort();
  final SendPort sendPort;

  late final WebSocketChannel channel;
  late final AsyncQueue _jobQueue = AsyncQueue.autoStart();
  late final Map<int, Completer<Object?>> receiveCompleters = {};

  Future<void> initialize() async {
    channel = WebSocketChannel.connect(Uri.parse("ws://$parentIp:$parentPort"));

    channel.stream.listen(handleSocketMessages);
  }

  /// Handles messager from the websocket connection.
  /// It is in a runJob to prevent race conditions in processing multiple jobs.
  Future<void> handleSocketMessages(Object? message) => _runJob(() async {
        assert(message is String, "Messages must be serialized!");

        var decoded = await compute(jsonDecode, message! as String);
        switch (decoded) {
          case {"state_snapshot": String snapshotString}:
            await sendToMain((Requests.overrideGlobalState, snapshotString));
        }
      });

  /// Runs a concurrent job in the isolate.
  /// This is necessary to disallow race conditions in processing multiple jobs.
  Future<T> _runJob<T>(FutureOr<T> Function() job) async {
    var completer = Completer<T>.sync();
    _jobQueue.addJobThrow((_) async => completer.complete(await job()));

    return completer.future;
  }

  /// Sends a value to the main isolate.
  Future<void> sendToMain((Requests, Object?) request) async {
    sendPort.send((0, request));
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
}
