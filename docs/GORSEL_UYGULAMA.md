# Okul Yönetim Projesi — Görselden Gerçek Uygulamaya Dönüştürme Standardı

> **Amaç:** Kullanıcının gönderdiği veya onayladığı referans görseli, hem görünüm hem davranış bakımından mümkün olan en yüksek sadakatle gerçek Flutter ekranına dönüştürmek; kalıcı veri ve mevcut çalışan sistemi korumak. Yalnızca benzer işlevleri yapmak, birkaç kartı değiştirmek veya yeni bir maket üretmek tamamlanma değildir.

## 1. Kapsam ve komutlar

- **UYGULA:** Onaylanan referans görseldeki tüm ekranları, görünümü ve davranışları uygulama hedefi kabul et. Güncel projeyi incele; gerçek Flutter kodu ve gerekli veri bağlantılarındaki değişiklikleri hazırla/uygula. Yalnızca analiz, açıklama veya yeni maket üretip durma. Görsel üretimi Flutter kodu değişikliği yerine geçmez.
- **YAZ:** Yalnızca onaylanan değişiklikleri GitHub'a commit/push et. Açık YAZ izni yoksa GitHub'a yazma. Önceki bir YAZ komutundan genel, süresiz yetki çıkarma.
- **APK:** Kullanıcı açıkça istemedikçe APK derlemesi veya manuel iş akışı başlatma. GitHub Actions'ın push üzerine otomatik çalışabileceğini göz önünde bulundur; bunu gizleme.
- Bir görselde birden fazla telefon/ekran varsa **her biri kapsam içindedir**. Afişteki açıklamalar işlevsel gereksinim sayılır; afişin kendisini uygulama ekranına dönüştürmek gerekmez.

## 2. Ön inceleme — güncel proje gerçeği

1. İlgili dosyaların GitHub'daki güncel **tam** sürümünü incele; hafıza, tahmin veya eski kodu esas alma.
2. Ekranları, modelleri, servisleri, SQLite/API/SQL katmanını, navigasyonu, yetkileri, çalışma modlarını ve mevcut ortak UI bileşenlerini gerektiği kadar incele.
3. `UI_STANDARDI.md` ve proje talimatlarıyla uyumu koru.
4. Her görsel ekran için görünür alanları, kartları, sekmeleri, filtreleri, form alanlarını, butonları, alt çubukları, menüleri ve geçişleri tek tek çıkar.
5. Her öğeyi **mevcut ve çalışıyor / yalnız görünüm eksik / işlev eksik / veri bağlantısı eksik / doğrulama-test eksik** olarak sınıflandır.
6. Çalışan özelliği yeniden yazma veya gereksiz refactor yapma; mevcut ortak altyapıyı kullan.

## 3. Görsel sadakat — temel kabul ölçütü

- **Referans görsel tasarım şartnamesidir; serbest ilham kaynağı değildir.** Kullanıcı yeni bir tasarım istemedikçe yerleşimi, kart gruplarını, başlıkları, buton sırasını, simgeleri, renkleri ve bilgi hiyerarşisini değiştirme.
- Her ekran için referansın görünür bölgelerini **üst uygulama çubuğu → başlık/özet → seçim ve işlem alanları → liste/form → kayıt alanı → alt gezinme** şeklinde eşleştir. Görselde olmayan yeni büyük alanlar ekleyerek ekranı uzatma.
- Mümkün olduğu ölçüde **ölçülebilir tasarım özelliklerini** çıkar ve uygula: yatay/dikey boşluklar, kart yüksekliği, köşe yarıçapı, kenarlık, gölge, arka plan ve durum renkleri, tipografi ağırlığı/boyutu, ikon boyutu, hizalama, buton genişliği, satır yoğunluğu, fotoğraf boyutu ve sabit alt çubuk.
- Aynı görünümü sağlamak için mevcut ortak UI bileşenlerini kullan; bunlar referansla uyuşmuyorsa yalnızca ilgili ekranda sınırlı stil uyarlaması yap. Standart `Card`/`ListTile` kullanmak tek başına görsel eşdeğerlik kanıtı değildir.
- Görseldeki **her görünür öğe** için gerçek Flutter karşılığı bulunmalı; eksik, farklı konumda veya yanlış boyuttaki öğe ayrı uyumsuzluk olarak kaydedilmeli.
- Referans birden fazla ekran içeriyorsa her ekranı ve aralarındaki geçişleri aynı sadakatle uygula. Tek ekranı tamamlamak bütün tasarımın tamamlandığı anlamına gelmez.
- Kullanıcı onayladığı referansı değiştirmedikçe asistan kendi ürettiği daha yeni görseli onun yerine koyamaz.
- **Ekran ölçeği:** Referans görselin piksel ölçüleri gerçek cihazın mantıksal piksel ölçüleriyle aynı olmayabilir. Birebir hedef, referansın *oranları, görsel hiyerarşisi ve davranışıdır*; her cihazda fiziksel piksel eşitliği vaadi verilmez.
- Küçük ekran, büyük yazı ölçeği, uzun adlar ve dar genişliklerde taşma/kesilme olmamalı. Önce referansın görünümünü koruyan esnek ölçüler, `Expanded`/`Flexible`, sınırlı metin ve uygun kaydırma kullan; gerekirse yalnızca dar ekran için uyarlama yap.
- Gerçek veri büyüklüğü, boş liste, yüklenme, hata, tekrar kayıt, düzenleme ve geri dönüş durumlarını tasarım bütünlüğünü bozmadan ele al.
- Referanstaki örnek isim, sayı, dosya ve tarihleri gerçek veri gibi sabitleme.

### 3.1. Görsel karşılaştırma döngüsü (zorunlu)

1. Onaylı referansı sabit tut; uygulamadan **aynı ekran durumunda** gerçek ekran görüntüsü al. Aynı seçili sekme/uygulama, benzer liste uzunluğu, aynı ekran boyutu ve yazı ölçeği ile karşılaştır; örnek veri ile gerçek veriyi karıştırma.
2. Referans ve Flutter görüntüsünü yan yana incele; mümkünse üst üste bindirme/fark görüntüsü kullan. **Yerleşim, ölçüler, renkler, yazılar, ikonlar, kenarlıklar, gölgeler, hizalar ve alt çubuk** için farkları tek tek belirle.
3. Önce büyük yapısal farkları, sonra boşluk/ölçüleri, sonra renk ve tipografiyi düzelt. Her düzeltmeden sonra yeni gerçek ekran görüntüsüyle tekrar karşılaştır.
4. Aynı ekranı **dar telefon genişliğinde** ve uzun metinle de kontrol et. Referansa sadakat uğruna kullanılamaz veya taşan arayüz oluşturma.
5. Görsel karşılaştırma yapılabilecek Flutter/emülatör/ekran görüntüsü erişimi yoksa **'görsel doğrulama yapılamadı'** de; görseli birebir uyguladığını iddia etme. Kullanıcıdan yalnızca erişilemeyen test için gerekli gerçek ekran görüntüsünü iste.
6. Tasarımda teknik olarak uygulanamayacak veya kullanım güvenliği nedeniyle uyarlanması gereken noktaları ve sapma gerekçelerini açıkça bildir; sessizce tasarımı değiştirme.


## 4. İşlevsellik ve veri kalıcılığı

- Gösterilen her etkileşimli öğenin gerçek işlevi ve uygun navigasyonu olmalı.
- Form alanı, kayıt servisinin kabul ettiği alanlara ve veritabanındaki gerçek sütunlara bağlanmalı; kaydetme sonrası tekrar açıldığında veri korunmalı.
- Gerekiyorsa sıralamayla **veritabanı → servis/API → Flutter** değiştir. Gerekmeyen katmana dokunma.
- Bireysel Öğretmen modu Flutter + SQLite; Kurumsal mod Flutter + API + SQL Server kullanır. Modlar arası veriyi karıştırma; mod değişiminde veri silme.
- Aktif/pasif kayıt, geçmiş eğitim yılı, öğretmen kapsamı ve yetki ilişkilerini koru. Pasif silme, geçmiş belge ve öğrenci kimliğini yanlışlıkla silmemeli.
- Mevcut Import/Export sihirbazlarında önizleme → hata kontrolü → kullanıcı onayı → kayıt sürecini koru; mevcut Excel formatlarını bozma.
- İletişim kısayollarını ortak Mesajlaşma sistemi üzerinden yürüt; gönderilmiş gibi sahte durum oluşturma.

## 5. Sahte tamamlanma yasakları

Aşağıdakiler **uygulandı** sayılmaz:

- Kaydetmeyen bir alan veya boşta kalan buton
- Sabit örnek veriyle çalışan liste, filtre ya da grafik
- Servise bağlanmayan telefon/mesaj/kayıt kısayolu
- Yalnız başlık, renk, açıklama kartı veya birkaç ikon değişikliği
- Aynı işlevi yapan ama referanstaki yerleşim, ölçü ve görünümden belirgin biçimde farklı ekran
- Flutter ekranı yerine görsel üretim aracıyla oluşturulmuş yeni maket
- Gerçek ekran görüntüsüyle karşılaştırılmadan "birebir aynı" denmesi
- Dört ekranlık görselin yalnız bir ekranının yapılması
- Test edilmemiş işlemi test edildi diye bildirmek
- Eksik işleri gizleyip **“birebir uygulandı”** demek

## 6. Otonom öz-denetim

Kullanıcıya dönmeden şu denetimi yap:

1. Görselde veya açıklamalarda atlanan ekran/öğe var mı?
2. Her buton gerçekten uygun işlemi açıyor mu?
3. Veriler yazılıyor, okunuyor, güncelleniyor ve gerektiğinde güvenli pasife alınıyor mu?
4. Boş/yanlış/tekrarlı veri ve eski kayıtlar ne olacak?
5. Küçük telefon, tek el kullanımı ve uzun listelerde sorun var mı?
6. Yetki, öğretmen kapsamı, eğitim yılı ve iki çalışma modu korundu mu?
7. Çalışan hangi özellik veya import bozulabilir?
8. Gereksiz yeni mimari veya fazla tıklama oluşturdum mu?

Kullanıcı tercihi veya geri döndürülemez/veri kaybı riski gerektirmeyen teknik eksikleri önce araştırıp çöz. Kritik kararlarda onay al.

## 7. Test ve regresyon

Değişiklikle ilgili erişilebilir testleri seç ve çalıştır: analiz/build, ekran açılışı, navigasyon, ekleme/okuma/güncelleme/pasif silme, boş-hatalı-tekrarlı veri, filtre/arama, yetki, mod, eğitim yılı, ekran taşması ve regresyon.

Görsel testte referans ile gerçek Flutter ekranının karşılaştırmasını ve tespit edilen farkların giderilmesini de kontrol et. Test aracına erişilemiyorsa bunu açıkça bildir; test yapılmış gibi davranma. Hata veya Exception varsa öncelikle onu çöz ve orijinal hata metnini koru.

## 8. Tek adım, onay ve GitHub güvenliği

- Gerçek proje değişikliklerini onaylanan kapsamda ilerlet; kullanıcı onayı gerektiren sonraki gerçek adımda dur.
- **UYGULA, YAZ yetkisi değildir.** Kullanıcının açık `YAZ` komutu olmadan commit/push yapma.
- YAZ verildiğinde yalnız o onaylı kapsamı yaz. Kapsamı ilgisiz özelliklere büyütme; boş commit üretme.
- GitHub'da ilgili commitlerin zaten bulunup bulunmadığını kontrol et. GitHub API üzerinden dosya güncellemesi yapıldığında commitin uzak depoda oluşmuş olabileceğini dikkate al; yapılmamış ayrı bir push varmış gibi ifade etme.
- Yerel dosya GitHub'dan daha güncelse eski sürümle üzerine yazma.
- Kullanıcının istemediği APK'yı tetiklemek için ayrıca iş akışı başlatma.

## 9. Tamamlanma kapısı ve sonuç raporu

**“Görsel birebir uygulandı”** ancak aşağıdakiler sağlandığında söylenebilir:

- Görseldeki tüm ekranlar ve tüm gerekli öğeler ele alındı.
- Görsel tasarım mevcut sistemle uyumlu biçimde uygulandı; referanstaki bölgeler, hizalar ve ölçüler tek tek kontrol edildi.
- Gerçek Flutter ekran görüntüsü referansla karşılaştırıldı; önemli farklar düzeltildi veya gerekçesiyle raporlandı.
- Etkileşimli öğeler gerçek işlemlere ve kalıcı verilere bağlı.
- Mevcut güvenli davranışlar, yetki ve mod ilişkileri korundu.
- Yapılabilen testler yürütüldü; yapılamayanlar dürüstçe belirtildi.

Son rapor kısaca **tamamlanan ekranlar/işlevler, referans–gerçek ekran görsel karşılaştırmasının sonucu, kalan görsel farklar, değişen dosyalar, commit-push durumu, gerçek test sonuçları ve kalan engelleri** göstermelidir. Kısmi iş kısmi olarak bildirilir; “tamamlandı” etiketi kullanılmaz.

**Öncelik sırası:** Gerçek veri ve güvenlik → çalışan işlevler → onaylı görsele en yüksek sadakat → küçük ekran uyumu. Birini düzeltirken diğerini bozma.

**Son ilke:** Kullanıcı görseli ve hedefi yönetir; AI inceleme, uygulama, teknik ayrıntıları tamamlama ve öz-denetim yükünü üstlenir. Kullanıcının açık yazma/onay yetkisini devralmaz.
