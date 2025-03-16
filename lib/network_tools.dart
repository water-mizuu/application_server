import "dart:async";
import "dart:isolate";

import "package:application_server/debug_print.dart";
import "package:application_server/future_not_null.dart";
import "package:application_server/playground_parallelism.dart";
import "package:application_server/throwable.dart";
import "package:flutter/services.dart";
import "package:network_info_plus/network_info_plus.dart";
import "package:network_tools/network_tools.dart";
import "package:path_provider/path_provider.dart";
import "package:time/time.dart";

late final String deviceIp;

/// The receive port for the network tools isolate.
///   This is the only way to communicate with the isolate.
final ListenedReceivePort _networkToolsReceivePort = ReceivePort().hostListener();
late final SendPort _networkToolsSendPort;

/// Does the necessary setup to allow running the network tools over in a separate isolate.
/// This function must be called from the root isolate.
Future<void> initializeNetworkTools() async {
  assert(
    RootIsolateToken.instance != null,
    "This function must be called from the root isolate.",
  );

  deviceIp = await NetworkInfo().getWifiIP().notNull();
  printDebug("Device IP: $deviceIp");

  /// Initialize the network tools in the root isolate too.
  var appDocDirectory = await getApplicationDocumentsDirectory();
  printDebug("Application Document Directory: ${appDocDirectory.path}");

  await configureNetworkTools(appDocDirectory.path);
  await Isolate.spawn(
    _networkTools,
    (_networkToolsReceivePort.sendPort, RootIsolateToken.instance!, deviceIp),
  );
  _networkToolsSendPort = await _networkToolsReceivePort.next<SendPort>();
}

/// Scans the local network for active hosts, returning a list of tuples
///   containing the device name and IP address.
Future<List<(Future<String>, String)>> scanIps() async {
  _networkToolsSendPort.send("scan_ips");
  var result = await _networkToolsReceivePort.next<List<SendableActiveHost>>();

  return [
    for (var sendableActiveHost in result)
      (
        ActiveHost.fromSendableActiveHost(sendableActiveHost: sendableActiveHost) //
            .deviceName
            .timeout(const Duration(seconds: 2))
            .catchError((_) => "Unnamed Device"),
        sendableActiveHost.address,
      ),
  ];
}

/// The process run by the isolate. After the initialization,
///   The isolate waits for the receivePort.
Future<void> _networkTools((SendPort, RootIsolateToken, String) payload) async {
  /// Isolate Initialization
  var (sendPort, token, deviceIp) = payload;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  /// The local receive port within the isolate.
  var receivePort = ReceivePort().hostListener();
  sendPort.send(receivePort.sendPort);

  /// Necessary for the network tools to work in the separate isolate.
  var (appDocDirectoryError, appDocDirectory) = await throwableAsync(
    () => getApplicationDocumentsDirectory().timeout(2.seconds),
  );
  if (appDocDirectoryError case TimeoutException()) {
    printDebug("");
  } else {
    await configureNetworkTools(appDocDirectory!.path);
  }

  var subnet = deviceIp.substring(0, deviceIp.lastIndexOf("."));

  var run = true;
  do {
    var message = await receivePort.next<String>();
    switch (message) {
      case "scan_ips":
        var searcher = HostScannerService.instance.getAllSendablePingableDevices(subnet);
        var devices = [await for (var device in searcher) device];
        sendPort.send(devices);
      case "close":
        run = false;
        receivePort.close();
      case _:
        throw StateError("Unrecognized message $message.");
    }
  } while (run);
}
