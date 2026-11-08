import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Yalnız yerelde kayıtlı fotoğraf okunur; ağ adresi indirilmez.
Future<Map<String, String>?> ogretmenGorusFotografi(
  Map<String, Object?> o,
) async {
  Uint8List? bytes;
  final blob = o['FotoVerisi'];
  if (blob is List<int> && blob.isNotEmpty) {
    bytes = Uint8List.fromList(blob);
  } else {
    final yol = '${o['DosyaYolu'] ?? ''}'.trim();
    if (yol.isEmpty) return null;
    if (Uri.tryParse(yol)?.hasScheme == true &&
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(yol)) {
      throw const FormatException(
        'Öğrenci fotoğrafı yerel bir dosya olmalıdır.',
      );
    }
    final file = File(yol);
    if (!await file.exists()) return null;
    if (await file.length() > 10 * 1024 * 1024) {
      throw const FormatException('Öğrenci fotoğrafı çok büyük.');
    }
    bytes = await file.readAsBytes();
  }
  if (bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Öğrenci fotoğrafı çok büyük.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 40000000) {
      throw const FormatException(
        'Öğrenci fotoğrafının çözünürlüğü çok yüksek.',
      );
    }
    for (final kenar in [240, 160, 100]) {
      final oran = math.min(
        1.0,
        kenar / math.max(descriptor.width, descriptor.height),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * oran).round()),
        targetHeight: math.max(1, (descriptor.height * oran).round()),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data != null && data.lengthInBytes <= 102400) {
            return {
              'mime': 'image/png',
              'base64': base64Encode(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              ),
            };
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    throw const FormatException('Öğrenci fotoğrafı form için küçültülemedi.');
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}
