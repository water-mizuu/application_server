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
import "dart:isolate";

import "package:application_server/future_not_null.dart";
import "package:application_server/global_state.dart";
import "package:application_server/playground_parallelism.dart";
import "package:async_queue/async_queue.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:http/http.dart" as http;
import "package:network_info_plus/network_info_plus.dart";
import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart" as shelf_io;
import "package:shelf_router/shelf_router.dart";
import "package:shelf_web_socket/shelf_web_socket.dart";
import "package:time/time.dart";
import "package:web_socket_channel/web_socket_channel.dart";

part "shelf_child.dart";
part "shelf_parent.dart";

sealed class ShelfServer {
  Future<void> startServer();
  Future<void> stopServer();

  String get ip;
  int get port;

  bool get isStarted;
  Completer<int> get startCompleter;
  Completer<int> get closeCompleter;
}

sealed class IsolatedServer {
  // ignore: unused_element
  Future<Response> runJob(Future<Response> Function() job);

  // ignore: unused_element
  Future<void> sendToMain((String, Object?) request);

  // ignore: unused_element
  Future<T?> requestFromMain<T extends Object>((String, Object?) request);
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
Future<int> _shelfInitiate(
  FutureOr<void> Function(WebSocketChannel channel) onConnect,
  int port,
) async {
  var network = NetworkInfo();

  var ip = await network.getWifiIP().notNull();
  var handler = webSocketHandler((WebSocketChannel channel) {
    /// This closure is only called whenever a connection is established.
    ///   How can this be exposed to the class?
    if (kDebugMode) {
      print("Websocket initialized.");
    }
    // Handle the web socket here.

    channel.stream.listen((message) {
      channel.sink.add("echo: $message");
    });
  });
  var server = await shelf_io.serve(handler, ip, port);
  // var server = await shelf_io.serve(process, ip, port);

  if (kDebugMode) {
    print("[:Server] Serving at $ip:$port");
  }

  return server.port;
}
