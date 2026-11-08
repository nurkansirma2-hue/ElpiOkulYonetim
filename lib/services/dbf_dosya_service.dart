import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dbf_pdf_okuyucu.dart';

import '../models/dbf_belgesi.dart';
import 'dbf_rar_okuyucu.dart';

class DbfDosyaService {
  static Future<DbfBelgesi?> sec(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'rar'],
      withData: false,
      withReadStream: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size <= 0 || file.size > DbfRarOkuyucu.azamiPdf) {
      throw const FormatException('Dosya boş veya 20 MB sınırından büyük.');
    }
    final source =
        file.readStream ??
        (file.path == null ? null : File(file.path!).openRead());
    if (source == null) throw const FormatException('Dosya okunamadı.');
    final data = BytesBuilder(copy: false);
    await for (final chunk in source) {
      if (data.length + chunk.length > DbfRarOkuyucu.azamiPdf) {
        throw const FormatException('Dosya 20 MB sınırını aşıyor.');
      }
      data.add(chunk);
    }
    if (data.length != file.size) {
      throw const FormatException('Dosya tam okunamadı.');
    }
    var bytes = data.takeBytes();
    var ad = file.name;
    if (p.extension(ad).toLowerCase() == '.rar') {
      final root = await getTemporaryDirectory();
      final klasor = await Directory(
        p.join(root.path, 'dbf_import'),
      ).create(recursive: true);
      final tmp = await klasor.createTemp('secim_');
      try {
        final rar = File(p.join(tmp.path, 'kaynak.rar'));
        await rar.writeAsBytes(bytes, flush: true);
        final adaylar = await DbfRarOkuyucu.listele(rar.path);
        if (adaylar.isEmpty) {
          throw const FormatException('RAR içinde PDF bulunamadı.');
        }
        if (!context.mounted) return null;
        final secim = await showDialog<DbfRarDosyasi>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('DBF PDF’sini seçin'),
            children: [
              for (final aday in adaylar)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, aday),
                  child: Text(aday.ad),
                ),
            ],
          ),
        );
        if (secim == null) return null;
        bytes = await DbfRarOkuyucu.oku(rar.path, secim);
        ad = p.posix.basename(secim.ad.replaceAll('\\', '/'));
      } finally {
        if (p.isWithin(root.path, tmp.path) &&
            p.basename(tmp.path).startsWith('secim_')) {
          await tmp.delete(recursive: true);
        }
      }
    }
    return pdfOku(ad, bytes);
  }

  static Future<DbfBelgesi> pdfOku(
    String ad,
    Uint8List bytes, {
    Future<void> Function()? hazirla,
  }) async {
    if (bytes.length < 5 ||
        bytes.length > DbfRarOkuyucu.azamiPdf ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException(
        'Geçerli, en fazla 20 MB boyutunda PDF seçin.',
      );
    }
    await hazirla?.call();
    final pages = DbfPdfOkuyucu.oku(bytes);
    return DbfBelgesi.metinden(
      dosyaAdi: ad, sayfalar: pages,
      icerikOzeti: 'crc32:${getCrc32(bytes).toRadixString(16).padLeft(8, '0')}',
      pdfBytes: bytes,
    );
  }
}
