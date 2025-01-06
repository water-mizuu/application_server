import 'package:flutter/foundation.dart';

class GlobalState {
  static final GlobalState _instance = GlobalState._internal();
  factory GlobalState() => _instance;
  GlobalState._internal();

  /// An example value that can be shared between the main isolate and the server isolate.
  final ValueNotifier<int> counter = ValueNotifier<int>(0);
}
