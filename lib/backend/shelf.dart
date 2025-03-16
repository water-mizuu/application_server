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

import "package:application_server/debug_print.dart";
import "package:application_server/future_not_null.dart";
import "package:application_server/global_state.dart";
import "package:application_server/isolate_dialog.dart";
import "package:application_server/playground_parallelism.dart";
import "package:application_server/throwable.dart";
import "package:async_queue/async_queue.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:network_info_plus/network_info_plus.dart";
import "package:shelf/shelf_io.dart" as shelf_io;
import "package:shelf_web_socket/shelf_web_socket.dart";
import "package:time/time.dart";
import "package:web_socket_channel/web_socket_channel.dart";

part "shelf_child.dart";
part "shelf_parent.dart";

sealed class ShelfServer {
  Future<void> startServer();
  Future<void> stopServer();

  bool get isStarted;
  Completer<void> get startCompleter;
  Completer<void> get closeCompleter;
}

extension type const Requests._(String inner) {
  static const Requests showDialog = Requests._("showDialog");
  static const Requests globalStateSnapshot = Requests._("globalStateSnapshot");
  static const Requests overrideGlobalState = Requests._("overrideGlobalState");
  static const Requests click = Requests._("click");
  static const Requests syncClicks = Requests._("syncClicks");
  static const Requests confirmClose = Requests._("confirmClose");
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
  var handler = webSocketHandler(onConnect);
  var server = await shelf_io.serve(handler, ip, port);

  printDebug("Serving at $ip:$port");

  return server.port;
}
