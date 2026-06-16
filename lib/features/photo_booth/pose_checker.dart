import 'pipeline.dart';

class PoseCheckResult {
  final bool bodyDetected;
  final bool fullBodyVisible;
  final bool centered;
  final bool upright;
  final bool armsDown;
  final double centerOffset;
  final double bodyHeightFraction;

  const PoseCheckResult({
    this.bodyDetected = false,
    this.fullBodyVisible = false,
    this.centered = false,
    this.upright = false,
    this.armsDown = false,
    this.centerOffset = 1.0,
    this.bodyHeightFraction = 0,
  });

  bool get allGood => bodyDetected && fullBodyVisible && centered && upright && armsDown;
}

class PoseChecker {
  /// Validate body pose in the frame.
  /// All coordinates are in image pixels (un-mirrored).
  PoseCheckResult check({
    required int frameW,
    required int frameH,
    required BodyData body,
    bool isMirrored = false,
    double centerThreshold = 0.15,
    double minBodyHeight = 0.4,
    double maxBodyHeight = 0.9,
  }) {
    if (!body.detected) return const PoseCheckResult();

    final frameCx = frameW / 2;
    final bodyCx = (body.leftShoulderX + body.rightShoulderX) / 2;

    final offsetX = (bodyCx - frameCx) / frameW;
    final centered = offsetX.abs() < centerThreshold;

    final shoulderY = body.midShoulderY;
    final ankleY = body.midAnkleY;
    final bodyHeight = (ankleY - shoulderY).abs();
    final bodyHeightFraction = bodyHeight / frameH;

    final fullBodyVisible =
        bodyHeightFraction >= minBodyHeight && bodyHeightFraction <= maxBodyHeight &&
        shoulderY > 0 && ankleY > shoulderY &&
        body.leftKneeY > 0 && body.rightKneeY > 0;

    // Check if upright (shoulders above hips above knees above ankles)
    final upright = shoulderY < body.midHipY &&
        body.midHipY < body.midKneeY &&
        body.midKneeY < body.midAnkleY;

    // Arms should be at sides (wrists below hips or at hip level)
    final armsDown = body.leftWristY >= body.leftHipY - 20 ||
        body.rightWristY >= body.rightHipY - 20;

    return PoseCheckResult(
      bodyDetected: true,
      fullBodyVisible: fullBodyVisible,
      centered: centered,
      upright: upright,
      armsDown: armsDown,
      centerOffset: offsetX.abs(),
      bodyHeightFraction: bodyHeightFraction,
    );
  }
}
