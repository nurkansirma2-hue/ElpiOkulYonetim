# Ortak form modülü

## Kapsam ve girişler

Formlarla Bilgi Toplama; öğrenci/veli bilgileri, fotoğraflı öğretmen görüşü, toplantı katılımı, anket/geri bildirim ve boş form şablonlarının ortak merkezidir. Toplantının Görüş topla kartı aynı öğretmen görüşü şablon ekranını açar. Yeni form akışı kapsam, sorular ve kontrol olmak üzere üç adımdır. Genel şablonlarda öğrenci konusu için üç kimlik alanı sabittir; boş formda da bu eşleştirme alanları korunur. Serbest soruların türü, sırası ve zorunluluğu düzenlenebilir. Veli ilişkisi sorularının koşullu doğrulama kuralları korunur. Yanıt alınmış formun soruları değiştirilemez; mevcut güvenli ad düzenlemesi devam eder.

## Ortak kayıt ve uyumluluk

Mevcut BilgiToplama tabloları ve toplantı kapsamlı UygulamaAyarlari kayıtları korunur. Yeni tablo, paket veya şema sürümü yoktur. Şablon/durum alanları `bilgi_form_yonetim`, taslak tekrar koruması `bilgi_form_taslak_istegi`, kişi bağları `bilgi_form_alicilari` ayarlarında tutulur. Öğretmen görüşünün yanıt önbelleği ve silme işaretleri mevcut toplantı form kaydındadır. Tam SQLite yedeği UygulamaAyarlari kayıtlarını da taşır; yeni durum ve önbellek alanlarının geri yüklenmesi test edilir. Eski formlar şablon metadatası olmadan açılabilir.

## Durumlar

- Taslak: form henüz yayımlanmamıştır veya yayımlandığına ilişkin kayıt yoktur.
- Yanıt bekleniyor: yayımlanmış/yanıt alınmış, elle tamamlanmamış form.
- Tamamlandı: yanıt alımı kapatıldıktan sonra kullanıcının verdiği durum.
- Arşiv: kapatılmış formun listede arşiv filtresine taşınması; silme değildir.

Yanıt alımı açma/kapatma Google’dan doğrulanır; yerel durum ardından güncellenir. Kapatma yayımlanmamış formu kendiliğinden yayımlamaz. Açma tamamlandı/arşiv işaretlerini kaldırır. Kapatılmış formda mevcut yanıtlar kontrollü değerlendirilebilir. Form yayımlama, paylaşım başlatma, mesaj gönderim onayı ve yanıt alınması ayrı olaylardır. Sırf yanıt geldiği için paylaşım başlatıldı sayılmaz. Karttaki sayılar uygulamaya alınan yanıtların bilinen durumudur; Google hesabındaki son durumu görmek için yenileme gerekir.

## Kapsam, alıcı ve kimlik

Formun hangi öğrenciler hakkında olduğu, yanıtlayacak grup ve bağlantının gönderileceği kişiler farklı kavramlardır. Seçim ve iletişim kaynağı Mesajlaşma’nın ortak bileşenidir; bağımsız rehber veya gönderim altyapısı oluşturulmaz. Aynı öğrencinin tekrar yanıtları tamamlanma sayısını artırmaz. Güvenilir kimlik eşleşmesi olmayan yanıtlar ayrı tutulur. Karışık/öğretmen alıcılı genel formlarda kişi sayısı tahmin edilmez.

Öğretmen görüşlerinin mevcut Google şablonunda yanıtlayan adı alınır; kalıcı öğretmen kimliği doğrulanmaz. Bu nedenle yanıttan otomatik öğretmen tamamlama sayısı veya yanıt vermeyen öğretmen listesi türetilmez. Kullanıcı öğretmenleri seçip Seçililere hatırlat ile mevcut Mesajlaşma üzerinden hatırlatma hazırlayabilir. Genel öğrenci/veli formlarında güncel yanıtlar alındıktan sonra güvenilir öğrenci eşleşmesi ve kayıtlı alıcı bağlarıyla eksiklere hatırlatma hazırlanır. Belirsiz eşleşme varsa otomatik hatırlatma durur.

Okul, öğretmen profili, eğitim yılı, ders kapsamı ve hassas toplantı yetkileri korunur. Hassas toplantılar kilit açılmadan genel katalogda gösterilmez; kendi ekranından açılır. Biten atama/pasif sınıf salt okunur açılır. Uzun Google işlemlerinden önce/sonra kapsam doğrulanır.

## Google, paylaşım ve yeniden deneme

Ortak modül mevcut Forms API ve özel fotoğraflı Apps Script adaptörünü kullanır. Fotoğraflar açık bir URL’ye yüklenmez. Formun yayımlandığı, yanıt kabul ettiği ve bağlantısı doğrulanmadan Mesajlaşma açılmaz. Yalnız seçilen kişi bağları aktarılır. SMS/WhatsApp seçimi, mesaj düzenleme, telefon kontrolü, tekrar numaraları birleştirme, ön izleme ve onay mevcut modülde kalır. WhatsApp’ın açılması gönderildi sayılmaz.

Aynı taslak isteği ikinci yerel kayıt oluşturmaz; farklı içerik aynı kimlikle sessizce yazılmaz. Fotoğraflı formun istek kimliği korunur. Genel Forms API oluşturmasında Google kimliği biliniyorsa yarım kalan istek aynı formda sürer. Kimlik dönmeden bağlantı kopmuşsa otomatik tekrar oluşturma engellenir; mevcut Google formunu bağlama kurtarması kullanılır.

## Yanıt yönetimi ve silme

Ayrıntı ekranı Özet, Yanıtlar ve Değerlendirme sekmelerinden oluşur. Genel formlarda eski/yeni bilgi karşılaştırması ve açık onay korunur. Anket/katılımın seçenek, evet-hayır ve sayı cevapları özetlenir. Öğretmen görüşleri öğretmen ve öğrenci bazında gösterilir; öğrenci kimlik/iletişim bilgilerini otomatik değiştirmez.

Yanıt tekli veya seçilerek/toplu silinebilir. Önce kullanıcı onayı alınır, sonra doğru form ve yanıt kimliğiyle Google’dan silinir. Silinme doğrulanmadan yerel ham yanıt kaldırılmaz. Google hâlâ yanıtı gösteriyorsa, yetki/bağlantı hatası varsa veya yerel kapsam değişmişse yerel kayıt korunur. Toplu işlemde kısmi başarı ve kalan kayıtlar gösterilir. Silinen öğretmen görüşü gecikmiş bir yenilemeyle geri gelmez. Daha önce onaylanıp öğrenci kaydına aktarılmış bilgiler korunur.

Bağlı Google E-Tablo kopyaları ve eski yedekler bu silme işlemine dahil değildir. Bu sınır silme onayında gösterilir. Testler gerçek Google yanıtlarını veya kullanıcı kayıtlarını silmez.

## Doğrulama

Otomatik testler şablon/sekme ve dar ekran kullanımını, kapsam/yetki denetimini, tekrar oluşturma korumasını, yayımlama başarısızlığında paylaşımın durmasını, yanıt tekrar sayımını, seçili/kısmi silmeyi, ham cevap temizliğini ve mevcut öğrenci bilgilerinin korunmasını kapsar. Telefon boyutunda üç sekme uygulamanın NotoSans yazı tipiyle ayrıca görüntülenir.

Canlı Google hesabında form oluşturma/yayımlama, gerçek cihazdaki SMS/WhatsApp geçişleri ve yayımdaki Apps Script sürümü ayrıca doğrulanmalıdır. Bu geliştirme kendiliğinden Apps Script dağıtımı, commit, push veya gerçek mesaj gönderimi yapmaz.

## Rehberlik kartının ortak yeni form başlangıcı

Öğrenci Tanıma Formu kartı artık doğrudan ortak Yeni bilgi formu ekranını açar. Form adı Öğrenci Bilgi Formu olarak gelir. Aktif rehberlik sınıfı, Velisi hedefi ve o sınıfın bütün aktif öğrencileri seçilidir; açılır listeler kapalıdır, arama kendiliğinden odaklanmaz. Sınıf ve kişiler mevcut yetkili alıcı kaynağından gelir; kullanıcı seçimi değiştirebilir. Normal Yeni form akışı boş seçimle başlamaya devam eder.

`RehberlikBilgiFormScreen` yalnız başlangıç kapsamını doğrulayıp mevcut ortak üç adımlı düzenleyiciyi kullanır. Taslak ortak BilgiToplama tablolarına ve form merkezine kaydolur, sonra ortak ayrıntı ekranı açılır. Sayfayı açmak Google formu oluşturmaz. Kaydetmeden önce rehberlik ataması, sınıf, profil ve yıl yeniden kontrol edilir.

Eski altı aşamalı Google tanıma sayfası ile uyumluluk sayfası kaldırılmıştır; bu sayfalara normal veya eski katalog üzerinden yönlendirme kalmamıştır. Önceki RehberlikGoogleForm kayıtları, Google bağlantıları ve tanıma fişi/onay geçmişi silinmez veya yeni tablolara otomatik dönüştürülmez. Öğrenciye ait mevcut tanıma fişleri kendi geçmiş ekranlarında korunur. Yeni formlar bundan sonra ortak oluşturma, paylaşım ve yanıt yönetimi akışını kullanır.

## Sabit Google hazırlama eylemi

Yeni formun son adımında Taslağı kaydet yerine Google Formu Hazırla bulunur. Yerel kayıt arka planda korunur, ortak ayrıntı ekranı açılır ve Google hazırlama otomatik başlar. Ayrı bir ikinci hazırlama tıklaması gerekmez; form yayımlanır ve kayıtlı alıcılarla mevcut Mesajlaşma ön izleme/onay ekranı açılır; SMS/WhatsApp gönderimi kullanıcı onayında kalır. Hata halinde aynı yerel form ve alıcı bağları korunur. Mevcut taslaklar aynı sabit düğmeyle hazırlanır veya sürdürülür.

Ana eylem sağa hizalı, ipucu açıklamalı sabit alt alandadır. İçeriğin üzerinde yüzen bir katman değildir; Scaffold bu alanı içerikten ayırır. Geri ve Devam işlemleri de adım boyunca bu alanı kullanır. Klavye açıldığında düğme görünür alana taşınır. Testler 320 piksel genişlikte içerikle çakışmama, kaydırmada sabit kalma, klavye açıklığı, tekrar dokunmada tek oluşturma ve Google hatasında kaydın korunmasını doğrular.


## Formdan doğrudan mesaj onayı

Google hazırlama başarılı olduğunda kayıtlı alıcı bağları yeniden seçim istenmeden Mesajlaşma modülüne aktarılır. Form yayımlama doğrulanmadan mesaj ekranı açılmaz. Kayıtlı alıcısı olmayan eski formlarda Alıcılar düğmesiyle seçim yapılır. Gönderim geçmişi otomatik ön izlemenin önüne geçmez. Eksik telefonlar, tekrar eden numaralar, SMS/WhatsApp seçimi ve gönderim takibi mevcut modülün akışındadır; ekranın açılması gönderildi sayılmaz.

Alıcılar, yanıt alımını aç/kapat, hatırlatma ve mesaj metnini düzenleme sabit alt işlem çubuğundadır. Mesaj düğmesi aynı Mesajlaşma düzenleyicisini kayıtlı alıcılarla açar. Tamamlama, arşiv ve hesap işlemleri Diğer menüsündedir. Alt çubuk içerik için ayrılan alanın dışındadır.

Formdan doğrudan onay akışında Mesajlaşma hazırlama sayfası gösterilmez. Mevcut modülün onay ve eksik telefon pencereleri form üzerinde açılır; vazgeçildiğinde forma dönülür. Başlatılan toplu gönderimin takip ekranı korunur. Mesaj düğmesiyle açıkça düzenleme istendiğinde ortak düzenleyici kullanılmaya devam eder.


## Öğrenci Bilgi Formu kimlik seçimi

Yeni Öğrenci ve veli bilgileri / Öğrenci Bilgi Formu şablonu, üç serbest kimlik alanı yerine zorunlu Öğrenciyi seçin açılır listesi oluşturur. Yalnız formun hedef öğrencileri sınıf • okul numarası • ad soyad olarak gösterilir. Seçeneklerin etiketleri ve öğrenci kimlikleri mevcut soru kaydının Secenekler alanında birlikte anlık görüntü olarak korunur; Google'a yalnız görünen etiket gönderilir. Yanıt, etiketin kayıtlı anlık görüntüsünden öğrenci kimliğine bağlanır; güncel yetki ve form hedefi tekrar denetlenir. Tanımsız/boş seçim kaydedilmez. Onay öncesinde öğrenci bilgisi değişmez.

Yanıtı olmayan yeni tip formlar düzenlenirken hedef değişikliğiyle liste yeniden oluşturulur. Önceden oluşturulmuş üç kimlik sorulu formlar ve yanıtları aynı sözleşmeyle çalışmaya devam eder; yayımlanmış eski formların soruları kendiliğinden değiştirilmez.


## Öğretmen görüşünde yerinde mesaj ve pencere akışı

Öğretmen görüşü Özet ekranı seçili ders öğretmenleriyle birlikte düzenlenebilir mesaj metnini gösterir. Form oluşturulmadan önce {FormBaglantisi} yer tutucusu bulunur; hazırlama/yayın doğrulaması tamamlanınca güncel bağlantı eklenir. Kullanıcının metin düzenlemesi yükleme ve hazırlama sırasında korunur.

Mesaj at ve Seçililere hatırlat mevcut Mesajlaşma motorunu seçili öğretmenlerle doğrudan onay kipinde açar. Hazırlama ve geçmiş sayfaları gösterilmez. Onay, eksik telefon tamamlama, SMS/WhatsApp seçimi ve toplu takip aynı mevcut altyapıyı kullanır; bu modülde toplu takip de pencere içinde gösterilir. Atla ve Gönderdim kontrollerinin kayıt anlamı değişmez; WhatsApp açılması gönderildi sayılmaz. İşlemden vazgeçildiğinde veya takip kapandığında kaynak forma dönülür.


Öğretmen görüşünün Özet, Yanıtlar ve Değerlendirme sekmelerindeki eylemler ortak sayfanın sabit alt işlem alanında gösterilir. Form ön izlemesi ve dört saniyelik ipucu da bu alandadır. Özet: mesaj, ön izleme, hatırlatma, yanıt getirme; Yanıtlar: yenileme, ön izleme, görünürleri seçme, seçilenleri silme; Değerlendirme: yenileme, ön izleme ve mesaj. Fazla işlemler Diğer menüsündedir. Silme için satır seçimi ve mevcut onay gereklidir. Salt okunur kayıtlarda yazma işlemleri gösterilmez.
