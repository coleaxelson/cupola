import 'package:flutter/widgets.dart';

/// Clips [child] at its top and bottom only, so what it paints past its sides
/// (a card's shadow, the light under a hero) reaches the room around it.
///
/// For a page's vertical scroll view, which clips at its own edges by default.
/// On a phone those edges are the screen's and nothing shows; with a side
/// inset (a rail floating over the page, the iPhone Duo's sensor column) the
/// page's content stops short of the screen's edge, and a shadow cut there
/// drew a straight line down the room. The scroll view inside takes
/// `clipBehavior: Clip.none`; this keeps what scrolls out of the top and the
/// bottom from painting over what sits above and below it.
class SideBleed extends StatelessWidget {
  const SideBleed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ClipRect(clipper: const _OpenSides(), child: child);
}

class _OpenSides extends CustomClipper<Rect> {
  const _OpenSides();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, 0, size.width * 2, size.height);

  @override
  bool shouldReclip(_OpenSides oldClipper) => false;
}
