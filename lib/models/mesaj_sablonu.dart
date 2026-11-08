import 'mesajlasma.dart';

class MesajSablonu {
  const MesajSablonu(this.id, this.tur, this.baslik, this.metin);
  final String id, baslik, metin;
  final MesajKisiTuru tur;
  Map<String, Object?> get json => {
    'id': id,
    'tur': tur.kod,
    'baslik': baslik,
    'metin': metin,
  };
  factory MesajSablonu.oku(Map<String, dynamic> r) => MesajSablonu(
    r['id'] as String,
    MesajKisiTuru.values.singleWhere((t) => t.kod == r['tur']),
    r['baslik'] as String,
    r['metin'] as String,
  );
}

class MesajSablonListesi {
  MesajSablonListesi(this.kapsam, this.kayit, Iterable<MesajSablonu> sablonlar)
    : sablonlar = List.unmodifiable(sablonlar);
  final String kapsam;
  final String? kayit;
  final List<MesajSablonu> sablonlar;
}

const varsayilanMesajSablonlari = [
  MesajSablonu(
    'veli-genel',
    MesajKisiTuru.veli,
    'Genel veli bilgilendirmesi',
    'Sayın velimiz, {Sinif} sınıfımızla ilgili bilgilendirmemizi dikkatinize sunarız. Tarih: {Tarih}.',
  ),
  MesajSablonu(
    'veli-toplanti',
    MesajKisiTuru.veli,
    'Veli toplantısı',
    'Sayın velimiz, {Sinif} sınıfımızın veli toplantısı hakkında bilgilendirme yapılacaktır. Tarih: {Tarih}.',
  ),
  MesajSablonu(
    'veli-odev',
    MesajKisiTuru.veli,
    'Ödev hatırlatması',
    'Sayın velimiz, öğrencimizin ödevlerini zamanında tamamlaması konusunda desteğinizi rica ederiz.',
  ),
  MesajSablonu(
    'veli-devamsizlik',
    MesajKisiTuru.veli,
    'Devamsızlık hakkında görüşme',
    'Sayın velimiz, {OgrenciAdi} adlı öğrencimizin devamsızlık durumunu görüşmek üzere okulumuzla iletişime geçmenizi rica ederiz.',
  ),
  MesajSablonu(
    'ogrenci-genel',
    MesajKisiTuru.ogrenci,
    'Öğrenci bilgilendirmesi',
    'Sevgili öğrencimiz, {Sinif} sınıfımızla ilgili bilgilendirmeyi dikkatle okuyunuz. Tarih: {Tarih}.',
  ),
  MesajSablonu(
    'ogrenci-odev',
    MesajKisiTuru.ogrenci,
    'Öğrenci ödev hatırlatması',
    'Sevgili öğrencimiz, ödevlerinizi zamanında tamamlayıp ders araçlarınızla birlikte hazır bulundurunuz.',
  ),
  MesajSablonu(
    'ogrenci-gorusme',
    MesajKisiTuru.ogrenci,
    'Öğrenci görüşme daveti',
    'Sevgili {OgrenciAdi}, görüşmek için öğretmeninizle iletişime geçiniz. Tarih: {Tarih}.',
  ),
  MesajSablonu(
    'ogretmen-genel',
    MesajKisiTuru.ogretmen,
    'Öğretmen bilgilendirmesi',
    'Değerli öğretmenim, {Sinif} sınıfı ile ilgili bilgilendirmeyi dikkatinize sunarım. Tarih: {Tarih}.',
  ),
  MesajSablonu(
    'ogretmen-toplanti',
    MesajKisiTuru.ogretmen,
    'Öğretmen toplantısı',
    'Değerli öğretmenim, toplantı hakkında bilgilendirme için lütfen iletişime geçiniz. Tarih: {Tarih}.',
  ),
];
