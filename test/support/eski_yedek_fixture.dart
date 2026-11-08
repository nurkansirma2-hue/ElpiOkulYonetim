import 'package:elpi_okul_yonetim/database/bilgi_toplama_semasi.dart';
import 'package:elpi_okul_yonetim/database/mesaj_alici_semasi.dart';
import 'package:elpi_okul_yonetim/database/rehberlik_semasi.dart';

// Testte yeni manifestten, eski sürümün gerçekten taşıdığı alanları ayırır.
void eskiYedekAlanlariniAyir(Map m, int surum) {
  final tablolar = m['tablolar'] as Map, kolonlar = m['kolonlar'] as Map;
  if (surum < 30) {
    for (final t in ['OdevUygulama', 'OdevUygulamaSonuc']) {
      tablolar.remove(t);
      kolonlar.remove(t);
    }
    (kolonlar['OdevTanim'] as List).remove('DersUygulamalari');
    for (final r in tablolar['OdevTanim'] as List) { (r as Map).remove('DersUygulamalari'); }
  }
  void kaldir(String t) {
    tablolar.remove(t);
    kolonlar.remove(t);
  }

  void alanKaldir(String f) {
    (kolonlar['Ogrenci'] as List).remove(f);
    for (final r in tablolar['Ogrenci'] as List) {
      (r as Map).remove(f);
    }
  }

  if (surum < 27) kaldir('MesajTekliGecmis');
  if (surum < 25) kaldir('MesajOgretmenSinifDers');
  if (surum < 24) {
    kaldir('OgrenciIletisim');
    alanKaldir('VeliTuru');
  }
  if (surum < 23) {
    for (final t in MesajAliciSemasi.tablolar) {
      kaldir(t);
    }
  }
  if (surum < 21) {
    kaldir('OdevDegerlendirmePuani');
    kaldir('OdevDegerlendirmeOlcutu');
  }
  if (surum < 20) {
    for (final t in BilgiToplamaSemasi.tablolar) {
      kaldir(t);
    }
    for (final f in BilgiToplamaSemasi.ogrenciAlanlari) {
      alanKaldir(f);
    }
  }
  if (surum < 19) {
    for (final t in RehberlikSemasi.googleTablolari) {
      kaldir(t);
    }
  }
  if (surum < 18) kaldir('MesajSms');
  if (surum < 16) kaldir('BireyselGunlukPlan');
}
