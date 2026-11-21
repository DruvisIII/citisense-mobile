import 'dart:math' as math;

import 'package:flutter/material.dart';

// ============================================================
// CITISENSE MASCOT
// ------------------------------------------------------------
// The mascot is drawn in code (not an image) so it can hold
// different props and animate. Poses:
//
//   wave         Home header. Waves each time Home is tapped.
//   megaphone    Beside "Announcements". Static.
//   report       My Reports. Writes on a clipboard (loops).
//   notification Notifications. Holds a ringing bell. Static.
//   settings     Settings. Holds a gear and winks. Static.
//   camera       Report an Issue. Takes a photo (loops).
//   thumbsUp     Login. Static thumbs-up.
//   peek         Peeks out from behind a button and hides (loops).
//   sidePeek     Peeks from behind the left edge of a card. Static.
//   sidePeekHappy  Same, with a happy face (selected card).
// ============================================================

enum MascotPose {
  wave,
  megaphone,
  report,
  notification,
  settings,
  camera,
  thumbsUp,
  peek,
  sidePeek,
  sidePeekHappy,
}

class CitiMascot extends StatefulWidget {
  const CitiMascot({
    super.key,
    required this.pose,
    this.playToken = 0,
    this.animate = true,
    this.backdrop = false,
  });

  final MascotPose pose;

  /// Set to false to show a looping pose as a still image.
  final bool animate;

  /// Draws a community scene (sky, clouds, buildings, trees) behind it.
  final bool backdrop;

  /// For [MascotPose.wave]: change this number to play the wave again.
  final int playToken;

  @override
  State<CitiMascot> createState() => _CitiMascotState();
}

class _CitiMascotState extends State<CitiMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _loops =>
      widget.animate &&
      (widget.pose == MascotPose.report ||
          widget.pose == MascotPose.camera ||
          widget.pose == MascotPose.peek);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: switch (widget.pose) {
          MascotPose.wave => 1900,
          MascotPose.report => 2800,
          MascotPose.camera => 3000,
          MascotPose.peek => 4200,
          _ => 1000,
        },
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted) return;
    // Respect the phone's "remove animations" accessibility setting.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;

    if (widget.pose == MascotPose.wave) {
      _controller.forward(from: 0);
    } else if (_loops) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CitiMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pose == MascotPose.wave &&
        widget.playToken != oldWidget.playToken) {
      _start();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _MascotPainter(
            widget.backdrop,
            widget.pose.index,
            // A still peek shows the mascot fully out.
            widget.pose == MascotPose.peek && !widget.animate
                ? 0.3
                : _controller.value,
          ),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter(this.withBackdrop, this.pose, this.t);

  final bool withBackdrop;
  final int pose;
  final double t;

  late Canvas _c;

  // Drawing space is 120 x 122 (x from -10 to 110); it is scaled to fit
  // and bottom-aligned.
  static const double _w = 120;
  static const double _h = 122;

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;

    // Frame per pose: width, height and left offset in drawing units.
    double fw = _w;
    double fh = _h;
    double ox = 10;
    if (pose == 7) {
      fh = 92; // peek: only the head above the button edge (y = 86)
    }
    if (pose == 8 || pose == 9) {
      fw = 70; // side peek: the part left of the card edge (x = 66)
      ox = -8;
    }

    final double s = math.min(size.width / fw, size.height / fh);
    canvas.save();
    canvas.translate((size.width - fw * s) / 2, size.height - fh * s);
    canvas.scale(s);
    canvas.translate(ox, 0);
    drawMascot(pose, t);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) =>
      old.pose != pose || old.t != t || old.withBackdrop != withBackdrop;

  // ===== DRAWING (BEGIN) =====
  // Colours
  int cBody = 0xFF3B7DEA;
  int cBodyLight = 0xFF63A1F7;
  int cLine = 0xFF1D4FC2;
  int cDeep = 0xFF2259D6;
  int cFoot = 0xFF2E6BE0;
  int cWhite = 0xFFFFFFFF;
  int cPupil = 0xFF111827;
  int cMouth = 0xFF3B1420;
  int cTongue = 0xFFF47C8A;
  int cGold = 0xFFF5B800;
  int cGoldDark = 0xFFC98F00;

  // Arm widths: fill + outline (outline shows 1.5 on each side).
  double armW = 7.6;
  double armOutlineW = 10.6;

  // Limb state for the current frame (viewer's left = l, right = r).
  // Each arm is a rubber-hose curve: shoulder -> elbow -> hand.
  double lSx = 22;
  double lSy = 77;
  double lEx = 13;
  double lEy = 88;
  double lHx = 12;
  double lHy = 99;
  int lHand = 0;
  double rSx = 78;
  double rSy = 77;
  double rEx = 87;
  double rEy = 88;
  double rHx = 88;
  double rHy = 99;
  int rHand = 0;

  // Per-frame look.
  double sway = 0;
  double squash = 1;
  double flagPhase = 0.8;
  int eyes = 0;
  double lookX = 0;
  double lookY = 0;
  int mouth = 0;

  // Pose-specific values.
  double waveE = 0;
  double flash = 0;
  double phoneDy = 0;
  double penX = 61;
  double penY = 99.5;

  bool skipHands = false;

  void drawMascot(int p, double t) {
    if (withBackdrop) {
      drawCommunity();
    }
    if (p == 6) {
      // Thumbs-up = the wave pose at rest.
      p = 0;
      t = 0;
    }
    if (p == 7) {
      drawPeek(t);
      return;
    }
    if (p == 8 || p == 9) {
      drawSidePeek(p == 9);
      return;
    }

    setPose(p, t);

    // ---------- shadow (stays on the ground) ----------
    oval(50, 116, 27 * (2 - squash), 4, fade(0xFF1E3A6E, 0.14));

    drawFigure(p, t);
  }

  void drawFigure(int p, double t) {
    // Lean (sway) and squash/stretch around the feet.
    save();
    translate(50, 112);
    rotate(sway);
    scale2(1 + (1 - squash) * 0.6, squash);
    translate(-50, -112);

    // ---------- feet + leg outlines ----------
    oval(39, 111, 9.5, 5.5, cFoot);
    ovalS(39, 111, 9.5, 5.5, cLine, 1.6);
    oval(61, 111, 9.5, 5.5, cFoot);
    ovalS(61, 111, 9.5, 5.5, cLine, 1.6);
    seg(40.5, 100, 40, 108.5, cLine, 10);
    seg(59.5, 100, 60, 108.5, cLine, 10);

    // ---------- antenna + fluttering flag ----------
    seg(50, 36, 50, 11, cLine, 6.2);
    seg(50, 36, 50, 11, cDeep, 4.2);
    drawFlag(flagPhase);
    circle(50, 10, 3.8, cDeep);
    circleS(50, 10, 3.8, cLine, 1.2);

    // ---------- arm outlines (behind the body) ----------
    strokeP(armCurve(lSx, lSy, lEx, lEy, lHx, lHy), cLine, armOutlineW);
    strokeP(armCurve(rSx, rSy, rEx, rEy, rHx, rHy), cLine, armOutlineW);

    // ---------- body ----------
    Path body = newPath();
    body.moveTo(50, 32);
    body.cubicTo(71, 32, 84, 52, 84, 76);
    body.cubicTo(84, 98, 70, 108, 50, 108);
    body.cubicTo(30, 108, 16, 98, 16, 76);
    body.cubicTo(16, 52, 29, 32, 50, 32);
    body.close();
    fillPV(body, cBodyLight, cBody, 32, 108);
    strokeP(body, cLine, 2.4);

    // ---------- leg + arm fills (cover the body outline = seamless) ----------
    seg(40.5, 100, 40, 108.5, cBody, 7);
    seg(59.5, 100, 60, 108.5, cBody, 7);
    strokeP(armCurve(lSx, lSy, lEx, lEy, lHx, lHy), bodyAt(lSy), armW);
    strokeP(armCurve(rSx, rSy, rEx, rEy, rHx, rHy), bodyAt(rSy), armW);
    oval(32.5, 52, 4, 8, fade(cWhite, 0.28));

    // ---------- ear knobs ----------
    circle(17.5, 63, 4.6, cDeep);
    circleS(17.5, 63, 4.6, cLine, 1.5);
    circle(82.5, 63, 4.6, cDeep);
    circleS(82.5, 63, 4.6, cLine, 1.5);

    // ---------- face ----------
    oval(39.5, 62, 13, 13.5, cWhite);
    oval(60.5, 62, 13, 13.5, cWhite);
    drawEye(41.5, 63, false);
    drawEye(58.5, 63, true);
    drawMouth();

    if (p != 2) {
      drawShield();
    }

    // ---------- props held behind the hands ----------
    if (p == 1) {
      drawMegaphone();
    }
    if (p == 2) {
      drawClipboard(t);
    }
    if (p == 3) {
      drawBell(89, 41);
    }
    if (p == 4) {
      drawGear(92, 73);
    }
    if (p == 5) {
      drawPhone(phoneDy, flash);
    }

    // ---------- hands ----------
    if (!skipHands) {
      drawHand(lSx, lSy, lEx, lEy, lHx, lHy, lHand);
      drawHand(rSx, rSy, rEx, rEy, rHx, rHy, rHand);
    }

    // ---------- props in front of the hands ----------
    if (p == 2) {
      drawPencil(penX, penY);
    }

    restore();
  }

  // ============================================================
  // COMMUNITY BACKDROP: open scene (no frame) behind the mascot
  // clouds, houses, a tree and bushes on a soft patch of ground
  // ============================================================
  void drawCommunity() {
    // Soft ground
    oval(50, 113, 64, 9, 0xFFEAF6EC);
    oval(50, 113, 52, 6.5, 0xFFDDF0E1);

    // Clouds (tinted so they show on the light page background)
    cloud(6, 34, 0.9);
    cloud(94, 22, 0.8);
    cloud(100, 56, 0.55);

    // Houses behind
    house(-6, 112, 22, 20);
    house(80, 112, 19, 18);
    house(97, 112, 12, 12);

    // Tree on the left
    seg(4, 112, 4, 84, 0xFF8B6B4A, 3.2);
    seg(4, 96, -1, 90, 0xFF8B6B4A, 1.8);
    seg(4, 92, 9, 86, 0xFF8B6B4A, 1.8);
    circle(-3, 84, 7.5, 0xFF55AE6C);
    circle(11, 84, 7.5, 0xFF55AE6C);
    circle(4, 76, 10, 0xFF6CC07F);
    circle(-2, 85, 6, 0xFF6CC07F);
    circle(10, 85, 6, 0xFF6CC07F);
    circle(1, 72, 2.6, fade(cWhite, 0.3));

    // Bushes on the ground
    bush(16, 111, 0.65);
    bush(-6, 112, 0.6);
    bush(92, 112, 0.7);
    bush(104, 111, 0.55);
  }

  void house(double left, double base, double w, double h) {
    int wall = 0xFFB4D2F7;
    int roof = 0xFF8EB9F0;
    rrect(left, base - h, left + w, base, 1, wall);
    Path r = newPath();
    r.moveTo(left - 2, base - h + 0.5);
    r.lineTo(left + w / 2, base - h - w * 0.42);
    r.lineTo(left + w + 2, base - h + 0.5);
    r.close();
    fillP(r, roof);
    int win = fade(cWhite, 0.9);
    double ww = w * 0.2;
    rrect(left + w * 0.18, base - h * 0.68, left + w * 0.18 + ww, base - h * 0.68 + ww, 0.6, win);
    rrect(left + w * 0.62, base - h * 0.68, left + w * 0.62 + ww, base - h * 0.68 + ww, 0.6, win);
    rrect(left + w * 0.41, base - h * 0.42, left + w * 0.59, base, 0.6, fade(roof, 0.9));
  }

  void cloud(double x, double y, double s) {
    int c = 0xFFDCE8F8;
    circle(x - 6 * s, y + 1.5 * s, 4.2 * s, c);
    circle(x, y - 1 * s, 6 * s, c);
    circle(x + 6.5 * s, y + 1.5 * s, 4.5 * s, c);
    rrect(x - 10 * s, y + 1 * s, x + 11 * s, y + 6 * s, 2.5 * s, c);
  }

  void bush(double x, double y, double s) {
    int dark = 0xFF4FA96A;
    int light = 0xFF67C182;
    circle(x - 6 * s, y + 2 * s, 6 * s, dark);
    circle(x + 6 * s, y + 2 * s, 6 * s, dark);
    circle(x, y - 3 * s, 8 * s, light);
    circle(x - 6 * s, y + 3 * s, 5 * s, light);
    circle(x + 6 * s, y + 3 * s, 5 * s, light);
    circle(x - 2.5 * s, y - 6 * s, 2.2 * s, fade(cWhite, 0.25));
  }

  // ============================================================
  // PEEK: rises from behind a button, looks around, blinks, hides
  // The button's top edge is at y = 86.
  // ============================================================
  double peekRise(double t) {
    if (t < 0.12 || t > 0.9) {
      return 0;
    }
    if (t < 0.24) {
      return ease((t - 0.12) / 0.12);
    }
    if (t > 0.78) {
      return 1 - ease((t - 0.78) / 0.12);
    }
    return 1;
  }

  void drawPeek(double t) {
    setPose(7, t);
    double rise = peekRise(t);
    if (rise <= 0.001) {
      return;
    }

    // Body: everything above the button edge, sliding up from behind it.
    save();
    clipRect(-30, -30, 150, 86);
    translate(0, (1 - rise) * 84 - 2 * math.sin(rise * math.pi));
    skipHands = true;
    drawFigure(7, t);
    skipHands = false;
    restore();

    // Hands grip the top of the button once the head is up.
    double hs = clamp01((rise - 0.55) / 0.35);
    if (hs > 0) {
      peekHand(29, 86, hs);
      peekHand(71, 86, hs);
    }
  }

  void peekHand(double x, double y, double s) {
    int fillC = bodyAt(77);
    double r = 5.6 * s;
    circle(x, y - 0.5, r + 1.5, cLine);
    circle(x, y - 0.5, r, fillC);
    if (s > 0.6) {
      seg(x - 2, y + 1.2, x - 2, y + 4, cLine, 1);
      seg(x + 1, y + 1.4, x + 1, y + 4.2, cLine, 1);
    }
  }

  // ============================================================
  // SIDE PEEK: leaning out from behind a card's left edge (x = 66)
  // ============================================================
  void drawSidePeek(bool happy) {
    setPose(8, 0);
    if (happy) {
      eyes = 3;
      mouth = 2;
    }

    save();
    clipRect(-40, -30, 66, 140);
    translate(50, 112);
    rotate(-0.13);
    translate(-50, -112);
    skipHands = true;
    drawFigure(8, 0);
    skipHands = false;
    drawHand(lSx, lSy, lEx, lEy, lHx, lHy, lHand);
    restore();

    // Right hand holding the card edge.
    peekHand(66, 64, 1);
  }

  // ============================================================
  // POSES
  // ============================================================
  void setPose(int p, double t) {
    // Defaults: both arms hanging relaxed at the sides.
    setLeft(13, 88, 12, 99, 0);
    setRight(87, 88, 88, 99, 0);
    sway = 0;
    squash = 1;
    flagPhase = 0.8;
    eyes = 0;
    lookX = 0;
    lookY = 0;
    mouth = 0;
    waveE = 0;
    flash = 0;
    phoneDy = 0;

    // ----- WAVE (Home): raise arm, wave from the elbow, lower -----
    if (p == 0) {
      waveE = envelope(t);
      double ph = t * math.pi * 2 * 4;
      double fore = -0.16 + 0.42 * math.sin(ph);
      double ex = 9 + 1.2 * math.sin(ph + 0.6);
      double ey = 75 + 1.4 * math.sin(ph);
      double hx = ex + 14 * math.sin(fore);
      double hy = ey - 14 * math.cos(fore);
      setLeft(lerp(13, ex, waveE), lerp(88, ey, waveE), lerp(12, hx, waveE),
          lerp(99, hy, waveE), waveE > 0.35 ? 1 : 0);
      // Other arm: thumbs-up at rest, relaxes while waving.
      setRight(lerp(91, 87, waveE), lerp(81, 89, waveE), lerp(92, 84, waveE),
          lerp(67, 99, waveE), waveE > 0.35 ? 0 : 2);
      sway = (-0.05 + 0.014 * math.sin(ph)) * waveE;
      squash = 1 + 0.018 * math.sin(ph * 2) * waveE;
      flagPhase = 0.8 + t * math.pi * 2 * 5;
      mouth = waveE > 0.4 ? 2 : 0;
      if (waveE > 0.5 && ((t > 0.40 && t < 0.47) || (t > 0.70 && t < 0.76))) {
        eyes = 2;
      }
    }

    // ----- MEGAPHONE (Announcements): static -----
    if (p == 1) {
      setRight(95, 93, 84, 87, 0);
      mouth = 1;
    }

    // ----- REPORT (My Reports): writing on a clipboard, loops -----
    if (p == 2) {
      sway = 0.018 * math.sin(t * math.pi * 2);
      squash = 1 + 0.012 * math.sin(t * math.pi * 4);
      flagPhase = 0.8 + t * math.pi * 2 * 2;
      lookY = 2.4;
      if (t > 0.34 && t < 0.40) {
        eyes = 2;
      }
      updatePen(t);
      setLeft(12, 92, 33, 95, 0);
      setRight(94, 93, penX + 10.6, penY - 10.6, 0);
    }

    // ----- NOTIFICATION: holding up a ringing bell, static -----
    if (p == 3) {
      setRight(94, 70, 89, 55, 0);
      setLeft(8, 84, 11, 96, 0);
      eyes = 3;
      mouth = 2;
      flagPhase = 2.2;
    }

    // ----- SETTINGS: gear in hand, other hand on hip, wink -----
    if (p == 4) {
      setRight(95, 92, 86, 85, 0);
      setLeft(6, 87, 18, 97, 0);
      eyes = 1;
    }

    // ----- PEEK (behind buttons): look left, look right, blink -----
    if (p == 7) {
      setLeft(17, 86, 29, 87, 0);
      setRight(83, 86, 71, 87, 0);
      flagPhase = 0.8 + t * math.pi * 2 * 3;
      if (t > 0.3 && t < 0.46) {
        lookX = -2.6 * math.sin(math.pi * (t - 0.3) / 0.16);
      }
      if (t > 0.5 && t < 0.66) {
        lookX = 2.6 * math.sin(math.pi * (t - 0.5) / 0.16);
      }
      if (t > 0.69 && t < 0.74) {
        eyes = 2;
      }
    }

    // ----- SIDE PEEK (barangay cards): looking toward the card -----
    if (p == 8) {
      setLeft(10, 86, 13, 97, 0);
      setRight(86, 70, 70, 64, 0);
      lookX = 2.4;
      flagPhase = 1.6;
    }

    // ----- CAMERA (Report an Issue): raise phone, flash, lower -----
    if (p == 5) {
      double raise = 1;
      if (t < 0.3) {
        raise = ease(t / 0.3);
      } else if (t > 0.86) {
        raise = 1 - ease((t - 0.86) / 0.14);
      }
      phoneDy = (1 - raise) * 10;
      if (t > 0.58 && t < 0.74) {
        flash = math.sin(math.pi * (t - 0.58) / 0.16);
      }
      setRight(96, 80 + phoneDy * 0.5, 85, 59 + phoneDy, 2);
      sway = -0.025 * raise;
      squash = 1 - 0.03 * flash;
      flagPhase = 0.8 + t * math.pi * 2 * 2;
      lookX = 2.2;
      lookY = -1.6;
      if (flash > 0.25) {
        eyes = 2;
        mouth = 2;
      }
    }
  }

  void setLeft(double ex, double ey, double hx, double hy, int style) {
    lEx = ex;
    lEy = ey;
    lHx = hx;
    lHy = hy;
    lHand = style;
  }

  void setRight(double ex, double ey, double hx, double hy, int style) {
    rEx = ex;
    rEy = ey;
    rHx = hx;
    rHy = hy;
    rHand = style;
  }

  // ============================================================
  // ARMS + HANDS
  // ============================================================

  // A smooth curve from shoulder to hand that passes through the elbow.
  Path armCurve(double sx, double sy, double ex, double ey, double hx, double hy) {
    Path a = newPath();
    a.moveTo(sx, sy);
    a.quadraticBezierTo(2 * ex - (sx + hx) / 2, 2 * ey - (sy + hy) / 2, hx, hy);
    return a;
  }

  // Body colour at a given height (matches the body gradient).
  int bodyAt(double y) {
    return mix(cBodyLight, cBody, clamp01((y - 32) / 76));
  }

  // style: 0 fist, 1 open waving hand, 2 thumbs up
  void drawHand(double sx, double sy, double ex, double ey, double hx, double hy, int style) {
    double cx = 2 * ex - (sx + hx) / 2;
    double cy = 2 * ey - (sy + hy) / 2;
    int fillC = bodyAt(sy);

    if (style == 2) {
      seg(hx - 1.5, hy - 3, hx - 1.5, hy - 8.8, cLine, 7);
      circle(hx, hy, 5.9 + 1.5, cLine);
      seg(hx - 1.5, hy - 3, hx - 1.5, hy - 8.8, fillC, 4.4);
      circle(hx, hy, 5.9, fillC);
      seg(hx + 1, hy - 1.6, hx + 4, hy - 1.6, cLine, 1.1);
      seg(hx + 1, hy + 1.6, hx + 4, hy + 1.6, cLine, 1.1);
    } else {
      // Rotate so local +x points along the forearm (out of the wrist).
      double ang = math.atan2(hy - cy, hx - cx);
      save();
      translate(hx, hy);
      rotate(ang);
      handShape(style, cLine, 1.5);
      handShape(style, fillC, 0);
      restore();
    }

    // Wrist patch: blend the arm into the hand (no seam).
    double k = 0.78;
    double px = (1 - k) * (1 - k) * sx + 2 * (1 - k) * k * cx + k * k * hx;
    double py = (1 - k) * (1 - k) * sy + 2 * (1 - k) * k * cy + k * k * hy;
    seg(px, py, hx, hy, fillC, armW);
  }

  void handShape(int style, int color, double grow) {
    if (style == 1) {
      // Four fingers spread + thumb (mitten style, like the reference).
      circle(5.6 * math.cos(-0.78), 5.6 * math.sin(-0.78), 2.2 + grow, color);
      circle(6.1 * math.cos(-0.26), 6.1 * math.sin(-0.26), 2.3 + grow, color);
      circle(6.0 * math.cos(0.26), 6.0 * math.sin(0.26), 2.2 + grow, color);
      circle(5.2 * math.cos(0.76), 5.2 * math.sin(0.76), 1.9 + grow, color);
      circle(4.6 * math.cos(-1.7), 4.6 * math.sin(-1.7), 2.2 + grow, color);
      circle(0, 0, 5.5 + grow, color);
      return;
    }
    circle(0, 0, 5.3 + grow, color);
  }

  // ============================================================
  // FACE
  // ============================================================
  void drawEye(double cx, double cy, bool right) {
    bool closed = eyes == 2 || (eyes == 1 && right);
    if (closed) {
      Path lid = newPath();
      lid.moveTo(cx - 5.5, cy + 1.5);
      lid.quadraticBezierTo(cx, cy - 5, cx + 5.5, cy + 1.5);
      strokeP(lid, cPupil, 2.6);
      return;
    }
    double x = cx + lookX;
    double y = cy + lookY;
    circle(x, y, 7.2, cPupil);
    double big = eyes == 3 ? 3.0 : 2.3;
    circle(x + 2.5, y - 3, big, cWhite);
    circle(x - 2, y + 3, 1.1, cWhite);
  }

  void drawMouth() {
    if (mouth == 1) {
      oval(50, 79.5, 3.6, 4.2, cMouth);
      oval(50, 81.6, 2.3, 1.3, cTongue);
      return;
    }
    Path m = newPath();
    if (mouth == 2) {
      m.moveTo(44, 76.5);
      m.quadraticBezierTo(50, 88, 56, 76.5);
    } else {
      m.moveTo(45.5, 77);
      m.quadraticBezierTo(50, 85, 54.5, 77);
    }
    m.close();
    fillP(m, cMouth);
    if (mouth == 2) {
      oval(50, 80.6, 2.8, 1.6, cTongue);
    } else {
      oval(50, 79.4, 2.2, 1.2, cTongue);
    }
  }

  void drawShield() {
    Path s = newPath();
    s.moveTo(50, 86);
    s.quadraticBezierTo(55, 88.5, 59.5, 88.5);
    s.lineTo(59.5, 95);
    s.quadraticBezierTo(58.5, 101.5, 50, 105.5);
    s.quadraticBezierTo(41.5, 101.5, 40.5, 95);
    s.lineTo(40.5, 88.5);
    s.quadraticBezierTo(45, 88.5, 50, 86);
    s.close();
    fillP(s, 0xFF2F6FE6);
    strokeP(s, cGold, 2);
    circle(50, 93.5, 3.3, cWhite);
    Path pin = newPath();
    pin.moveTo(47.1, 95);
    pin.lineTo(52.9, 95);
    pin.lineTo(50, 99.6);
    pin.close();
    fillP(pin, cWhite);
    circle(50, 93.5, 1.3, 0xFF2F6FE6);
  }

  void drawFlag(double ph) {
    double w1 = 1.8 * math.sin(ph);
    double w2 = 1.5 * math.sin(ph - 1.2);
    double w3 = 1.2 * math.sin(ph + 0.6);
    Path flag = newPath();
    flag.moveTo(51.5, 9.5);
    flag.cubicTo(57, 7.5 + w1, 61, 12.5 - w1, 68, 10.5 + w2);
    flag.lineTo(64 + w3, 15.5 + w2 * 0.5);
    flag.lineTo(68, 20.5 + w2);
    flag.cubicTo(61, 22.5 - w1, 57, 17.5 + w1, 51.5, 19.5);
    flag.close();
    fillP(flag, cDeep);
    strokeP(flag, cLine, 1.2);
  }

  // ============================================================
  // PROPS
  // ============================================================
  void drawMegaphone() {
    rrect(72, 73, 78, 79, 1.5, cGoldDark);
    Path cone = newPath();
    cone.moveTo(77, 73);
    cone.lineTo(95, 63);
    cone.lineTo(95, 89);
    cone.lineTo(77, 79);
    cone.close();
    fillP(cone, cGold);
    strokeP(cone, cGoldDark, 1.6);
    oval(95, 76, 2.8, 13, 0xFFFFD34D);
    ovalS(95, 76, 2.8, 13, cGoldDark, 1.4);
    rrect(82, 79, 86, 88, 1.5, cGoldDark);
    arc(95, 76, 6.5, -0.6, 1.2, 0xFF2563EB, 1.8);
    arc(95, 76, 10.5, -0.6, 1.2, 0xFF2563EB, 1.8);
  }

  // Pencil tip position while writing three lines.
  void updatePen(double t) {
    double writeEnd = 0.78;
    double q = clamp01(t / writeEnd) * 3;
    penX = 61;
    penY = 99.5;
    for (int k = 0; k < 3; k++) {
      double y = 89.5 + 5.0 * k;
      double pk = clamp01(q - d(k));
      if (t < writeEnd && q >= d(k) && q < d(k) + 1) {
        penX = 39 + 22 * pk;
        penY = y + math.sin(t * 120) * 0.5;
      }
    }
    if (t >= writeEnd) {
      double lift = ease(clamp01((t - writeEnd) / 0.12));
      penX = 61 + 2 * lift;
      penY = 99.5 - 9 * lift;
    }
  }

  void drawClipboard(double t) {
    rrect(32, 80, 68, 108, 3.5, 0xFFC98A3D);
    rrectS(32, 80, 68, 108, 3.5, 0xFF8C5A22, 1.4);
    rrect(35.5, 84, 64.5, 105, 1.5, cWhite);
    rrect(44, 78, 56, 84, 1.5, 0xFF94A3B8);
    rrectS(44, 78, 56, 84, 1.5, 0xFF64748B, 1);

    double writeEnd = 0.78;
    double q = clamp01(t / writeEnd) * 3;
    for (int k = 0; k < 3; k++) {
      double y = 89.5 + 5.0 * k;
      double pk = clamp01(q - d(k));
      seg(39, y, 61, y, 0xFFE2E8F0, 1.6);
      if (pk > 0) {
        seg(39, y, 39 + 22 * pk, y, 0xFF2563EB, 1.8);
      }
    }

    // Green check pops in when the report is done.
    if (t >= writeEnd) {
      double pop = clamp01((t - writeEnd) / 0.1);
      double shrink = clamp01((1 - t) / 0.05);
      double over = 1 + 0.25 * math.sin(pop * math.pi);
      double r = 5.8 * pop * over * shrink;
      if (r > 0.2) {
        circle(35, 81, r + 1.2, cWhite);
        circle(35, 81, r, 0xFF1E9E55);
        Path tick = newPath();
        tick.moveTo(35 - r * 0.45, 81);
        tick.lineTo(35 - r * 0.1, 81 + r * 0.38);
        tick.lineTo(35 + r * 0.5, 81 - r * 0.35);
        strokeP(tick, cWhite, 1.6);
      }
    }
  }

  void drawPencil(double px, double py) {
    save();
    translate(px, py);
    rotate(-math.pi / 4);
    Path wood = newPath();
    wood.moveTo(0, 0);
    wood.lineTo(3.4, -1.9);
    wood.lineTo(3.4, 1.9);
    wood.close();
    fillP(wood, 0xFFF2C893);
    Path lead = newPath();
    lead.moveTo(0, 0);
    lead.lineTo(1.3, -0.75);
    lead.lineTo(1.3, 0.75);
    lead.close();
    fillP(lead, 0xFF1F2937);
    rrect(3.4, -1.9, 19.5, 1.9, 0.4, cGold);
    rrectS(0, -1.9, 22.6, 1.9, 0.8, 0xFFB07A00, 0.8);
    rrect(19.5, -1.9, 20.5, 1.9, 0.2, 0xFF94A3B8);
    rrect(20.5, -1.9, 22.6, 1.9, 0.8, 0xFFF28B9A);
    restore();
  }

  void drawBell(double cx, double cy) {
    arc(cx, cy, 12.5, -2.75, 0.7, cGoldDark, 1.8);
    arc(cx, cy, 16, -2.7, 0.6, cGoldDark, 1.6);
    arc(cx, cy, 12.5, -1.1, 0.7, cGoldDark, 1.8);
    arc(cx, cy, 16, -1.05, 0.6, cGoldDark, 1.6);
    save();
    translate(cx, cy + 6);
    rotate(-0.28);
    translate(-cx, -cy - 6);
    circle(cx, cy + 9.5, 2.3, cGoldDark);
    Path b = newPath();
    b.moveTo(cx - 7, cy + 5);
    b.quadraticBezierTo(cx - 7, cy - 8, cx, cy - 8);
    b.quadraticBezierTo(cx + 7, cy - 8, cx + 7, cy + 5);
    b.lineTo(cx + 9, cy + 7.5);
    b.lineTo(cx - 9, cy + 7.5);
    b.close();
    fillP(b, cGold);
    strokeP(b, cGoldDark, 1.5);
    circle(cx, cy - 9, 1.8, cGoldDark);
    oval(cx - 3, cy - 2, 1.4, 3.2, fade(cWhite, 0.55));
    restore();
    circle(cx + 7, cy - 7, 3.6, 0xFFEF4444);
    circleS(cx + 7, cy - 7, 3.6, cWhite, 1.3);
  }

  void drawGear(double cx, double cy) {
    save();
    translate(cx, cy);
    for (int i = 0; i < 8; i++) {
      save();
      rotate(d(i) * math.pi / 4);
      rrectS(-2.3, -11.2, 2.3, -6, 1, 0xFF475569, 2.8);
      restore();
    }
    circleS(0, 0, 8.4, 0xFF475569, 2.8);
    for (int i = 0; i < 8; i++) {
      save();
      rotate(d(i) * math.pi / 4);
      rrect(-2.3, -11.2, 2.3, -6, 1, 0xFFA7B4C6);
      restore();
    }
    circle(0, 0, 8.4, 0xFFA7B4C6);
    circle(0, 0, 3.2, cWhite);
    circleS(0, 0, 3.2, 0xFF475569, 1.4);
    restore();
  }

  void drawPhone(double dy, double flash) {
    rrect(82, 30 + dy, 100, 60 + dy, 3.5, 0xFF1E293B);
    rrectS(82, 30 + dy, 100, 60 + dy, 3.5, 0xFF0F172A, 1.4);
    rrect(84.5, 33 + dy, 91.5, 45.5 + dy, 2.5, 0xFF334155);
    circle(88, 36.6 + dy, 2.3, 0xFF0B1220);
    circleS(88, 36.6 + dy, 2.3, 0xFF64748B, 0.8);
    circle(88, 41.8 + dy, 2.3, 0xFF0B1220);
    circleS(88, 41.8 + dy, 2.3, 0xFF64748B, 0.8);
    circle(88.7, 35.9 + dy, 0.7, 0xFF93C5FD);
    circle(88.7, 41.1 + dy, 0.7, 0xFF93C5FD);
    circle(96, 35 + dy, 1.3, 0xFFFDE68A);

    if (flash > 0) {
      double fx = 96;
      double fy = 35 + dy;
      circle(fx, fy, 3 + 10 * flash, fade(0xFFFFF7D6, 0.55 * flash));
      circle(fx, fy, 2 + 4 * flash, fade(cWhite, flash));
      for (int i = 0; i < 8; i++) {
        double a = d(i) * math.pi / 4;
        double r1 = 5 + 3 * flash;
        double r2 = 5 + 9 * flash;
        seg(fx + r1 * math.cos(a), fy + r1 * math.sin(a), fx + r2 * math.cos(a),
            fy + r2 * math.sin(a), fade(0xFFFFD34D, flash), 1.4);
      }
    }
  }

  // ============================================================
  // EASING
  // ============================================================
  double envelope(double t) {
    if (t <= 0 || t >= 1) {
      return 0;
    }
    if (t < 0.12) {
      return ease(t / 0.12);
    }
    if (t > 0.86) {
      return ease((1 - t) / 0.14);
    }
    return 1;
  }

  double ease(double x) {
    double v = clamp01(x);
    return v * v * (3 - 2 * v);
  }

  double lerp(double a, double b, double k) {
    return a + (b - a) * k;
  }

  double clamp01(double x) {
    if (x < 0) {
      return 0;
    }
    if (x > 1) {
      return 1;
    }
    return x;
  }
  // ===== DRAWING (END) =====

  // ---------- canvas helpers (Dart only) ----------
  double d(int i) => i.toDouble();

  int mix(int a, int b, double k) {
    final Color c = Color.lerp(Color(a), Color(b), k)!;
    return c.toARGB32();
  }

  void scale2(double x, double y) => _c.scale(x, y);

  int fade(int color, double a) {
    final int alpha = (((color >> 24) & 0xFF) * a).round().clamp(0, 255).toInt();
    return (alpha << 24) | (color & 0x00FFFFFF);
  }

  Path newPath() => Path();

  Paint _fill(int color) => Paint()
    ..color = Color(color)
    ..isAntiAlias = true;

  Paint _stroke(int color, double w) => Paint()
    ..color = Color(color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  void fillP(Path p, int color) => _c.drawPath(p, _fill(color));

  void fillPV(Path p, int c1, int c2, double y1, double y2) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(c1), Color(c2)],
      ).createShader(Rect.fromLTRB(0, y1, _w, y2));
    _c.drawPath(p, paint);
  }

  void strokeP(Path p, int color, double w) =>
      _c.drawPath(p, _stroke(color, w));

  void circle(double x, double y, double r, int color) =>
      _c.drawCircle(Offset(x, y), r, _fill(color));

  void circleS(double x, double y, double r, int color, double w) =>
      _c.drawCircle(Offset(x, y), r, _stroke(color, w));

  void oval(double x, double y, double rx, double ry, int color) =>
      _c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
        _fill(color),
      );

  void ovalS(double x, double y, double rx, double ry, int color, double w) =>
      _c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
        _stroke(color, w),
      );

  void rrect(double l, double t, double r, double b, double rad, int color) =>
      _c.drawRRect(
        RRect.fromLTRBR(l, t, r, b, Radius.circular(rad)),
        _fill(color),
      );

  void rrectS(
    double l,
    double t,
    double r,
    double b,
    double rad,
    int color,
    double w,
  ) => _c.drawRRect(
    RRect.fromLTRBR(l, t, r, b, Radius.circular(rad)),
    _stroke(color, w),
  );

  void seg(
    double x1,
    double y1,
    double x2,
    double y2,
    int color,
    double w,
  ) => _c.drawLine(Offset(x1, y1), Offset(x2, y2), _stroke(color, w));

  void arc(
    double cx,
    double cy,
    double r,
    double start,
    double sweep,
    int color,
    double w,
  ) => _c.drawArc(
    Rect.fromCircle(center: Offset(cx, cy), radius: r),
    start,
    sweep,
    false,
    _stroke(color, w),
  );

  void clipCircle(double cx, double cy, double r) => _c.clipPath(
    Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
  );

  void clipRect(double l, double t, double r, double b) =>
      _c.clipRect(Rect.fromLTRB(l, t, r, b));

  void save() => _c.save();
  void restore() => _c.restore();
  void translate(double x, double y) => _c.translate(x, y);
  void rotate(double a) => _c.rotate(a);
}
