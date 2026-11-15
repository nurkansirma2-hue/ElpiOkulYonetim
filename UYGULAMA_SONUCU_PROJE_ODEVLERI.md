# Proje Ödevleri — yerel uygulama sonucu

Kaynak: `nurkansirma2-hue/ElpiOkulYonetim`, `master`, başlangıç `5b5be20`.
Yerel çalışma klasörü: `ElpiOkulYonetim`.
Önceki `OkulYonetim` ve `OkulYonetim-guncel` kopyaları değiştirilmedi.

## Uygulanan akış

| Ekran | Gerçek bağlantı ve davranış |
| --- | --- |
| 1. Form talebi / Kapsam | Rehberlik Dosyam içinden Proje Ödevleri kartı; başlık, açıklama, atamanın sınıf/yıl bilgisi, ortak alıcı bileşeniyle öğrenci seçimi ve isteğe bağlı son gün. |
| 2. Öğrenci ve dersler / Sorular | Seçili öğrenciler açılır bölümde; sınıfın güncel ders kayıtları, programı ve sınıfa bağlı ders öğretmenleri birlikte kullanılır. Kayıtlı bütün dersler başlangıçta seçilidir. Ders Ekle ile yalnız bu forma ders eklenebilir; kutusu kaldırılan ders formdan çıkarılır. Altı ders sınırı yoktur; öğrencinin üç farklı tercih yapabilmesi için en az üç ders seçilmelidir. Sabit örnek öğrenci/ders sayısı yoktur. |
| 3. Google Form / Kontrol | Ortak BilgiToplama tabloları ve Forms adaptörü. Öğrenci kimliği sınıf, okul numarası ve ad soyad içeren kayıtlı açılır listeden eşleşir. Üç ders sorusu zorunlu açılır listedir; açıklama Google formuna da aktarılır. Ön izleme, sabit Geri/Hazırla alanı, yerel taslak tekrar koruması ve yarım kalan Google formunu bağlama desteği vardır. |
| 4. Davet | Yayın ve yanıt kabulü Google'dan doğrulanır; kayıtlı kişi bağları ortak Mesajlaşma onayına taşınır. SMS/WhatsApp, telefon denetimi, tekrar numara birleştirme ve takip mevcut modülde kalır. Ekranın açılması gönderildi sayılmaz. |
| 5. Yanıtlar | Özet, Yanıtlar ve Değerlendirme görünümleri; ortak yanıt getirme, gerçek tekil öğrenci sayaçları, form bilgileri ve eksiklere hatırlatma. Belirsiz/çoklu öğrenci yanıtı varsa otomatik hatırlatma durur. |
| 6. Tercih kontrolü | Arama, sorunlu kayıt filtresi, üç farklı ders denetimi, seçili/geçerli tercihleri onaylama. Satırdaki Düzenle özgün yanıtı koruyan ortak düzeltme API'sini kullanır; yeni sürüm yeniden onay gerektirir. Eşleşmeyen, çoklu, eksik, pasif ve reddedilmiş yanıtlar onaylanmaz. |
| 7. Dağıtım | Kontenjan varsayılan olarak kapalıdır. Açıldığında ders başına sıfır veya pozitif kontenjan; ön izleme, manuel düzenleme ve açık onayla kalıcı kayıt. Yerleşmeyen öğrenci sayısı ayrıca gösterilir. |
| 8. Raporlar | Öğrenci tercihleri, ders bazlı öğrenciler, kayıtlı ders öğretmenleri ve tercih/dağıtım takip çizelgesi. Gerçek `.xlsx`, `.docx`, `.pdf` üretimi; seçilen raporun PDF'sini mevcut Belgelerim arşivine kaydetme. Öğretmen eşleştirmesi yoksa isim uydurulmaz. |

Dağıtım kuralı: önce bütün öğrencilerin 1., sonra 2., sonra 3. tercihleri değerlendirilir. Aynı öncelikte okul numarası sırası kullanılır. Tercih edilmeyen derse otomatik atama yapılmaz. Manuel düzenleme de onaylı tercihler ve kontenjanlarla doğrulanır. Bu, rastgele kura veya küresel en iyi eşleştirme algoritması değildir.

Son gün bilgilendirme amaçlıdır; Google yanıt alımını otomatik kapatan yeni bir zamanlayıcı eklenmedi. Açma/kapatma mevcut ortak form ayrıntısından yönetilir. Takip çizelgesi bu modülün tercih/onay/dağıtım sürecini gösterir; diğer Ödev Kontrol modülünün not veya teslim kayıtları değiştirilmez.

## Veri ve mevcut sistem

- Yeni tablo, SQLite sürüm değişikliği veya paket eklenmedi. Proje kapsamı, onaylar, dağıtım ve davet metni mevcut `UygulamaAyarlari` içinde okul/profil/rehberlik ataması kapsamında saklanır. Ham yanıt ve öğrenci kimlik anlık görüntüsü ortak BilgiToplama kayıtlarındadır.
- Kayıt işlemleri güncel okul, profil, yıl, aktif atama ve öğrenci kapsamıyla doğrulanır. Geçmiş atamada yazma reddedilir. Yeni yanıt eski onayı veya kesin dağıtımı sessizce değiştirmez; eski ön izlemeyle kayıt durdurulur.
- Öğrenci ana kayıtları, mevcut SQLite şeması, importlar, diğer modüller ve kullanıcı veritabanı değiştirilmedi. Depodaki mevcut çalışma modu yalnız Bireysel Öğretmen'dir; yeni kurumsal/API katmanı oluşturulmadı.
- Gerçek Google hesabında form oluşturulmadı; gerçek SMS/WhatsApp mesajı gönderilmedi.

## Görsel kontrol ve açıklanan farklar

İki referans panodaki sekiz görünüm, Flutter widget testlerinden alınan gerçek renderlarla incelendi. `test-artifacts/proje/` altında 16 PNG vardır: 400 px normal yazı ve 320 px 1,3 yazı ölçeği. Bunlar üç öğrencili bellek içi test verisidir; uygulama ekranlarında bu sayılar sabit değildir.

Başlık/özet → form/liste → sabit işlem alanı sırası, üç aşama, ders seçenekleri, yanıt sayaçları, kontrol, dağıtım ve rapor bölümleri karşılaştırıldı. Taşma testlerinde Flutter hatası oluşmadı. Kontrol satırındaki eksik yazı tipi simgesi düzeltildi; Google hazırlama/onay ve rapor eylemleri anlamlarına göre renklendirildi.

Bu sürüm için **piksel birebir eşitlik iddiası yoktur**. Bilinen uyarlamalar:

- Üst çubuk, kartlar, boşluklar ve ana renk mevcut ortak UI/tema tercihlerinden gelir; referans afişinin her rengi ve ölçüsü zorla sabitlenmez.
- Sınıf ve yıl açık rehberlik atamasından gelir; başka sınıf/yıla geçiş açılır listesi eklenmedi. Öğrenci seçimi ortak bileşenle yapılır.
- Kanal ve kişi onayı ayrı bir gönderim motoruyla çoğaltılmadı; mevcut ortak Mesajlaşma onayında gösterilir.
- Tercihler dar ekranda kaydırılabilir seçim/düzeltme kartlarıdır; referanstaki sıkıştırılmış yatay tablo düzeni birebir kopyalanmadı. İşlemler arasında küçük bir menü vardır.
- Büyük yazıda alt eylemler gerektiğinde satıra sarılır. Canlı Android/emülatör ve gerçek cihaz ekranı karşılaştırması yapılmadı.

## Doğrulama

| Kontrol | Sonuç |
| --- | --- |
| Değişen yedi Dart dosyasında doğrudan Dart analizi | `No issues found!` |
| Yeni proje test dosyası | **12 başarılı, 0 başarısız** |
| Yeni test kapsamı | Tekrar yanıt, aynı ders, eksik yanıt, eski ön izleme, çoklu yanıt, pasif öğrenci, mod/profil/yıl, geçmiş atama, reddedilen/silinen yanıt, manuel kontenjan, yerel düzeltme, Google açılır liste/açıklama, çıktı dosyaları, tam yedek geri yükleme, Belgelerim'e PDF kaydı ve sekiz görünümün dar ekranları. |
| Mevcut dokuz dosyalık regresyon seçimi | **159 başarılı, 31 başarısız** |
| Aynı regresyon seçimi değişiklik öncesi `5b5be20` kaynakta | **159 başarılı, aynı 31 test başarısız**; başarısız test adlarında fark yok. |
| Git farkında boşluk kontrolü | `git diff --check` temiz. |

Regresyon seçimi: Rehberlik modülü, bireysel rehberlik, rehberlik bilgi formu, öğrenci görünümü, ortak bilgi toplama servisi/ekranı, Belgelerim, mesaj alıcı altyapısı ve tekli onay testleri. Mevcut hatalara örnekler: kaldırılmış/dönüşmüş ekran metinlerini arayan testler, eski SQLite sürümü beklentisi (`27` / mevcut `31`), eski yedek performans tablosu beklentisi ve mevcut ortak ekranın PageStorage `bool/double` hatası. Bu kapsam dışı kaynaklar değiştirilmedi.

Her iki karşılaştırmalı çalışmada da `eski veli cevabı korunur; seçilen ebeveynin eğitim ve mesleği alınır` testi filtreyle dışarıda bırakıldı; ilk filtresiz çalışma bu testte bekledi ve sonlandırıldı. Bu test başarılı sayılmadı. Genel test takımının tümü başarılı değildir.

`flutter analyze --no-pub`, analiz sunucusunda Türkçe çalışma yolu için LSP JSON çözümleme hatası verdi; aynı dosyalar doğrudan `dart analyze` ile denetlendi. Canlı Google, SMS/WhatsApp ve gerçek cihaz kontrolleri yapılmadı; APK derlenmedi.

Kanıtlar yerelde saklandı; GitHub commitine dahil edilmedi: `test-artifacts/proje-analiz.txt`, `proje-yeni-test.txt`, `proje-regresyon-son.txt`, `proje-temel-regresyon.txt` ve `test-artifacts/proje/*.png`.

## Değişen tam kaynak dosyalar

- `lib/screens/bireysel_rehberlik_dosyasi_screen.dart` — mevcut bölüm kartlarının ardından Proje Ödevleri girişi.
- `lib/screens/rehberlik_proje_odev_screen.dart` — sekiz görünüm ve işlem bağlantıları.
- `lib/services/bireysel_rehberlik_service.dart` — yeni proje bölümünü aynı servis kitaplığına bağlayan `part` satırı.
- `lib/services/rehberlik_proje_odev_service.dart` — kapsam, kalıcılık, tercih doğrulama/onay, dağıtım ve ders öğretmeni sorguları.
- `lib/services/bilgi_toplama_google_service.dart` — `_item` içinde proje tercihleri için açılır liste; `hazirla` içinde isteğe bağlı açıklama ve doğrulaması. Mevcut çağrılarda açıklama parametresi zorunlu değildir.
- `lib/services/proje_odev_rapor_service.dart` — Excel/Word/PDF rapor üretimi.
- `test/rehberlik_proje_odev_test.dart` — yeni iş akışı ve koruma testleri.

Dosyaların tam hâlleri proje klasöründedir. Üretilen makineye özel Flutter dosyaları değişiklik kapsamından temizlendi. Yerel uygulama ve testlerin ardından kullanıcı **YAZ** onayı verdi. Yalnız bu rapor ve yukarıdaki yedi kod/test dosyası commit/push kapsamındadır. Manuel CI veya APK işlemi başlatılmadı.

## Ders listesi düzeltmesi — sonraki yerel çalışma

`965f8d3` sonrasında ders listesinin yalnız programdan gelmesi düzeltildi. `DersSinif`, geçerli program ve yetkili sınıf öğretmenlerinin ders bağları birleştirilir; diğer yıl ve ilgisiz dersler alınmaz. İlk altı dersi seçme kısıtı kaldırıldı. Elle eklenen ders form içinde saklanır; ana ders kataloğu ve sınıf programı değiştirilmez. Çıkarılan ders öğrenciye sunulan üç açılır listenin seçeneklerinden de çıkar.

Son doğrulama: **16 test başarılı**, değişen üç Dart dosyasının analizi temiz. Ek testler sekiz sınıf dersinin gelmesini, başka ders öğretmeninin dersini, elle eklenen dersin kalıcılık/dağıtımını, tekrarlı veya ilgisiz derslerin reddini ve 320/400 px ekranda Ders Ekle ile seçimden çıkarmayı kapsar. Günlük: `test-artifacts/proje-ders-duzeltme-test.txt`. Kullanıcı bu düzeltme için de **YAZ** onayı verdi. Bu rapor, proje ekranı, proje servisi ve ilgili test dosyası commit/push kapsamındadır; test günlükleri ve ekran görüntüleri yerelde tutulur.

## Yanıt ekranında doğrudan işlem — sonraki yerel çalışma

`7844280` sonrasında Yanıtlar ve Değerlendirme sekmelerindeki **Ortak form ayrıntısı / yanıt düzenleme** düğmesi kaldırıldı. Öğrenci adına/satırına normal dokunuş cevap düzenleme penceresini açar. Basılı tutma seçim modunu açar; bu modda dokunma seçimi değiştirir. Tümünü seç/seçimi kaldır, seçim sayısı ve seçimi kapatma aynı görünümde yer alır. Boş seçimde toplu işlemler kapalıdır. Sekme/işlem değişiminde veya seçim kapatıldığında seçim temizlenir; geri işlemi önce seçimden çıkar.

Seçili yanıtların toplu onayı aynı proje tercih onayını kullanır. Sorunlu yanıtlar otomatik onaylanmaz; kaç kaydın atlanacağı onayda bildirilir. İsim üzerinden düzenleme özgün cevabı koruyarak yeni sürüm kaydeder ve yeniden onay gerektirir. Birden fazla cevabı bulunan öğrencilerin ham yanıtları da ayrı satırlarda listelenebilir.

Toplu silme mevcut Google/yerel silme planını kullanır. Güncel yanıtlar ve seçili sürümler doğrulanır, kullanıcıya kalıcı silme onayı gösterilir. Yalnız seçilen yanıt kimlikleri silinir; yeni veya seçilmemiş yanıtlar kapsama alınmaz. İlerleme/durdurma ve kısmi başarı sonucu ekranda gösterilir. Google silmesi başarısız kaydın ham cevabı korunur. Öğrenci ana kaydı değiştirilmez. Etkilenen tercih/dağıtım geçerliliği yeniden hesaplanır. Canlı kullanıcı yanıtı silinmedi; testte Google adaptörü taklit edildi.

Genişletilmiş proje test dosyası **16 test başarılı** sonucunu verdi. Ekran testi; dokunarak düzenlemeyi kaydetme, özgün yanıtı koruma, uzun basma, tümünü seçme, hatalı tercihleri atlayarak toplu onay, silmeyi iptal ve kısmi silmede kalan kayıtları korumayı doğrular. 320 px büyütülmüş yazı ve 400 px normal görünümün yanıt/seçim renderları incelendi. Sekme başlıkları kelime ortasından bölünmez; ders tercihleri numaralı sırayla gösterilir. Değişen ekran/test dosyalarının analizi temiz. Kanıtlar yerelde: `test-artifacts/proje-yanit-islemleri-test.txt` ve `test-artifacts/proje/*-5-yanit-listesi.png`, `*-5-yanit-secimi.png`.

Kullanıcı bu son yanıt ekranı değişiklikleri için de **YAZ** onayı verdi. Proje ekranı, ilgili test dosyası ve bu rapor commit/push kapsamındadır. Test günlükleri ve ekran görüntüleri yerelde tutulur; manuel CI veya APK işlemi başlatılmaz.
