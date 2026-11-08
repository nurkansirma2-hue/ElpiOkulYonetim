import 'package:flutter/material.dart';
import '../services/ogrenci_import_tanimi.dart';
import '../services/fotograf_import_tanimi.dart';
import 'ortak_import_screen.dart';

/// Öğrenci listesi ve fotoğrafları mevcut ortak import akışına yönlendirir.
class AdminImportScreen extends StatefulWidget {
  const AdminImportScreen({super.key, this.bireyselFoto = false});
  final bool bireyselFoto;
  @override
  State<AdminImportScreen> createState() => _AdminImportScreenState();
}

class _AdminImportScreenState extends State<AdminImportScreen> {
  final _ogrenciKayitAkisi = OgrenciImportKayitAkisi();
  @override
  Widget build(BuildContext context) => widget.bireyselFoto
      ? const OrtakImportScreen(
          tanim: FotografImportTanimi.tanim,
          kayitGorseli: FotografImportTanimi.gorsel,
          ozelOnIzlemeyiHazirla: FotografImportTanimi.onIzlemeyiHazirla,
          alternatifOnIzlemeyiHazirla:
              FotografImportTanimi.hucrelerdenOnIzlemeyiHazirla,
          alternatifOnIzlemeAdi: 'Excel Hücrelerinden Elle Eşleştir',
        )
      : OrtakImportScreen(
          tanim: OgrenciImportTanimi.tanim,
          secimOnayi: _ogrenciKayitAkisi.onayla,
          secimiKaydet: _ogrenciKayitAkisi.kaydet,
          bosSecimleAktarilabilir: _ogrenciKayitAkisi.bosSecimleAktarilabilir,
          sonucIleDon: false,
        );
}
