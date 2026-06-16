import 'dart:typed_data';
import 'package:pdf/pdf.dart' as pw;
import 'package:image/image.dart' as img;
import 'template_engine.dart';

class PdfExporter {
  Future<Uint8List> export({
    required TemplateResult templateResult,
    required TemplateConfig config,
  }) async {
    final doc = pw.PdfDocument();
    final pageW = config.paperWidthMm * pw.PdfPageFormat.mm;
    final pageH = config.paperHeightMm * pw.PdfPageFormat.mm;

    for (final pagePng in templateResult.pages) {
      final image = img.decodeImage(pagePng);
      if (image == null) continue;

      final pdfImage = pw.PdfImage.fromImage(doc, image: image);
      final page = pw.PdfPage(
        doc,
        pageFormat: pw.PdfPageFormat(pageW, pageH, marginAll: 0),
      );
      final gfx = page.getGraphics();
      gfx.drawImage(pdfImage, 0, pageH, pageW, -pageH);
    }

    return doc.save();
  }
}
