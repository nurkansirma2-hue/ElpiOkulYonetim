# OkulYonetim — Uygulama Geneli UI Standardı

Bu belge, yeni ve değiştirilen Flutter ekranlarının ortak tasarım kaynağıdır. Modül talebinde aksi açıkça belirtilmedikçe aşağıdaki kurallar uygulanır; AppBar, renk, kart ve boşluk kararları kullanıcıya tekrar sorulmaz. Amaç, onaylanan ana sayfa tasarımını ortak bileşenlerle uygulama geneline taşırken mevcut işlevleri korumaktır.

## 1. Uygulama yaklaşımı

- Önce mevcut ekranı, tema altyapısını ve ortak widgetları incele. Aynı işi yapan ikinci bir bileşen oluşturma; mevcut olanı genişlet.
- Projede varsa `AnaSayfaTemasi`, `OrtakGorunumTercihi`, `AnaSayfaGorunumTercihi`, `AnaMenuYerlesimi`, `AnaMenuKart` ve `GunlukDersGorunumu` yapılarını temel al. Bu adlar mevcut kodda doğrulanmalı; dosya veya API varlığı varsayılmamalıdır.
- Ortak sayfa iskeleti, AppBar, alt işlem çubuğu, kart, arama, seçim, rozet ve durum bileşenleri mevcut mimariye uygun yerde tutulur; örneğin `lib/widgets/ortak_ui/`. İsim ve dosya sayısı projeye uyar; gereksiz mimari veya toplu yeniden adlandırma yapılmaz.
- Yalnız istenen ekran/modül kapsamında aşamalı geçiş yap. Çalışan ekranları baştan yazma; ortak görsel kabı uygula. Tasarım çalışması yeni işlev ekleme gerekçesi değildir.

## 2. Tema, tipografi ve ikonlar

- Material 3 ve telefon öncelikli düzen esas alınır. Açık temada açık zemin, beyaz kart, yumuşak köşe, ince kenarlık, hafif gölge, pastel ikon alanı, koyu lacivert başlık ve gri/mavi yardımcı metin kullanılır. Varsayılan mavi AppBar, seçili temanın ana rengine uyum sağlar.
- Renk, radius, boşluk, gölge ve yazı stilleri ortak tema/token üzerinden gelir; ekranlarda tekrar tekrar sabit değer yazılmaz. Koyu temada yüzeyler ve metinler `ColorScheme` ile uyarlanır.
- Mevcut mavi, yeşil, turkuaz, mor, toprak ve grafit temaları; açık/koyu/sistem modu ve kompakt görünüm tercihleri korunur.
- Sayfa, bölüm, kart başlığı, yardımcı metin, küçük bilgi ve rozet için ortak `TextTheme` seviyeleri kullanılır. Sayfa yatay boşluğu, kart aralığı ve form aralıkları ortak değerlerden alınır.
- Global gezinme, modül ve işlem ikonları anlamlarına göre tutarlı kullanılır. Modül ikonları renkli alanlarda; ara, filtre, sırala, kaydet gibi işlem ikonları sade biçimde gösterilir. Aynı ikon farklı anlamlara atanmaz.
- Yalnız renkle anlam aktarılmaz; durum metni ve gerekirse ikon bulunur. İkon butonlarında anlaşılır tooltip/semantik etiket ve yeterli dokunma alanı sağlanır.

## 3. Ortak sayfa iskeleti ve global AppBar

- Sayfa düzeni: **global AppBar → kaydırılabilir içerik → gerektiğinde sabit alt işlem çubuğu veya ana eylem**. Gerekmeyen bölümler kapatılabilir; iç içe gereksiz Scaffold/AppBar oluşturulmaz.
- Alt sayfada geri düğmesi bulunur; ana sayfada bulunmaz. Başlık ve isteğe bağlı alt bilgi ayrı ayrı en fazla 1 satırdır; taşarsa ellipsis kullanılır.
- Sağda mevcut işlevlere bağlı Ana Sayfa, Bildirim ve Daha Fazla (`⋮`) yer alır. Ana sayfanın kendisinde Ana Sayfa ikonu gösterilmez. Bildirim rozeti gerçek veriden gelir.
- `⋮` yalnız uygulama genelindeki mevcut ayarlar, profil, görünüm ve benzeri işlemleri içerir.
- Filtre, sıralama, yenileme, dışa aktarma, not hesaplama, öğrenci seçimi, şablon ve toplu işlemler global AppBar'a konmaz; içerikte veya alt işlem alanında sunulur. Dar alanda global işlemler ortak taşma menüsünde erişilebilir tutulur.
- İçerik ve alt alan SafeArea ile korunur. Son liste öğesi sabit çubuğun altında kalmaz; ekranın kaydırma sahipliği açıkça belirlenir.

## 4. Sabit alt işlem çubuğu ve butonlar

- Liste/yönetim ekranlarında modülün mevcut işlevlerinden en anlamlı 3–5 işlem seçilir; fazlası modüle ait “Diğer” menüsüne taşınır. İşlem uydurulmaz.
- Çubuğun konumu, yüzeyi, yüksekliği, boşlukları, ikon/yazı stilleri ve SafeArea davranışı ortaktır; işlemleri modüle göre değişir.
- Form, yeni kayıt, ön izleme, adımlı akış ve onay ekranlarında çubuk zorunlu değildir; Kaydet, Devam, Ön İzle veya Gönder gibi ana eylem kullanılabilir.
- Ana eylem ortak `FilledButton`, ikincil eylem `OutlinedButton`/`TextButton` stilini kullanır. İşlem sürerken tekrar tetikleme engellenir; mevcut doğrulama korunur.
- Klavye açıldığında alanlar ve ana eylem erişilebilir kalır. Alt çubuk gerektiğinde gizlenir veya klavye üzerinde kompakt gösterilir; taşma ve içerik örtülmesi oluşmaz.

## 5. Ortak bileşenler

| Bileşen | Uygulanacak kural |
| --- | --- |
| Kart | Ortak radius, kenarlık, gölge, iç/dış boşluk, başlık/açıklama stili, ikon alanı ve sağ ok kullanılır. İçerik türü değişebilir; temel görsel dil değişmez. |
| Arama | Ortak arama ikonu, temizleme düğmesi, odak kenarlığı, radius ve ipucu stili kullanılır. Aranan alanlar, filtreleme davranışı ve sonuç işlevi korunur. |
| Seçim kartı | Alan etiketi, seçili değer ve açılma işareti gösterilir; uygun ortak Dialog/BottomSheet açılır. Seçim mantığı yeniden yazılmaz; eşdeğer seçim akışları aynı kabı kullanır. |
| Durum rozeti | Tamamlandı/başarılı: yeşil; bekliyor/devam ediyor: mavi veya nötr; uyarı: sarı/turuncu; hata: kırmızı; pasif/hesap dışı: gri. Renkler temadan gelir ve metinle desteklenir. |
| Loading | Ortak yüklenme göstergesi kullanılır; mümkün olduğunca yerleşim sıçraması önlenir. Yükleniyor, boş ve hata durumları birbirine karıştırılmaz. |
| Empty-state | İkon, kısa başlık, açıklama ve gerekiyorsa mevcut bir eylem gösterilir. Kayıt yok ve arama sonucu yok durumlarının metni ayrılır. |
| Hata | Anlaşılır Türkçe açıklama ve uygunsa yeniden deneme sunulur. Mevcut veri katmanı hata davranışı korunur; hassas teknik ayrıntı kullanıcıya gösterilmez. |
| Form | Etiket, ipucu, alan, seçim, doğrulama mesajı ve buton stilleri ortaktır. Alan hatası ilgili alana yakın gösterilir. |
| Dialog / BottomSheet | Başlık, kapatma/iptal, liste, seçili öğe işareti, uygula/kaydet, radius ve aralıklar ortaktır. Uzun içerik kaydırılır; klavye ve SafeArea hesaba katılır. İptal, uygulanmamış seçimi kaydetmez; mevcut onay/kayıt davranışı korunur. |

## 6. Metin bütünlüğü ve responsive davranış

**Kart ve butonlarda kelimeler karakter ortasından bölünmez.** Örneğin `Mesajlaşma`, `Mesajlaşm / a` olarak gösterilemez; `Sınıf Rehberliğim` ise boşluktan iki satıra ayrılabilir.

- Kart başlığı en fazla **2 satırdır**. Kart açıklaması en fazla **2 satırdır** ve taşarsa **ellipsis** kullanır. Buton etiketi de kelime bütünlüğünü korur; sığmıyorsa buton/işlem düzeni uyarlanır, anlamı belirsiz hale getirilmez.
- `maxLines` ve `ellipsis` tek başına kelime ortasında satır kırılmasını engellemez. Metin ölçümü ve yeterli kullanılabilir genişlikle kural gerçekten sağlanmalıdır. Uzun tek sözcük sığmıyorsa önce yerleşim genişletilir; hâlâ sığmıyorsa satır ortasında bölmek yerine ellipsis uygulanır ve tam metne erişim sağlanır.
- Ana sayfada iki sütun tercih edilir; **iki sütunda yeterli metin alanı kalmıyorsa otomatik tek sütuna geçilir**. Tek sütunda da sabit kart yüksekliğiyle metin kesilmez.
- `LayoutBuilder` ile sayfa genişliği değil, gerçek içerik/kart kısıtları değerlendirilir. Padding, sütun aralığı, ikon alanı, ikon-metin boşluğu ve sağ ok çıkarılarak metne kalan genişlik hesaplanır; gerçek metin ve etkin yazı ölçeğiyle gerektiğinde `TextPainter` üzerinden ölçülür.
- Yaklaşık **400–420 px altı** genişliklerde iki sütunun güvenliği özellikle değerlendirilir. Bu kesin bir eşik değildir: 390–400 px genişlikte iki sütun ancak uzun başlıklar ve etkin yazı ölçeğiyle güvenliyse korunabilir. Daha geniş ekranda büyük yazı nedeniyle yine tek sütun gerekebilir.
- Erişilebilirlik ölçeği `MediaQuery.textScalerOf(context)` ile hesaba katılır; eski Flutter sürümlerinde mevcut `textScaleFactor` karşılığı kullanılır. Sığdırmak için kullanıcının yazı ölçeği kapatılmaz veya keyfî sınırlandırılmaz.
- Rehber ölçüler: ikon alanı **36–40 px**, sağ ok **16–18 px**, kart yatay padding **10–12 px**, başlık normalde **14 px**, küçük ekranda **13 px**. Bunlar Flutter mantıksal piksel ölçüleridir; zorunlu hard-code değerler değildir. Mevcut tema, metin ölçeği, okunabilirlik ve dokunma hedefleri önceliklidir; ikonun küçük olması dokunma alanını küçültmez.
- Uzun sınıf/ders adları, yatay ekran, tablet, büyük yazı, klavye, SafeArea ve kaydırma kontrol edilir. Geniş ekranda içerik okunabilir bir azami genişlikte tutulur; hiçbir düzende overflow oluşmaz.

## 7. Ana sayfa, çalışma modları ve işlevlerin korunması

- Ana menüde renkli ikon, başlık, kısa açıklama ve sağ ok içeren mevcut kart dili korunur; sütun sayısı yukarıdaki kurala uyar. Modüller mevcut yetki/mod verisinden gelir; sabit modül listesi oluşturulmaz.
- Ana sayfaya özgü `GunlukDersGorunumu` ve Bugünkü Dersler akışı korunur: tarih/gün ve ders gezinmesi, ders-sınıf-saat-sıra, yıllık plan konusu, Günlük Plan, derslik ve öğretmen gibi mevcut alanlar gerçek veriden beslenir.
- Ana sayfa öğrenci aramasının ad, soyad, okul numarası, sınıf ve mevcut diğer desteklenen alanları korunur; yalnız görsel kabı ortaklaştırılır.
- Bireysel Öğretmen modu **Flutter → SQLite**, Okul/Kurumsal mod **Flutter → API → SQL Server** akışını sürdürür. Ortak UI veri kaynağı, yetki veya kurum/öğretmen kapsamını değiştirmez; moda özgü işlemler mevcut kurallarla gösterilir.
- Servisler, modeller, controller/state yönetimi, sorgular, iş kuralları, kayıt/gönderim davranışı ve navigasyon hedefleri UI düzenlemesi nedeniyle gereksiz değiştirilmez. Örnek sınıf, tarih, öğretmen, puan veya bildirim sayısı gerçek veri yerine yazılmaz.

## 8. Doğrulama ve teslim ölçütleri

- Değişiklikten önce etkilenen mevcut akışları belirle; sonra `flutter analyze`, ilgili mevcut testler ve ortamın desteklediği build kontrolünü çalıştır. Çalıştırılamayan kontrolleri ve nedenlerini açıkça bildir; yapılmayan kontrolü başarılı sayma.
- Ana sayfa açılışı, geri/ana sayfa gezinmesi, bildirim/menü, arama/filtre/seçim, kayıt gibi etkilenen işlemleri doğrula. Her iki çalışma modu ve yetki görünürlüğünde regresyon kontrolü yap.
- Açık/koyu/sistem teması, renk ve kompakt görünüm tercihleri, günlük ders alanı ve öğrenci aramasını koru. Ortak bileşen değiştiğinde onu kullanan diğer ekranlardan temsilî örnekleri kontrol et.
- 320/360 px dar ekranlar, 390/400/420 px çevresi ve geniş ekranlarda; normal ve büyütülmüş yazıyla kontrol yap. Uzun başlıklar (`Mesajlaşma`, `Sınıf Rehberliğim`, `Öğrenci İşlemleri`), uzun tek sözcük, uzun sınıf/ders adı ve 30–40 öğrencili listede metin, kaydırma ve performansı gözle.
- Kelime ortası kırılma, 2 satır sınırları/ellipsis, otomatik tek sütun, klavye, alt çubuğun SafeArea'sı ve son öğenin erişilebilirliği teslim ölçütüdür. Yerleşim mantığı değişmişse bu riskleri kapsayan hedefli widget testleri ekle veya güncelle.
- Teslimde değişen ekran/bileşenleri, doğrulama sonucunu ve kalan sınırlamaları kısa belirt. Bu belge tek başına uygulama kodunu değiştirme veya bütün modülleri dönüştürme talimatı değildir.
- GitHub'a yazma, commit veya push yalnız kullanıcının açık talimatıyla yapılır; UI düzenleme talebi kendiliğinden bu izni vermez.
