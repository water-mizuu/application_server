import "dart:io";

import "package:application_server/global_state.dart";
import "package:application_server/maximize_or_restore_button.dart";
import "package:bitsdojo_window/bitsdojo_window.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/foundation.dart";
import "package:material_symbols_icons/symbols.dart";
import "package:provider/provider.dart";

class NavigationBar extends StatelessWidget {
  const NavigationBar({super.key});

  static final buttonColors = WindowButtonColors(
    iconNormal: const Color(0xFF000000),
    mouseOver: const Color(0x22000000),
    mouseDown: const Color(0x33000000),
    iconMouseOver: const Color(0xAA000000),
    iconMouseDown: const Color(0xBB000000),
  );

  static final closeButtonColors = WindowButtonColors(
    mouseOver: const Color(0xFFD32F2F),
    mouseDown: const Color(0xFFB71C1C),
    iconNormal: const Color(0xFF000000),
    iconMouseOver: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        /// There is no documentation on how this works. It just does.
        appWindow.startDragging();
      },
      child: WindowTitleBarBox(
        child: ColoredBox(
          color: Colors.white,
          child: Platform.isMacOS
              // For macOS, we can't override the title bar.
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(Symbols.flutter),
                    ),
                    Text(
                      "Application Server",
                      style: TextStyle(
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(Symbols.flutter),
                    ),
                    const Text(
                      "Application Server",
                      style: TextStyle(
                        fontFamily: "Segoe UI",
                        fontSize: 12.0,
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                    MinimizeWindowButton(colors: buttonColors, animate: true),
                    MaximizeOrRestoreButton(colors: buttonColors, animate: true),
                    CloseWindowButton(
                      colors: closeButtonColors,
                      animate: true,
                      onPressed: () async {
                        if (kDebugMode) {
                          print("[MAIN] Closing the window.");
                        }

                        await context.read<GlobalState>().closeServer();
                        appWindow.close();
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
