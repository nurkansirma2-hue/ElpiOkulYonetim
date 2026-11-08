import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

class DbfRarDosyasi {
  const DbfRarDosyasi(this.sira, this.ad);
  final int sira;
  final String ad;
}

/// Arşiv girdileri diske açılmaz. Android'de onaylı rar paketinin sağladığı
/// libarchive okuyucusu; Windows'ta sistemin tar okuyucusu kullanılır.
class DbfRarOkuyucu {
  static const azamiPdf = 20 * 1024 * 1024;
  static Future<List<DbfRarDosyasi>> listele(String yol) async {
    if (Platform.isWindows) {
      final metin = await _tar(['-tf', yol]);
      final adlar = const LineSplitter().convert(systemEncoding.decode(metin));
      if (adlar.length > 1000) {
        throw const FormatException('RAR en fazla 1000 girdi içerebilir.');
      }
      return [
        for (var i = 0; i < adlar.length; i++)
          if (adlar[i].toLowerCase().endsWith('.pdf'))
            DbfRarDosyasi(i, adlar[i]),
      ];
    }
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'RAR okuma Android ve Windows’ta destekleniyor. PDF’yi doğrudan seçebilirsiniz.',
      );
    }
    return Isolate.run(() => _native(yol, null).$1);
  }

  static Future<Uint8List> oku(String yol, DbfRarDosyasi dosya) async {
    if (Platform.isWindows) return _tar(['-xOf', yol, '--', dosya.ad]);
    return Isolate.run(() => _native(yol, dosya.sira).$2!);
  }

  static Future<Uint8List> _tar(List<String> args) async {
    final process = await Process.start('tar.exe', args, runInShell: false);
    final hata = process.stderr.transform(systemEncoding.decoder).join();
    final buffer = BytesBuilder(copy: false);
    try {
      await (() async {
        await for (final chunk in process.stdout) {
          if (buffer.length + chunk.length > azamiPdf) {
            throw const FormatException('Arşivdeki PDF 20 MB sınırını aşıyor.');
          }
          buffer.add(chunk);
        }
        final code = await process.exitCode;
        if (code != 0) throw FormatException('RAR okunamadı: ${await hata}');
      })().timeout(const Duration(seconds: 30));
      return buffer.takeBytes();
    } finally {
      process.kill();
    }
  }

  static (List<DbfRarDosyasi>, Uint8List?) _native(String yol, int? secili) {
    final lib = DynamicLibrary.open('librar_native.so');
    final libc = DynamicLibrary.open('libc.so');
    final malloc = libc
        .lookupFunction<
          Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)
        >('malloc');
    final free = libc
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final yeni = lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'archive_read_new',
        );
    final rar = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('archive_read_support_format_rar');
    final rar5 = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('archive_read_support_format_rar5');
    final ac = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, IntPtr),
          int Function(Pointer<Void>, Pointer<Uint8>, int)
        >('archive_read_open_filename');
    final sonraki = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
          int Function(Pointer<Void>, Pointer<Pointer<Void>>)
        >('archive_read_next_header');
    final isim = lib
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Void>),
          Pointer<Uint8> Function(Pointer<Void>)
        >('archive_entry_pathname');
    final boyut = lib
        .lookupFunction<
          Int64 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('archive_entry_size');
    final tur = lib
        .lookupFunction<
          Uint32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('archive_entry_filetype');
    final oku = lib
        .lookupFunction<
          IntPtr Function(Pointer<Void>, Pointer<Void>, IntPtr),
          int Function(Pointer<Void>, Pointer<Void>, int)
        >('archive_read_data');
    final atla = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('archive_read_data_skip');
    final kapat = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('archive_read_free');
    final pathBytes = utf8.encode(yol);
    final path = malloc(pathBytes.length + 1).cast<Uint8>();
    final entry = malloc(sizeOf<IntPtr>()).cast<Pointer<Void>>();
    final chunk = malloc(65536);
    final archive = yeni();
    if (path == nullptr ||
        entry == nullptr ||
        chunk == nullptr ||
        archive == nullptr) {
      if (path != nullptr) free(path.cast());
      if (entry != nullptr) free(entry.cast());
      if (chunk != nullptr) free(chunk);
      if (archive != nullptr) kapat(archive);
      throw StateError('RAR okuyucusu için bellek ayrılamadı.');
    }
    try {
      path.asTypedList(pathBytes.length + 1)
        ..setAll(0, pathBytes)
        ..[pathBytes.length] = 0;
      rar(archive);
      rar5(archive);
      if (ac(archive, path, 65536) != 0) {
        throw const FormatException(
          'RAR açılamadı; şifreli veya bozuk olabilir.',
        );
      }
      final sonuc = <DbfRarDosyasi>[];
      var sira = 0, toplam = 0;
      while (true) {
        final status = sonraki(archive, entry);
        if (status == 1) break;
        if (status != 0 || sira >= 1000) {
          throw const FormatException(
            'RAR girdi sınırı aşıldı veya başlık okunamadı.',
          );
        }
        final size = boyut(entry.value);
        toplam += size < 0 ? 0 : size;
        if (size < 0 || toplam > 100 * 1024 * 1024) {
          throw const FormatException(
            'RAR açılmış boyutu 100 MB sınırını aşıyor.',
          );
        }
        final namePtr = isim(entry.value);
        if (namePtr == nullptr) {
          throw const FormatException('RAR dosya adı okunamadı.');
        }
        final nameBytes = <int>[];
        for (var i = 0; i < 4096 && namePtr[i] != 0; i++) {
          nameBytes.add(namePtr[i]);
        }
        if (nameBytes.length == 4096) {
          throw const FormatException('RAR dosya adı çok uzun.');
        }
        String name;
        try {
          name = utf8.decode(nameBytes);
        } catch (_) {
          const tr = {
            208: 'Ğ',
            221: 'İ',
            222: 'Ş',
            240: 'ğ',
            253: 'ı',
            254: 'ş',
          };
          name = nameBytes.map((b) => tr[b] ?? String.fromCharCode(b)).join();
        }
        final pdf =
            tur(entry.value) == 0x8000 && name.toLowerCase().endsWith('.pdf');
        if (pdf) {
          if (size > azamiPdf) {
            throw const FormatException(
              'RAR içindeki PDF 20 MB sınırını aşıyor.',
            );
          }
          sonuc.add(DbfRarDosyasi(sira, name));
          if (secili == sira) {
            final data = BytesBuilder(copy: false);
            while (true) {
              final n = oku(archive, chunk, 65536);
              if (n == 0) break;
              if (n < 0 || data.length + n > azamiPdf) {
                throw const FormatException(
                  'RAR içeriği bozuk veya boyut sınırını aşıyor.',
                );
              }
              data.add(Uint8List.fromList(chunk.cast<Uint8>().asTypedList(n)));
            }
            if (data.length != size) {
              throw const FormatException('PDF tam okunamadı.');
            }
            return (sonuc, data.takeBytes());
          }
        }
        if (atla(archive) != 0) {
          throw const FormatException('RAR verisi atlanamadı.');
        }
        sira++;
      }
      if (secili != null) {
        throw const FormatException('Seçilen PDF arşivde bulunamadı.');
      }
      return (sonuc, null);
    } finally {
      kapat(archive);
      free(path.cast());
      free(entry.cast());
      free(chunk);
    }
  }
}
