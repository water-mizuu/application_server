// ignore_for_file: parameter_assignments

import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/material.dart" hide Colors, Divider, NavigationBar, showDialog;

class GlobalState {
  GlobalState();

  /// An example value that can be shared between the main isolate and the server isolate.
  final ValueNotifier<int> counter = ValueNotifier<int>(0);

  Future<void> synchronizeFromJson(Map<String, Object?> json) async {
    counter.value = json["counter"] as int? ?? 0;
  }

  Map<String, Object?> toJson() {
    return {
      "counter": counter.value,
    };
  }
}
