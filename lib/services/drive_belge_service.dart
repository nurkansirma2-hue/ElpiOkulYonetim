import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/ortak_import.dart';
import '../models/import_ilerleme.dart';

/// Yalnız kullanıcının Google Picker ile izin verdiği dosyayı okur.
/// Drive'a, SQLite'a ve yerel ayarlara yazma işlemi içermez.
class DriveBelgeService {
  DriveBelgeService({http.Client? client})
    : _client = client ?? http.Client(),
      _sahibi = client == null;
  final http.Client _client;
  final bool _sahibi;
  static const azamiBoyut = 50 * 1024 * 1024;
  static const _channel = MethodChannel('elpi_okul_yonetim/drive_belge');
  static const _mime = {
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'pdf': 'application/pdf',
    'csv': 'text/csv',
    'txt': 'text/plain',
  };
  static const _googleDoc = 'application/vnd.google-apps.document';
  static const _googleSheet = 'application/vnd.google-apps.spreadsheet';

  Future<ImportDosya?> sec(
    Set<String> uzantilar, {
    Future<void> Function(String hesap)? hesapSecildi,
    void Function(ImportIlerleme)? ilerleme,
  }) async {
    final mime = [
      for (final e in uzantilar)
        if (_mime[e] != null) _mime[e]!,
      if (uzantilar.contains('docx')) _googleDoc,
      if (uzantilar.contains('xlsx')) _googleSheet,
    ];
    final result = await _channel.invokeMapMethod<String, dynamic>('sec', {
      'mimeTurleri': mime,
    });
    if (result == null) return null;
    ilerleme?.call(const ImportIlerleme('Drive dosya bilgileri alınıyor…'));
    final dosya = await indir(
      token: result['token'] as String,
      dosyaId: result['dosyaId'] as String,
      uzantilar: uzantilar,
      ilerleme: ilerleme,
    );
    final hesap = result['hesap'];
    if (hesap is String && hesap.contains('@') && hesap.length <= 320) {
      await hesapSecildi?.call(hesap);
    }
    return dosya;
  }

  /// Yeni izin veya hesap seçme ekranı açmaz. İzin yenilenmeli ise null döner.
  Future<String?> erisim(String hesap) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('erisim', {
      'hesap': hesap,
    });
    return result?['token'] as String?;
  }

  /// drive.file kapsamında önceden izin verilmiş Office/Google belgeleri.
  /// İçerik indirmez; en fazla üç sayfa tarar. Devamı manuel seçilebilir.
  Future<List<Map<String, dynamic>>> adaylariListele(String token) async {
    final mime = [
      _mime['xls']!,
      _mime['xlsx']!,
      _mime['docx']!,
      _googleDoc,
      _googleSheet,
    ];
    final sonuc = <Map<String, dynamic>>[];
    String? sayfa;
    for (var i = 0; i < 3; i++) {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "trashed = false and (${mime.map((m) => "mimeType = '$m'").join(' or ')})",
        'pageSize': '100',
        'orderBy': 'modifiedTime desc',
        'fields':
            'nextPageToken,files(id,name,mimeType,size,version,capabilities(canDownload))',
        if (sayfa != null) 'pageToken': sayfa,
      });
      final data =
          jsonDecode(utf8.decode(await _oku(uri, token, 1024 * 1024)))
              as Map<String, dynamic>;
      sonuc.addAll(
        (data['files'] as List? ?? []).map(
          (r) => Map<String, dynamic>.from(r as Map),
        ),
      );
      sayfa = data['nextPageToken'] as String?;
      if (sayfa == null || sayfa.isEmpty) break;
    }
    return sonuc;
  }

  Future<Uint8List> _oku(
    Uri uri,
    String token,
    int limit, {
    void Function(ImportIlerleme)? ilerleme,
  }) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['Authorization'] = 'Bearer $token';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw StateError(
        'Drive dosyası okunamadı (HTTP ${response.statusCode}). '
        'Erişim iznini ve internet bağlantısını kontrol edin.',
      );
    }
    if ((response.contentLength ?? 0) > limit) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException('Drive dosyası boyut sınırını aşıyor.');
    }
    final builder = BytesBuilder(copy: false);
    await (() async {
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > limit) {
          throw const FormatException('Drive dosyası boyut sınırını aşıyor.');
        }
        builder.add(chunk);
        ilerleme?.call(
          ImportIlerleme(
            'Google Drive dosyası indiriliyor…',
            tamamlanan: builder.length,
            toplam: response.contentLength,
          ),
        );
      }
    })().timeout(const Duration(seconds: 60));
    if (response.contentLength != null &&
        builder.length != response.contentLength) {
      throw const FormatException(
        'Drive dosyası tam indirilemedi. Yeniden seçin.',
      );
    }
    return builder.takeBytes();
  }

  Future<ImportDosya> indir({
    required String token,
    required String dosyaId,
    required Set<String> uzantilar,
    String? beklenenSurum,
    int boyutSiniri = azamiBoyut,
    void Function(ImportIlerleme)? ilerleme,
  }) async {
    if (token.trim().isEmpty ||
        token.contains(RegExp(r'[\r\n]')) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,256}$').hasMatch(dosyaId)) {
      throw StateError('Google dosya yetkilendirmesi geçersiz. Yeniden seçin.');
    }
    final metaUri =
        Uri.https('www.googleapis.com', '/drive/v3/files/$dosyaId', {
          'fields':
              'id,name,mimeType,size,version,trashed,capabilities(canDownload)',
          'supportsAllDrives': 'true',
        });
    Future<Map<String, dynamic>> metadata() async =>
        jsonDecode(utf8.decode(await _oku(metaUri, token, 1024 * 1024)))
            as Map<String, dynamic>;
    final meta = await metadata();
    if (beklenenSurum != null && meta['version'] != beklenenSurum) {
      throw StateError('Drive belgesi aramadan sonra değişti. Yeniden arayın.');
    }
    if (meta['id'] != dosyaId ||
        meta['trashed'] == true ||
        (meta['capabilities'] as Map?)?['canDownload'] != true ||
        meta['version'] == null) {
      throw StateError(
        'Bu Drive dosyası indirilemiyor veya artık kullanılamıyor.',
      );
    }
    var ad = (meta['name'] as String).replaceAll('\\', '/').split('/').last;
    final mime = meta['mimeType'];
    String? export;
    if (mime == _googleDoc && uzantilar.contains('docx')) {
      export = _mime['docx'];
      if (!ad.toLowerCase().endsWith('.docx')) ad += '.docx';
    } else if (mime == _googleSheet && uzantilar.contains('xlsx')) {
      export = _mime['xlsx'];
      if (!ad.toLowerCase().endsWith('.xlsx')) ad += '.xlsx';
    }
    final ext = ad.split('.').last.toLowerCase();
    if (!uzantilar.contains(ext) || (export == null && _mime[ext] != mime)) {
      throw const FormatException(
        'Seçilen Drive dosyasının türü bu işlemde desteklenmiyor.',
      );
    }
    final boyut = int.tryParse('${meta['size']}');
    if (boyutSiniri <= 0 ||
        boyutSiniri > azamiBoyut ||
        (boyut != null && (boyut <= 0 || boyut > boyutSiniri))) {
      throw const FormatException(
        'Dosya boş veya indirme boyut sınırından büyük.',
      );
    }
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/$dosyaId${export == null ? '' : '/export'}',
      export == null
          ? {'alt': 'media', 'supportsAllDrives': 'true'}
          : {'mimeType': export},
    );
    ilerleme?.call(ImportIlerleme('$ad indiriliyor…'));
    final bytes = await _oku(uri, token, boyutSiniri, ilerleme: ilerleme);
    if (bytes.isEmpty ||
        (export == null && boyut != null && bytes.length != boyut)) {
      throw const FormatException('Drive dosyası boş veya tam indirilemedi.');
    }
    ilerleme?.call(
      const ImportIlerleme(
        'İndirme tamamlandı; dosyanın değişmediği doğrulanıyor…',
      ),
    );
    final son = await metadata();
    if (son['version'] != meta['version'] ||
        son['trashed'] == true ||
        son['name'] != meta['name'] ||
        son['mimeType'] != mime) {
      throw StateError('Drive dosyası işlem sırasında değişti. Yeniden seçin.');
    }
    return ImportDosya(ad, bytes);
  }

  void dispose() {
    if (_sahibi) _client.close();
  }
}
