// Magic Portrait re-exports all operations from individual feature process
// files so callers can compose them manually. The standard orchestration is
// driven by EditConfig via edit/pipeline.dart and editor.dart.

export '../auto_crop/process.dart' show autoCrop;
export '../../shared/encoding/image_encoder.dart' show encodeOutput;
export '../straighten/process.dart' show headTiltAngle, rotateStraight, cropTransparent;
export '../auto_lighting/process.dart' show applyLighting, autoLevels, stretch;
export '../sharpen/process.dart' show sharpenImage;
export '../skin_smooth/process.dart' show skinSmooth, isSkinColor;
export '../red_eye_fix/process.dart' show fixRedEye;
export '../resize/process.dart' show resizeImage;
export '../border/process.dart' show addBorder;
export '../remove_bg/process.dart' show replaceBackground;
