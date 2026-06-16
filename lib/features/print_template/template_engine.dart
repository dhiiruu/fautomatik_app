import 'dart:typed_data';
import 'package:image/image.dart' as img;

const _mmPerInch = 25.4;
const _minMarginMm = 3.0;

class TemplateConfig {
  final double paperWidthMm;
  final double paperHeightMm;
  final double dpi;
  final double photoWidthMm;
  final double photoHeightMm;
  final double spacingMm;
  final double marginTopMm;
  final double marginBottomMm;
  final double marginLeftMm;
  final double marginRightMm;
  final int backgroundColor;
  final bool cropMarks;
  final int cropMarkColor;
  final double cropMarkLengthMm;

  const TemplateConfig({
    required this.paperWidthMm,
    required this.paperHeightMm,
    this.dpi = 300,
    required this.photoWidthMm,
    required this.photoHeightMm,
    this.spacingMm = 3,
    this.marginTopMm = 10,
    this.marginBottomMm = 10,
    this.marginLeftMm = 10,
    this.marginRightMm = 10,
    this.backgroundColor = 0xFFFFFFFF,
    this.cropMarks = false,
    this.cropMarkColor = 0xFF000000,
    this.cropMarkLengthMm = 5,
  });

  int get paperW => (paperWidthMm * dpi / _mmPerInch).round();
  int get paperH => (paperHeightMm * dpi / _mmPerInch).round();
  int get photoW => (photoWidthMm * dpi / _mmPerInch).round();
  int get photoH => (photoHeightMm * dpi / _mmPerInch).round();
  int get spacing => (spacingMm * dpi / _mmPerInch).round();
  int get marginTop => (marginTopMm * dpi / _mmPerInch).round();
  int get marginBottom => (marginBottomMm * dpi / _mmPerInch).round();
  int get marginLeft => (marginLeftMm * dpi / _mmPerInch).round();
  int get marginRight => (marginRightMm * dpi / _mmPerInch).round();
  int get cropMarkLen => (cropMarkLengthMm * dpi / _mmPerInch).round();
}

class PhotoSlot {
  final int page;
  final int index;
  final int x;
  final int y;
  final int width;
  final int height;

  const PhotoSlot({
    required this.page,
    required this.index,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class TemplateResult {
  final List<Uint8List> pages;
  final List<PhotoSlot> slots;
  final int totalPlaced;

  const TemplateResult({
    required this.pages,
    required this.slots,
    required this.totalPlaced,
  });

  int get totalPages => pages.length;
}

class TemplateEngine {
  TemplateResult place({
    required List<Uint8List> photos,
    required TemplateConfig config,
  }) {
    final safe = _clampMargins(config);
    final pw = safe.paperW;
    final ph = safe.paperH;
    final ptW = safe.photoW;
    final ptH = safe.photoH;
    final sp = safe.spacing;
    final mL = safe.marginLeft;
    final mT = safe.marginTop;
    final mR = safe.marginRight;
    final mB = safe.marginBottom;

    final cellW = ptW + sp;
    final cellH = ptH + sp;
    final availW = pw - mL - mR + sp;
    final availH = ph - mT - mB + sp;
    final cols = availW ~/ cellW;
    final rows = availH ~/ cellH;

    if (cols <= 0 || rows <= 0) {
      return const TemplateResult(pages: [], slots: [], totalPlaced: 0);
    }

    final perPage = cols * rows;
    final totalPages = (photos.length + perPage - 1) ~/ perPage;
    final pages = <Uint8List>[];
    final slots = <PhotoSlot>[];

    final bgR = (safe.backgroundColor >> 16) & 0xFF;
    final bgG = (safe.backgroundColor >> 8) & 0xFF;
    final bgB = safe.backgroundColor & 0xFF;
    final bgColor = img.ColorRgb8(bgR, bgG, bgB);

    final cmR = (safe.cropMarkColor >> 16) & 0xFF;
    final cmG = (safe.cropMarkColor >> 8) & 0xFF;
    final cmB = safe.cropMarkColor & 0xFF;

    for (var page = 0; page < totalPages; page++) {
      final canvas = img.Image.fromBytes(
        width: pw,
        height: ph,
        bytes: Uint8List(pw * ph * 4).buffer,
        numChannels: 4,
      );
      canvas.clear(bgColor);

      final start = page * perPage;
      final end = (start + perPage).clamp(0, photos.length);

      for (var i = start; i < end; i++) {
        final localIdx = i - start;
        final col = localIdx % cols;
        final row = localIdx ~/ cols;
        final slotX = mL + col * cellW;
        final slotY = mT + row * cellH;

        final photo = img.decodeImage(photos[i]);
        if (photo == null) continue;

        final scaled = img.copyResize(
          photo,
          width: ptW,
          height: ptH,
          maintainAspect: true,
          backgroundColor: bgColor,
          interpolation: img.Interpolation.linear,
        );

        final offsetX = slotX + (ptW - scaled.width) ~/ 2;
        final offsetY = slotY + (ptH - scaled.height) ~/ 2;

        for (var y = 0; y < scaled.height; y++) {
          for (var x = 0; x < scaled.width; x++) {
            canvas.setPixel(offsetX + x, offsetY + y, scaled.getPixel(x, y));
          }
        }

        if (safe.cropMarks) {
          _drawCropMarks(canvas, slotX, slotY, ptW, ptH, safe.cropMarkLen, cmR, cmG, cmB, bgR, bgG, bgB);
        }

        slots.add(PhotoSlot(
          page: page,
          index: i,
          x: offsetX,
          y: offsetY,
          width: scaled.width,
          height: scaled.height,
        ));
      }

      pages.add(img.encodePng(canvas));
    }

    return TemplateResult(
      pages: pages,
      slots: slots,
      totalPlaced: photos.length,
    );
  }

  TemplateConfig _clampMargins(TemplateConfig c) {
    double clamp(double v) => v < _minMarginMm ? _minMarginMm : v;
    if (c.marginTopMm >= _minMarginMm &&
        c.marginBottomMm >= _minMarginMm &&
        c.marginLeftMm >= _minMarginMm &&
        c.marginRightMm >= _minMarginMm) {
      return c;
    }
    return TemplateConfig(
      paperWidthMm: c.paperWidthMm,
      paperHeightMm: c.paperHeightMm,
      dpi: c.dpi,
      photoWidthMm: c.photoWidthMm,
      photoHeightMm: c.photoHeightMm,
      spacingMm: c.spacingMm,
      marginTopMm: clamp(c.marginTopMm),
      marginBottomMm: clamp(c.marginBottomMm),
      marginLeftMm: clamp(c.marginLeftMm),
      marginRightMm: clamp(c.marginRightMm),
      backgroundColor: c.backgroundColor,
      cropMarks: c.cropMarks,
      cropMarkColor: c.cropMarkColor,
      cropMarkLengthMm: c.cropMarkLengthMm,
    );
  }

  void _drawCropMarks(
    img.Image canvas,
    int x, int y,
    int w, int h,
    int len,
    int cr, int cg, int cb,
    int bgR, int bgG, int bgB,
  ) {
    void drawHLine(int x1, int x2, int yy) {
      for (var xx = x1; xx <= x2; xx++) {
        final p = canvas.getPixel(xx, yy);
        if (p.r == bgR && p.g == bgG && p.b == bgB) {
          canvas.setPixel(xx, yy, img.ColorRgb8(cr, cg, cb));
        }
      }
    }

    void drawVLine(int y1, int y2, int xx) {
      for (var yy = y1; yy <= y2; yy++) {
        final p = canvas.getPixel(xx, yy);
        if (p.r == bgR && p.g == bgG && p.b == bgB) {
          canvas.setPixel(xx, yy, img.ColorRgb8(cr, cg, cb));
        }
      }
    }

    // Top-left corner
    drawHLine(x - len, x, y);
    drawVLine(y - len, y, x);
    // Top-right corner
    drawHLine(x + w, x + w + len, y);
    drawVLine(y - len, y, x + w);
    // Bottom-left corner
    drawHLine(x - len, x, y + h);
    drawVLine(y + h, y + h + len, x);
    // Bottom-right corner
    drawHLine(x + w, x + w + len, y + h);
    drawVLine(y + h, y + h + len, x + w);
  }
}
