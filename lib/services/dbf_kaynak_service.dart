import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DbfKaynakService {
  static const varsayilanAdres =
      'https://meslek.meb.gov.tr/dbflistele.aspx?kurum_id=1&sinif_kodu=9';
  static const _key = 'dbf_kaynak_sayfasi_v1';

  static Uri dogrula(String adres) {
    final uri = Uri.tryParse(adres.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        adres.length > 2048 ||
        adres.contains(RegExp(r'[\x00-\x20]'))) {
      throw const FormatException(
        'Kullanıcı adı/parola içermeyen geçerli bir https:// sayfa adresi yazın.',
      );
    }
    return uri;
  }

  static Future<String> getir() async {
    final adres =
        (await SharedPreferences.getInstance()).getString(_key) ??
        varsayilanAdres;
    return dogrula(adres).toString();
  }

  static Future<void> kaydet(String adres) async {
    final uri = dogrula(adres);
    if (!await (await SharedPreferences.getInstance()).setString(
      _key,
      uri.toString(),
    )) {
      throw StateError('Kaynak adresi kaydedilemedi.');
    }
  }

  static Future<void> ac(String adres) async {
    final uri = dogrula(adres);
    if (Platform.isAndroid) {
      await const MethodChannel(
        'elpi_okul_yonetim/dbf',
      ).invokeMethod<void>('kaynakAc', {'adres': uri.toString()});
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final result = await Process.run(
        Platform.isWindows
            ? 'explorer.exe'
            : Platform.isMacOS
            ? 'open'
            : 'xdg-open',
        [uri.toString()],
        runInShell: false,
      );
      if (result.exitCode != 0 && !Platform.isWindows) {
        throw StateError('Tarayıcı açılamadı: ${result.stderr}');
      }
    } else {
      throw UnsupportedError(
        'Bu platformda kaynak adresini tarayıcınızda açın.',
      );
    }
  }
}
