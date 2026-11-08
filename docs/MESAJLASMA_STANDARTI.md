# Ortak alıcı seçimi ve mesajlaşma standardı

Tarih: 28 Ekim 2026

## Amaç ve kapsam

Mesajın kime gönderileceği belirlenirken bütün modüller Mesajlaşma Modülünün
ortak seçim bileşenini ve gönderim altyapısını kullanır. Formlarla Bilgi Toplama,
Sınıf Rehberliğim, öğretmen görüşleri ve diğer kaynak modüller bağımsız kişi
seçimi veya SMS/WhatsApp gönderim altyapısı oluşturmaz.

Bu belge geliştirme standardıdır. Mevcut bütün ekranların bu standarda geçtiği
anlamına gelmez. Uyarlama, ilgili modülün yetkilendirilmiş geliştirme kapsamında
yapılır. Bu belgenin oluşturulması ekran veya veri modeli değişikliği değildir.

Görsel düzen için [UI_STANDARDI.md](UI_STANDARDI.md) esas alınır; alıcı seçimi ve
gönderim davranışında bu belge uygulanır. Kullanıcının görevdeki açık talimatları
önceliklidir.

## Mevcut ortak yapı

| Kaynak | Sorumluluk |
| --- | --- |
| `lib/widgets/mesaj_alici_secim_sliver.dart` — `MesajAliciSecimSliver` | Ortak arama, sınıf, alıcı grubu ve kişi seçimi arayüzü |
| `lib/models/mesajlasma.dart` — `MesajKisi`, `MesajKisiTuru` | Öğrenci, veli ve öğretmen alıcılarının kimlik ve sınıf bağı |
| Aynı dosyada `MesajKisiOnIzleme`, `mesajTelefonNormalize` | Telefon doğrulama, eksik/geçersiz alıcılar ve aynı numarayı gruplama |
| `lib/services/mesajlasma_service.dart` — `MesajlasmaService` | Oturum kapsamı, mevcut gönderim motoru ve takip |
| `lib/services/mesaj_alici_service.dart` — `MesajAliciIslemleri` | Güncel adayları çözümleme, iletişim güncelleme ve kişi temelli kuyruk oluşturma |
| `lib/screens/mesajlasma_screen.dart` — `MesajlasmaScreen` | Ortak mesaj hazırlama, şablon, ön izleme, kanal seçimi ve kullanıcı onayı |
| `lib/widgets/mesaj_eksik_telefon_dialog.dart` | Eksik iletişim bilgilerini mevcut kayda yazma akışı |

Yeni bir ortak bileşen yazmadan önce bu yapılar genişletilir. Ekranın yalnız
alıcı seçmesi gerekiyorsa ortak seçim bileşeni gönderimden bağımsız kullanılabilir.
Arama, sınıf seçimi veya kişi listesi kaynak modülde kopyalanmaz.

## Alıcı seçiminin ortak davranışı

1. Arama alanı kullanıcı dokunmadan odaklanmaz veya klavyeyi açmaz.
2. Sınıflar mevcut yetkili veri kaynağından gelir; sayısal seviye ve şube dikkate
   alınarak küçükten büyüğe sıralanır. Tüm sınıflar yalnız izin verilen kapsamdır.
3. Kaynağın izin verdiği alıcı grupları gösterilir: sınıf öğrencileri ve sınıfta
   derse giren öğretmenler. İzin verilmeyen grup gizlenir veya erişilemez olur.
4. Öğrenci grubunda mesajın **Kendisi** veya **Velisi** için olduğu açıkça seçilir.
   Kendisi seçiliyken veli alanları gösterilmez. Veli alanları mevcut ilişki
   çözümleme ve iletişim düzenleme işlemlerini kullanır.
5. Öğrenci/öğretmen listesi başlangıçta kapalıdır; kullanıcı açar. Kişi seçimi
   yapıldığında mevcut ortak davranışa uygun kapanır. Başlıkta
   `seçilen / toplam` sayısı gösterilir.
6. Tümünü seç ve Seçimi kaldır aynı yerde bulunur. Filtre/aramanın etkin olduğu
   durumda toplu seçimin yalnız görünenlere uygulanacağı açıkça yazılır:
   **Görünenleri seç**. Gizli satırlar sessizce seçilmez veya silinmez.
7. Arama veya sınıf değişimi mevcut seçimi kendiliğinden silmez. Kaynak modülün
   kapsamı dışına çıkan kayıtlar ise gönderimden önce çıkarılır ve bildirilir.
8. Başlangıç seçimi, kaynak modül tarafından verilebilir. Boş seçim ile tümünü
   seçme farklıdır; boş seçim kendiliğinden bütün alıcılara dönüştürülmez.
9. Kimse seçilmemişse açıklayıcı uyarı gösterilir. Gönderim akışı başlatılmaz.

Bu davranışlar ortak bileşenin hedef sözleşmesidir. Eksik davranış ortak bileşende
uygulanır; her modülde farklı bir yorumla tekrar kodlanmaz.

## Form kapsamı ile mesaj alıcısı farklıdır

| Kavram | Anlamı |
| --- | --- |
| Formun konusu / öğrenci kapsamı | Formun hangi sınıf veya öğrenciler hakkında yanıt toplayacağı |
| Yanıtlayacak hedef kitle | Öğrenci, veli veya öğretmen gibi yanıt vermesi beklenen grup |
| Mesaj alıcısı | Form bağlantısının iletişim kaydı üzerinden gönderileceği kişi |

Örnek: 24 öğrencilik bir sınıf için Velisi seçilirse öğrenci kapsamı 24 kişidir;
mesaj alıcıları bu öğrencilerin velileridir. Ortak telefon kullananlar nedeniyle
tekil telefon sayısı 24'ten az olabilir. Bu durum öğrenci kapsamını daraltmaz.

Öğretmen görüşünde ise formun konusu sınıf ve öğrencileridir; mesaj alıcıları o
sınıfta derse giren seçili öğretmenlerdir. Öğretmen kimliği öğrenci kimliği olarak
yorumlanmaz. Form türüne özgü yanıt eşleştirme ve kaydetme işlemi kaynak modülde
kalır. Alıcı seçimi öğrenci ana kaydını veya form yanıtını kendiliğinden değiştirmez.

## Modüller arası aktarım

Kaynak modül şunları sağlar:

- Kaynak modül ve kayıt kimliği; geçmişin doğru işlemi göstermesi için.
- Geçerli okul, öğretmen profili, eğitim yılı ve varsa sınıf/öğrenci sınırı.
- İzin verilen kişi türleri ve başlangıçta seçili kişi kimlikleri.
- Başlangıç mesajı ve varsa hazırlanmış, doğrulanmış form bağlantısı.
- Kaynağa erişimin devam ettiğini kontrol eden mevcut kapsam denetimi.

Seçim sonucu kişi türü, kişi kimliği ve sınıf bağıyla taşınır. Telefonlar kaynak
ekranda ayrı bir rehbere kopyalanmaz; gönderim öncesinde servisten yeniden okunur.
Görünen ada veya liste sırasına göre alıcı eşleştirmesi yapılmaz.

Mevcut `MesajlasmaScreen` parametreleri uyarlamada esas alınır:

| Parametre | Kullanım ve sınır |
| --- | --- |
| `kaynakModul`, `kaynakKayit` | İşlemin ve geçmişin kaynağı |
| `baslangicMetni` | Kullanıcının düzenleyebileceği başlangıç mesajı |
| `baslangicOgrenciIdleri` | Mevcut öğrenci akışında başlangıç seçimi |
| `izinliOgrenciIdleri` | Öğrenci kapsamı; `null` ile boş küme aynı değildir |
| `ogretmenSinifId` | Öğretmen akışında yalnız ilgili sınıf |
| `baslangicOgretmenIdleri` | Bu sınıf içindeki başlangıç öğretmen seçimi |
| `kaynakKontrol` | Mevcut kaynağın okul/profil/yıl ve kayıt erişimini doğrular |
| `gonderimOnizlemesiniAc` | Normal modül aktarımında `false`; önce ortak hazırlama ekranı açılır |

Bu parametreler bütün kişi türleri için tek bir genel sözleşmenin tamamlandığı
anlamına gelmez. Gerekli genişletme mevcut ortak yapılarda, ilgili kapsamda yapılır.
`izinliOgrenciIdleri` öğretmen kısıtı olarak kullanılmaz: mevcut servis bu sınır
verildiğinde öğretmen adaylarını dışlar. Başlangıç seçimi tek başına yetki sınırı
değildir; aday sorgusu ve gönderim servisi de kaynak kapsamını doğrulamalıdır.

## Telefon kontrolü ve iletişim güncelleme

- Adaylar `MesajlasmaService.aliciAdaylari()` ile mevcut veri kaynağından çözülür.
- Telefonlar mevcut `mesajTelefonNormalize()` kurallarıyla doğrulanır.
- Eksik/geçersiz numaralar kişi bazında bildirilir. Kullanıcı mevcut tamamlama
  ekranından düzenleyebilir veya açıkça gönderim dışında bırakabilir.
- İletişim değişiklikleri mevcut servisle doğru öğrenci/veli/öğretmen kaydına
  yazılır; modüle özel telefon tablosu oluşturulmaz.
- Ön izleme ile gönderim arasında değişen iletişim veya kapsam yeniden doğrulanır.
- Aynı normalleştirilmiş numara aynı ortak mesaj için tek gönderim hedefidir;
  bağlı kişilerin bilgileri geçmişte korunur. Kişiye özel farklı mesajlarda mevcut
  servis kuralları uygulanır; yalnız numara eşit diye farklı içerik sessizce atılmaz.
- Hiç geçerli telefon kalmadıysa kuyruk veya kanal çağrısı başlatılmaz.

## Gönderim akışı

**Seçim → Ortak mesaj hazırlama → Ön izleme → SMS/WhatsApp seçimi ve kullanıcı
onayı → Mevcut gönderim motoru → Gönderim takibi**

Kaynak ekrandaki Mesaj at düğmesi doğrudan SMS göndermez veya WhatsApp açmaz.
Kullanıcı ortak ekranda mesajı/şablonu düzenleyebilir, alıcıları kontrol edebilir
ve vazgeçebilir. Kaynak kapsamı dışında alıcı eklenemez.

Form bağlantısı yalnız gerçekten hazırlanmış ve gönderime uygun olduğu
doğrulanmışsa eklenir. Başarısız hazırlama, başarılı form bağlantısı gibi sunulmaz.
Bağlantısız mesaj düzenlemesine izin veriliyorsa eksiklik açıkça belirtilir;
formun hazırlanmış olduğu izlenimini veren metin otomatik üretilmez.

## Durum ve geçmiş kuralları

- WhatsApp'ın açılması yalnız **Acildi** durumudur; gönderildi veya teslim edildi
  kabul edilmez. Kullanıcının gönderim beyanı mevcut onay akışıyla alınır.
- SMS isteğinin platforma iletilmesi de teslim edildi anlamına gelmez.
- Toplu gönderim, atlama, hata, devam etme ve tekrar gönderim kuralları mevcut
  kuyruk/alıcısı motorunda kalır. Kaynak modül ayrı gönderim günlüğü tutmaz.
- Aynı alıcı farklı modül/işlem geçmişine karıştırılmaz. Gösterilen geçmiş okul,
  profil, yıl ve gerektiğinde kaynak kayıt kapsamıyla sınırlandırılır.
- Token, gizli anahtar ve gereksiz kişisel veriler log veya Git'e yazılmaz.

## Uygulama sınırları

Bu standardı uygulamak tek başına yeni servis, ekran, tablo, migration, paket,
yetki veya Google dağıtımı oluşturma izni değildir. Mevcut veriler ve çalışan
gönderim altyapısı korunur. Modüle özgü zorunlu değişiklikler önce gerçek koddan
belirlenir; yalnız ihtiyaç duyulan ortak sözleşme genişletilir.

İlk uyarlama: Formlarla Bilgi Toplama ekranındaki Hedef kitle seçiminin,
formun öğrenci kapsamı korunarak ortak alıcı seçimiyle birleştirilmesidir. Yeni formun ilk adımı ortak bileşenin ogrenciKapsami kullanımını açar. Kendisi/Velisi tercihi paylaşım aşamasında kalır; diğer modüller ayrıca uyarlanır.

## Doğrulama ölçütleri

| Senaryo | Beklenen sonuç |
| --- | --- |
| Seçim yok | Açıklayıcı uyarı; gönderim başlatılmaz |
| Tekli seçim | Yalnız seçilen kişi ve güncel iletişimi aktarılır |
| Çoklu seçim | Seçilmemiş kişi eklenmez; doğru kaynak kapsamı korunur |
| Tümünü seç / kaldır | Etikette belirtilen kapsam uygulanır; sayaç doğru güncellenir |
| Arama ve sınıf değişimi | Önceki geçerli seçimler korunur, görünmeyenler sessizce değiştirilmez |
| Kendisi / Velisi | Doğru kişi ve telefon çözülür; öğrenci kapsamı korunur |
| Sınıf öğretmenleri | Başka sınıfın öğretmeni veya öğrenci/veli eklenmez |
| Eksik veya geçersiz telefon | Mevcut tamamlama/uyarı akışı; geçerli alıcı kalmazsa gönderim yok |
| Tekrarlanan telefon | Aynı ortak mesaj için tek telefon hedefi, bağlı kişiler korunur |
| Değişen telefon / okul / profil / yıl | Güncel kapsam doğrulanır; eski veriyle gönderilmez |
| Form hazırlama hatası | Hata açıkça gösterilir; sahte veya kullanılamaz bağlantı eklenmez |
| Ön izleme veya kanal seçimini iptal | Gönderim yapılmaz |
| WhatsApp açılır | Gönderildi olarak işaretlenmez |
| Toplu işlem yarım kalır | Mevcut takip ekranından güvenli devam edilir |
| Dar ekran, büyük yazı ve klavye | Seçim, sayaç ve ana eylemler erişilebilir kalır |

Test verileriyle yapılan kontroller ile gerçek Google/telefon gönderimi ayrı
raporlanır. Yapılmayan canlı kontrol başarılı kabul edilmez.
