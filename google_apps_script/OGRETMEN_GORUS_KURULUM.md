# Fotoğraflı öğretmen görüşü — kurulum paketi

28 Ekim 2026: Yerel kurulum dosyaları ve Flutter'daki **Görüş topla → Fotoğraflı
Google formu → Mesajlaşma** bağlantısı hazırlanmıştır. Google hesabındaki dağıtım
28 Ekim 2026 tarihinde sürüm 3 olarak güncellenmiştir. Aynı dağıtım kimliği ve Yalnızca ben erişimi korunmuştur. Yeni hesap kurulumunda aşağıdaki güncelleme
gereklidir. okulOgretmenGorusKurulumKontrol Google editöründe başarıyla tamamlandı. Gerçek telefondan fotoğraflı form oluşturma ve gönderim henüz doğrulanmadı.

## Mevcut hesaba tek seferlik ekleme

1. Formların sahibi hesapla [mevcut Apps Script projesini](https://script.google.com/home/projects/1gkiBMjOdyGqh0fr0qDsofUMxjOnckZXZtlk0YAi42co7a48bLz38qC5-/edit) açın.
2. **Dosyalar → + → Komut dosyası** ile `OgretmenGorus` dosyasını oluşturup
   bu klasördeki `OgretmenGorus.gs` içeriğinin tamamını yapıştırın ve kaydedin.
   Mevcut `Code.gs` dosyasını koruyun; yanıt silme/düzeltme işlemleri onu kullanıyor.
3. `appsscript.json` mevcut haliyle kalır: `auth/forms`, V8, `executionApi.access: MYSELF`.
   Yeni Cloud projesi, OAuth istemcisi, Drive izni veya web uygulaması oluşturmayın.
4. Üstteki işlev listesinden **okulOgretmenGorusKurulumKontrol** seçip **Çalıştır**
   düğmesine basın. Google izin sorarsa form sahibi hesapla Forms iznini verin.
   Bu kontrol hiçbir form oluşturmaz, fotoğraf yüklemez ve mesaj göndermez.
5. **Dağıt → Dağıtımları yönet → mevcut API yürütülebilir dağıtım → Düzenle**
   bölümünde **Sürüm: Yeni sürüm** seçin. Açıklama: `Fotoğraflı öğretmen görüşü v1`.
   Erişim **Yalnızca ben** olarak kalmalıdır. **Dağıt** ile güncelleyin.
   **Yeni dağıtım** açmanız gerekmez; mevcut dağıtım kimliği korunur:

   `AKfycbzqt5tBBAmgmHmmpPjWVxc7cNqpQF2YtcnXS9GDHSp6BJ5Rs21OUkhJsxOVNFp7jpRf`

Editörde çalıştırmak yalnız kaydedilmiş kodu kontrol eder. Telefonda kullanılan
API'nin yeni kodu görmesi için 5. adım zorunludur. Canlı API kontrolünde
`okul-ogretmen-gorus/v1`, `ready: true`, `version: 1` dönmelidir.

## Formun içeriği ve erişimi

- Zorunlu **Öğretmen adı** ve **Girdiğiniz ders / dersler** alanları.
- İsteğe bağlı **Sınıfın genel durumu hakkındaki görüşünüz** alanı.
- Her öğrencinin okul numarası, adı, varsa fotoğrafı ve ayrı uzun açıklama alanı.
  Fotoğrafı olmayan öğrencinin açıklama alanı yine bulunur. Tek forma en fazla 100 öğrenci.
- Fotoğraflar doğrudan FormApp'e veri olarak eklenir. Herkese açık Drive dosyası,
  harici görsel adresi veya fotoğraf barındırma hizmeti kullanılmaz.
- Form önce **yayımlanmamış** hazırlanır. Ayrı yayımlama çağrısı gerekir.
  Yanıt özeti katılımcılara açılmaz. Yayımlanan formdaki adlar/fotoğraflar bağlantıya
  erişebilen kişilerce görülebilir; **MYSELF betiğin çalıştırma yetkisidir**, formun
  yalnız belirli öğretmenler tarafından görülebileceği anlamına gelmez.
  Okul hesabının kurum politikaları form erişimini ayrıca sınırlayabilir.
- Betik öğretmenlerin kimliklerini doğrulamaz; ad ve ders alanları beyana dayanır.
  Telefon numarası, veli bilgisi veya öğrenci ana kaydı bu betiğe gönderilmez.

## Flutter bağlantısı için kesin çağrı sözleşmesi

Mevcut Google hesabı, OAuth Cloud projesi ve `auth/forms` izni kullanılır.
Çağrı `POST https://script.googleapis.com/v1/scripts/{dağıtımKimliği}:run`,
OAuth Bearer başlığı ve `devMode: false` ile yapılır. Token kaynak koda veya
yerel form metadata kaydına yazılmaz. Dönüş `response.result` içinden okunur;
HTTP başarısı tek başına yeterli değildir, `error` ve protokol kontrol edilir.

### Kontrol

`function: okulOgretmenGorusKurulumKontrol`, `parameters: []`.

### Form oluşturma

`function: okulOgretmenGorusFormOlustur`, `parameters: [istek]`.
İstek yapısı (örnek değerler yalnız sözleşmeyi anlatır; gerçek veri oluşturulmaz):

```json
{
  "requestId": "uygulamanin-onceden-kaydettigi-32-64-karakterli-rastgele-kimlik",
  "kapsam": "okul/profil/yil/atama/toplanti-kimlikleri",
  "baslik": "9-C sınıfı öğretmen görüşleri",
  "sinif": "9-C",
  "yil": "2026-2027",
  "ogrenciler": [
    {"id": 3004, "no": "3004", "ad": "Öğrenci adı", "foto": null}
  ]
}
```

`foto` varsa `{"mime":"image/jpeg","base64":"..."}` veya PNG karşılığıdır.
Data URL öneki kullanılmaz. Uygulama küçük ön izleme üretmelidir: fotoğraf başına
en fazla 100 KB, toplam en fazla 8 MB. Fotoğraf yolu ve ağ URL'si kabul edilmez.
İstek kimliği yalnız `[A-Za-z0-9_-]` içerir. Aynı toplantının kaydedilmiş isteği
yeniden kullanılır; ağ hatasında yeni rastgele kimlik üretilmez.

Sonuç: `protocol`, `requestId`, `formId`, `ready`, `published`,
`acceptingResponses`, `editUrl`, `responderUrl`.
Uygulama önce okul/öğretmen/yıl/atama/toplantı yetkisini kontrol eder,
istek kimliğini yerelde kaydeder, sonra ağı çağırır. Dönüşte aynı kapsamı tekrar
doğrulayıp gerçek Google form kimliğini kaydeder. `kapsam` betik tarafında
SQLite sahiplik denetiminin yerine geçmez; içeriğin parmak izine dahil edilir.

### Ön izleme sonrası yayımlama

`function: okulOgretmenGorusYayinla`, `parameters: [requestId, formId]`.
Yalnız aynı Google hesabında bu betikle tamamlanmış ve kimliği eşleşen formu açar.
Öğrenci listesi/fotoğraflar sonradan sessizce değiştirilmez. Dönen gerçek
`responderUrl` sınıfa derse giren öğretmenler seçili olarak mevcut mesajlaşmaya
aktarılmalıdır; SMS/WhatsApp gönderimi mevcut kullanıcı onayıyla yapılmalıdır.
Betik kendisi mesaj göndermez.

### Görüşleri okuma

`function: okulOgretmenGorusYanitlari`, `parameters: [requestId, formId, 0]`.
Sonuçta `yanitlar`, `toplam`, `nextOffset` vardır; sonraki sayfa için dönen konum
kullanılır, `null` bitiştir. Sayfa boyutu 50'dir. FormApp soru kimlikleri betikte
tutulur. Yanıtlar `responseId`, `tarih`, `ogretmen`, `ders`, `sinifGorusu` ve
öğrenci kimliğine göre `ogrenciler` açıklama haritası olarak döner. Fotoğraflar
yanıt paketinde tekrar gönderilmez. Yenilemede responseId ile birleştirilmelidir;
sayfalama sırasında gelen/değişen yanıtlar için baştan yenileme yapılabilir.
Bu aşamada yanıtlar öğrenci/veli ana kayıtlarına yazılmaz.

## Hata ve tekrar deneme davranışı

- Aynı kimlik ve aynı içerik aynı formu verir; başka içerikle çağrı reddedilir.
- Yarım kalan, yayımlanmamış ve yanıtsız taslakta aynı soru sırasından devam edilir.
  Sorular dışarıdan değiştirilmişse üzerine yazılmaz veya silinmez.
- Google'da silinen forma erişim hatası döner; sessizce yeni form açılmaz.
- Fotoğraf içeriği, adlar ve token'lar loglanmaz. Kullanıcı özelliklerinde yalnız
  form kimliği, içerik özeti ve soru kimlikleri tutulur.
- FormApp.create ile kullanıcı özelliği kaydı Google'da tek atomik işlem değildir.
  Bu iki işlem arasında servis hatası olursa boş, yayımlanmamış bir taslak kalabilir.
  Bu nadir durumda Google Forms dosyalarını kontrol edin; otomatik dosya silme yapılmaz.
- Kişisel Apps Script depolama/çalışma kotaları geçerlidir. Kota hatasında
  mevcut form veya yanıtlar silinmez; hata uygulamada gösterilmelidir.

## Doğrulama ve mevcut sınır

Yerel test: `node --test google_apps_script/ogretmen_gorus.test.cjs`.
Sahte Google servisleriyle tekrar çağrı, yarım kalan iş, yanlış kimlik, fotoğraf
doğrulaması, yayımlama ve yanıt eşleşmesi kontrol edilir. Testler Google hesabına
bağlanmaz. Canlı dağıtım, gerçek görselin Google'da görünmesi ve Android'den
mesajlaşma gönderimi ayrıca doğrulanmalıdır. Flutter testleri gerçek Google
hesabına veya gerçek telefon numarasına mesaj göndermez.

## Uygulamada kullanım

1. **Sınıf Rehberliğim → sınıf → Toplantılar → 3. Görüş topla** kartını açın.
2. Gerçek ders öğretmenleri ve öğrenci listesini kontrol edin. Öğretmen yoksa
   aynı ekrandaki **Öğretmen ders programını aktar** düğmesini kullanın.
3. **Form ön izlemesi** bölümünde öğrenci fotoğraflarını ve soru alanlarını görün.
4. **Fotoğraflı formu hazırla** ile Google hesabını seçin ve veri aktarımını onaylayın.
   Form ve istek kimliği toplantıya bağlı olarak kaydedilir; tekrar açılışta aynı
   form kullanılır. Aynı isteği yeniden denemek için fotoğraflı öğrenci anlık
   görüntüsü yerel SQLite kaydında tutulur; erişim token'ı kaydedilmez.
5. **Öğretmenlere gönder** formu yayımlayıp yalnız ilgili sınıfın öğretmenleri
   seçili olarak mesajlaşmayı açar. Öğretmenlerden bazılarını seçimden
   çıkarabilirsiniz. Öğrenci/veli veya başka sınıf alıcısı bu akışa eklenmez.
6. **Ön İzle ve Onayla** ekranında alıcıları ve form bağlantısını kontrol edip
   SMS veya WhatsApp yolunu seçin. Eksik öğretmen telefonu mevcut tamamlama
   ekranında girilip öğretmen iletişim kaydına yazılabilir.
7. **Gelen görüşleri getir** öğretmenin genel sınıf görüşünü ve öğrenci
   açıklamalarını gösterir. Öğrenci/veli ana kayıtları otomatik değiştirilmez.

Form hazırlanınca öğrenci listesi sabitlenir. Sonradan değişen ad/fotoğraflar
mevcut formun ve yanıtların üzerine sessizce yazılmaz. Geçmiş toplantıların
görüşleri okunabilir; yeni form hazırlama ve gönderme kapalıdır.

Kaynaklar:
- [Form oluşturma ve yayımlama durumu](https://developers.google.com/apps-script/reference/forms/form-app#create(String,Boolean))
- [Görseli Blob ile ekleme](https://developers.google.com/apps-script/reference/forms/image-item#setImage(BlobSource))
- [API yürütme ve OAuth koşulları](https://developers.google.com/apps-script/api/how-tos/execute)
