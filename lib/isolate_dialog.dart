import "dart:async";

import "package:flutter/material.dart" as material;
import "package:flutter/material.dart";

class IsolateDialog {
  late final Completer<void> _isGlobalContextSet = Completer<void>();
  BuildContext? _globalContext;
  set globalContext(BuildContext context) {
    if (_globalContext == null) {
      _globalContext = context;
      _isGlobalContextSet.complete();
    }
  }

  BuildContext get globalContext => _globalContext!;

  /// Shows a dialog with the given message.
  ///   This function will return when the dialog is dismissed.
  Future<void> showDialog(String message) async {
    await _isGlobalContextSet.future;

    var completer = Completer<void>();
    if (globalContext.mounted) {
      await material.showDialog<void>(
        context: globalContext,
        builder: (context) {
          return AlertDialog(
            title: const Text("Message"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  completer.complete();
                },
                child: const Text("Continue"),
              ),
            ],
          );
        },
      );
    }
    return await completer.future;
  }
}
