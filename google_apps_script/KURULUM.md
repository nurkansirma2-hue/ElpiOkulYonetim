# Google Forms yanıt silme bağlantısı

Bu klasördeki `Code.gs` ve `appsscript.json`, Flutter uygulamasındaki
**Google Forms ve uygulamadan sil** işlemi içindir. SQL/API veya paket değişikliği yoktur.

## 22 Ekim 2026 kurulum durumu

- Google hesabında **Okul Yönetim - Google Yanıt Silme** projesi oluşturuldu.
- Kullanıcı onayıyla `809052042804` / `okulyonetim-512219` Cloud projesine bağlandı.
- Apps Script API etkinleştirildi; mevcut Forms kapsamlarına `auth/forms` eklendi.
- **Çalıştırılabilir API** olarak, **Yalnızca ben** erişimiyle sürüm 1 dağıtıldı.
- Dağıtım kimliği:
  `AKfycbzqt5tBBAmgmHmmpPjWVxc7cNqpQF2YtcnXS9GDHSp6BJ5Rs21OUkhJsxOVNFp7jpRf`
- Üretimde kullanılan `BireyselBilgiToplamaService.instance` bu kimliği varsayılan
  olarak kullanır. Kaydedilmiş profil ayarı önceliklidir; derlemede
  `GOOGLE_FORMS_DELETE_DEPLOYMENT_ID` ile varsayılan değiştirilebilir.
- `okulYanitSilKurulumKontrol` Google editöründe başarıyla çalıştı; hiçbir yanıt silinmedi.
- Telefon üzerinden OAuth/Apps Script API çağrısı ve gerçek silme testi henüz yapılmadı.
  Android Studio'da uygulamayı durdurup yeniden çalıştırın; yalnız hot reload yeterli değildir.
  Form sahibi hesapla Google iznini verip yalnız seçilmiş deneme yanıtını silerek doğrulayın.

[Google'daki betik projesi](https://script.google.com/home/projects/1gkiBMjOdyGqh0fr0qDsofUMxjOnckZXZtlk0YAi42co7a48bLz38qC5-/edit)

## Hesap kurulumu

### 23 Ekim 2026 — düzeltme bağlantısı

- Mevcut API dağıtımı aynı kimlikle sürüm 2 olarak güncellendi; erişim yine yalnız hesap sahibidir.
- `okulYanitDuzenlemeBaglantisi(formId, responseId)` yalnız verilen yanıtın Google düzenleme bağlantısını döndürür.
- Çağrı sırasında formun yanıt düzenlemesi açılır. Kapalı veya silinmiş yanıt için bağlantı verilmez.
- Flutter, yanıt/öğrenci eşleşmesini ve dönüşteki form/yanıt kimliğini doğrular.
- Yanıttan **Öğrenciye düzeltme bağlantısı gönder** seçilir; mevcut mesajlaşma ekranı yalnız o öğrencinin kayıtlı telefonuyla açılır.
- WhatsApp/SMS gönderimini öğretmen mesajlaşma ekranında onaylar. Bu kurulum sırasında mesaj gönderilmedi.
- Öğrenci Google'daki aynı yanıtını değiştirir. **Yanıtları getir** sonrasında uygulamada yalnız en güncel sürüm görünür; önceki sürüm geçmişte korunur.
- Öğrenci ana ve ek bilgileri yeni yanıt tekrar onaylandığında güncellenir. Yanıt Google'dan silindikten sonra eski bağlantı kullanılamaz.
- Yeni OAuth kapsamı veya veritabanı şeması gerekmez. Gerçek telefondan uçtan uca gönderim/düzeltme testi kullanıcı tarafından yapılmalıdır.

1. Formların sahibi Google hesabıyla [Apps Script](https://script.google.com/home) açılır.
2. Yeni projeye `Code.gs` içeriği eklenir. Proje Ayarları'ndan manifest görünür yapılıp
   `appsscript.json` içeriği kaydedilir. Erişim `MYSELF` olarak kalır; web uygulaması açılmaz.
3. **Proje Ayarları → Google Cloud Platform Projesi → Projeyi değiştir** ile
   Flutter'ın Web/Android OAuth istemcilerinin mevcut Cloud projesine bağlanır.
   Mevcut istemci kimliğinin proje numarası `809052042804`'tür.
   Bu projede **Google Apps Script API** etkinleştirilir. Mevcut OAuth istemcileri değiştirilmez.
   Google, varsayılan Apps Script projesine geri dönülemeyeceğini ve önceki
   betik yetkilendirmelerinin iptal edileceğini bildirir. İlişkilendirme için kullanıcı onayı gerekir.
4. Mevcut OAuth izin ekranına `https://www.googleapis.com/auth/forms` kapsamı eklenir.
   Hesap test modundaysa form sahibi mevcut test kullanıcıları arasında bulunmalıdır.
5. **Dağıt → Yeni dağıtım → API yürütülebilir** seçilir. Erişim yalnız hesap sahibidir.
   Oluşan **Dağıtım kimliği** alınır; betik kimliği veya web uygulaması URL'si kullanılmaz.
6. Yeni hesap için farklı dağıtım kullanılacaksa form detayındaki **Google’dan silme ayarı**
   bölümüne dağıtım kimliği kaydedilir. Kurulmuş mevcut hesapta varsayılan kimlik hazırdır.
   Bu ayar okul ve öğretmen profiline bağlıdır; token saklanmaz.
7. Telefonda form sahibi hesap seçilir ve Google Forms izni kullanıcı tarafından verilir.
   Aynı Cloud projesi ve tüm betik OAuth kapsamları zorunludur.

## İşleyiş ve doğrulama

- Kullanıcı tek yanıt için kalıcı Google silmesini onaylar.
- Uygulama sahiplik, yıl ve ön izleme güncelliğini ağ isteğinden önce denetler.
- Betik yalnız verilen form ve kesin yanıt kimliğiyle çalışır. Benzer ad/okul numarasıyla silmez.
- Betik yanıtın artık bulunmadığını doğrular. Uygulama ayrıca Forms API üzerinden
  forma erişimi ve yanıt için HTTP 404 sonucunu kontrol eder.
- Google silmesi doğrulanmadan yerel yanıt listeden kaldırılmaz.
- Ağ kesilmesi veya Google silmesinden sonra yerel işlem hatası durumunda tekrar denenebilir.
  Betik aynı yanıt yoksa bunu doğrulayıp güvenli biçimde sonuç döndürür.
- Onaylı öğrenci bilgileri ve yerel kayıt geçmişi korunur. Forma bağlı Google E-Tablolar
  kopyaları silinmez; bu, Google'ın `deleteResponse` yönteminin davranışıdır.
- `okulYanitSilKurulumKontrol` hiçbir veriyi değiştirmeden protokolü kontrol etmek içindir.
  Gerçek yanıt silme testi yalnız kullanıcının seçtiği deneme yanıtıyla ve açık onayıyla yapılır.

Hesap ilişkilendirmesi, API dağıtımı ve telefon izni tamamlanmadan canlı entegrasyon
hazır kabul edilmez. Yerel testler Google hesabında canlı silme yapmaz.

## Kaynaklar

- [Apps Script API yürütme koşulları](https://developers.google.com/apps-script/api/how-tos/execute)
- [Dağıtım kimliği ve scripts.run sözleşmesi](https://developers.google.com/apps-script/api/reference/rest/v1/scripts/run)
- [Form.deleteResponse](https://developers.google.com/apps-script/reference/forms/form#deleteResponse(String))
