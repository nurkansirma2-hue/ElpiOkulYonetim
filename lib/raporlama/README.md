# Ortak liste ve raporlama altyapısı

Bu klasör alan kataloğu, tasarım editörü ve PDF üretimini içerir. Okul, öğrenci,
profil, API ve veritabanı bilgisi taşımaz. Aynı altyapıyı başka bir Flutter
uygulamasında kullanmak için o uygulamanın alanlarını ve verilerini tanımlamak
yeterlidir.

## Dosyalar ve sorumluluklar

- `rapor_modeli.dart`: Flutter bağımlılığı olmayan veri/tasarım sözleşmesi,
  doğrulama ve rapor kapsamı içeren JSON.
- `rapor_tasarim_editoru.dart`: Alanları tikleme, sıralama, altı bölgede
  konumlandırma ve sayfa düzeni. Tasarımı `onDegistir` üzerinden değiştirir.
- `rapor_pdf_service.dart`: Tanım, tasarım, veri ve dışarıdan verilen fontlardan
  PDF baytları üretir.

Veriyi sorgulama, yetki kontrolü, tarih/para/birim biçimlendirme, hazır şablonlar,
JSON saklama, dosya adı belirleme, paylaşma ve yazdırma uygulamanın işidir.
Çekirdek bu işlemler için SQLite, HTTP, dosya sistemi veya bir kullanıcı
oturumu açmaz. Mevcut `pdf` ve Flutter bağımlılıkları kullanılır; bu klasör
kendi kendine paket veya SDK sürümü değiştirmez.

## Başka bir projede örnek: depo envanteri

Aşağıdaki örnek `lib/screens/` altında bir Flutter ekranıdır. `raporlama/`
klasörü aynı projenin `lib/` dizinindedir. Font yolları uygulamanın kendi
`pubspec.yaml` dosyasında kayıtlı asset yolları olmalıdır.

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../raporlama/rapor_modeli.dart';
import '../raporlama/rapor_pdf_service.dart';
import '../raporlama/rapor_tasarim_editoru.dart';

class EnvanterRaporEkrani extends StatefulWidget {
  const EnvanterRaporEkrani({super.key});

  @override
  State<EnvanterRaporEkrani> createState() => _EnvanterRaporEkraniState();
}

class _EnvanterRaporEkraniState extends State<EnvanterRaporEkrani> {
  static const tanim = RaporTanimi(
    id: 'depo.envanter',
    listeEtiketi: 'Envanter',
    bilgiAlanlari: [
      RaporAlanTanimi(id: 'isletme', etiket: 'İşletme'),
      RaporAlanTanimi(id: 'depo', etiket: 'Depo'),
      RaporAlanTanimi(id: 'sorumlu', etiket: 'Sorumlu'),
      RaporAlanTanimi(id: 'baslik', etiket: 'Serbest başlık', serbestMetin: true),
    ],
    sutunAlanlari: [
      RaporAlanTanimi(id: 'sira', etiket: 'Sıra', tur: RaporHucreTuru.sira),
      RaporAlanTanimi(id: 'kod', etiket: 'Stok kodu'),
      RaporAlanTanimi(id: 'urun', etiket: 'Ürün'),
      RaporAlanTanimi(id: 'adet', etiket: 'Adet'),
      RaporAlanTanimi(id: 'bos', etiket: 'Boş alan', tur: RaporHucreTuru.bos),
    ],
  );

  static const veri = RaporVerisi(
    bilgiler: {
      'isletme': 'Örnek Ticaret',
      'depo': 'Merkez',
      'sorumlu': 'Derya Kaya',
    },
    satirlar: [
      {'kod': 'A-101', 'urun': 'Bağlantı kablosu', 'adet': 12},
      {'kod': 'A-102', 'urun': 'Adaptör', 'adet': 3},
    ],
  );

  final tasarim = RaporTasarimi(
    ad: 'Aylık envanter',
    bilgiler: [
      RaporBilgiAlani(alanId: 'isletme'),
      RaporBilgiAlani(alanId: 'baslik', sabitMetin: 'Envanter sayımı'),
      RaporBilgiAlani(alanId: 'depo', onEtiket: 'Depo', konum: 'ustSol'),
      RaporBilgiAlani(
        alanId: 'sorumlu', altMetin: 'Depo sorumlusu', konum: 'altSag'),
    ],
    sutunlar: [
      RaporTabloSutunu(alanId: 'sira', baslik: 'Sıra', genislik: 1),
      RaporTabloSutunu(alanId: 'kod', baslik: 'Stok kodu'),
      RaporTabloSutunu(alanId: 'urun', baslik: 'Ürün', genislik: 5),
      RaporTabloSutunu(alanId: 'adet', baslik: 'Adet'),
      RaporTabloSutunu(alanId: 'bos', baslik: 'Kontrol'),
    ],
  );

  Future<Uint8List> pdfOlustur() async {
    final normal = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final kalin = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    return RaporPdfService.olustur(
      tanim: tanim,
      tasarim: tasarim.kopya(tanim),
      veri: veri,
      normalFont: normal,
      kalinFont: kalin,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Envanter raporu')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: RaporTasarimEditoru(
        tanim: tanim,
        tasarim: tasarim,
        veri: veri,
        onDegistir: (islem) => setState(islem),
        onMetinDegisti: () => setState(() {}),
      ),
    ),
  );
}
```

`pdfOlustur()` sonucu mevcut uygulamanın PDF ön izlemesine, yazdırma veya
paylaşma akışına verilir. Bu örnek dosya kaydetme ya da dış sisteme gönderme
işlemi yapmaz. Her ekran kendi mutable `RaporTasarimi` örneğini tutar; aynı
tasarım nesnesini farklı ekranlar arasında paylaşmak yerine `kopya(tanim)`
kullanılır.

## Veri ve alan kuralları

- Katalog kimlikleri boş olamaz ve bir katalog içinde tekrarlanamaz. Bilgi ve
  tablo kataloglarında aynı kimlik bulunabilir. Tasarım aynı alanı farklı
  konumlarda veya birden fazla boş sütunda kullanabilir.
- Bilgi değerleri `String`, sonlu `num` veya `bool` olarak okunur. Eksik,
  boş veya karmaşık değerler başlık üretmez. Tarih ve para gibi özel değerleri
  adaptör gösterime hazır metne dönüştürür.
- `onEtiket` değerin önüne `Etiket: değer` biçiminde eklenir. `altMetin`
  görünür ana değerin altına çizilen sabit ikinci satırdır; eksik değer için
  yedek metin değildir. İmza veya görev ünvanı bu şekilde verilir.
- `serbestMetin: true` tanımlı bilgi alanı `sabitMetin` taşıyabilir. Sabit metin
  veri anahtarından bağımsızdır ve bilgi alanı yeniden sıralanınca korunur.
- `metin` sütunu satırdaki değerini, `resim` sütunu satırdaki `Uint8List`
  resim baytlarını kullanır. `sira` sıra numarası, `bos` yazdırılabilir boş
  hücre üretir. Bu türlerde alan adı özel değildir; katalog belirler.
- İlk sürümde üst/alt sol, orta ve sağ olmak üzere altı bilgi bölgesi vardır.
  16 bilgi alanı ve 16 tablo sütunu seçilebilir; en az bir sütun görünür kalır.
  Sığdırma okunurluk sınırında durur ve kalan satırlar sonraki sayfalara geçer.

## JSON saklama ve eski şablonlar

Uygulama kaydetmeden önce `tasarim.dogrula(tanim)` çağırır ve
`tasarim.toJson(tanim.id)` sonucunu kendi deposunda tutar. Okuma:

```dart
final okunan = RaporTasarimi.fromJson(json, tanim);
```

JSON hem `surum: 1` hem `raporId` taşır. Farklı rapor kimliğine ait tasarım
reddedilir; aynı sütun isimlerinin tesadüfen bulunması yeterli değildir.
Depolama anahtarı uygulamanın rapor kimliği ve kullanıcı/kurum kapsamını da
ayırt etmelidir. Katalog alan kimlikleri şablonlar kaydedildikten sonra
değiştirilirse uygulama açık bir uyarlama sağlamalıdır.

Okul Yönetim uygulamasının eski `RaporSablonu` sürüm 1 JSON'u farklı bir
sözleşmedir. Onu doğrudan `RaporTasarimi.fromJson` ile okumayın. Öğrencilerim
uyarlayıcısı eski başlıkları, müdürün görünürlüğünü/konumunu ve sütunları ortak
tasarıma çevirir; eski kayıt biçimini ve `liste_sablonu` anahtarlarını korur.
Profil/yıl/sınıf erişimi ile birleşik sınıf sütunu kararı okul uygulamasında
kalır. Bu klasörün kullanılması tek başına veri taşıma veya şema değişikliği
gerektirmez.

Modelin okul dışı kullanımı `test/ortak_rapor_modeli_test.dart` içindeki envanter
örneğiyle; PDF ve editör davranışı kendi test dosyalarıyla doğrulanır.
