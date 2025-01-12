import "package:bitsdojo_window/bitsdojo_window.dart";
import "package:fluent_ui/fluent_ui.dart";

class MaximizeOrRestoreButton extends StatelessWidget {
  const MaximizeOrRestoreButton({
    required this.colors,
    this.onPressed,
    this.animate = false,
    super.key,
  });

  final WindowButtonColors colors;
  final VoidCallback? onPressed;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    /// This is necessary to get the widget to react to the size of the window.
    ///   Preferrably this should be in a Builder style, but it's Flutter magic.
    MediaQuery.sizeOf(context);

    return WindowButton(
      colors: colors,
      iconBuilder: (context) {
        return appWindow.isMaximized
            ? RestoreIcon(color: colors.iconNormal)
            : MaximizeIcon(color: colors.iconNormal);
      },
      onPressed: onPressed ?? () => appWindow.maximizeOrRestore(),
      animate: animate,
    );
  }
}
