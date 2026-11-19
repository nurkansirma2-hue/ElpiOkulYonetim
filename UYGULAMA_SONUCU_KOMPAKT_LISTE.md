# Ana sayfa kompakt liste düzeltmesi

Başlangıç: `65d3319`, `master`. Yerel uygulama ve testlerin ardından kullanıcı bu kapsam için YAZ onayı verdi. Yalnız aşağıdaki beş kaynak/test/rapor dosyası commit/push kapsamındadır; test günlükleri yerelde tutulur. Manuel CI veya APK işlemi başlatılmaz.

## Değişiklik

Hızlı Erişim menüsü, görünüm ayarını okumadan `kompakt: false` ile sabit kutucuklar çiziyordu. Bu alan mevcut `AnaMenuYerlesimi` bileşenine ve `kompaktGorunum` tercihine bağlandı. Uygula sonrası açık ana sayfa yeniden kurulmadan liste/kart görünümüne geçer. Ortak bileşenin dar ekran ve büyük yazı uyarlaması kullanılır. Modüller, bağlantıları, günlük ders akışı ve arama korunur.

Bellekte ve kayıt yüklenirken varsayılan kompakt liste `true` oldu. Kayıtlı tercih yoksa ilk açılışta kompakt liste gelir. Kullanıcının açıkça kaydettiği kart/liste tercihi korunur; seçilen görünüm sonraki açılışta tekrar yüklenir. Renk teması, açık/koyu/sistem tercihleri ve SQLite kayıtları değiştirilmedi.

## Doğrulama

- İki ilgili test dosyasında **11 başarılı, 4 başarısız**. Yeni gerçek ana sayfa testi varsayılan listeyi, modüllerin alt alta yerleşimini, ayardan kart/liste geçişini, aynı ekran durumunun korunmasını ve kalıcı tercihle yeniden açılışı doğrular. Kurulumun ilk adımında 320 px büyük yazı ve 430 px normal görünümde geçiş testleri de geçti.
- Dört başarısız test, iki kaynak dosyanın değişiklik öncesi HEAD sürümleriyle tekrar çalıştırıldı: **aynı dört hata**. Bunlar mevcut günlük ders görünümünün eski metin beklentileri ve ikinci kurulum rehberi beklentileridir. Kapsam dışı uygulama davranışı değiştirilmedi. Kaynaklar karşılaştırma sonunda byte düzeyinde geri yüklendi.
- Doğrudan Dart analizi: yeni hata yok; ana sayfa dosyasında önceden bulunan üç kullanılmayan yardımcı bildirimi ve bir süslü parantez bilgi bildirimi var. Değişen tercih ve test dosyalarında bulgu yok. `git diff --check` temiz.
- Kanıtlar yerelde: `test-artifacts/kompakt-liste-test.txt`, `kompakt-liste-temel.txt`, `kompakt-liste-analiz.txt`. Canlı cihaz ekran karşılaştırması yapılmadı; APK derlenmedi.

## Tam dosyalar

- `lib/screens/bireysel_ana_sayfa_screen.dart`
- `lib/widgets/ana_sayfa_gorunumu.dart`
- `test/ana_sayfa_gorunumu_test.dart`
- `test/ortak_gorunum_ana_sayfalar_test.dart`
- Bu rapor.
