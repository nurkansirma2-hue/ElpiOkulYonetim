# GOOGLE FORM HESAP VE YETKİ STANDARDI

**Proje:** ElpiOkulYonetim  
**Kapsam:** Uygulamadaki Google Forms kullanan bütün modül ve iş akışları  
**Durum:** Onaylı proje standardı; uygulama kodunun çok kullanıcılı hâle getirildiği anlamına gelmez.

## 1. Amaç ve temel karar

Google Forms ile yapılan her işlem, işlemi başlatan uygulama kullanıcısının **kendi bağladığı Google hesabının gerçek izinleri** ve uygulama içindeki okul/öğretmen/profil/eğitim yılı kapsamı doğrulanarak yürütülür. Bir öğretmenin form işlemleri, geliştiricinin kişisel Gmail hesabına, sabit kişisel OAuth oturumuna veya yalnız geliştiriciye açık bir Apps Script dağıtımına bağımlı hale getirilmez.

**Temel ilke:** Kullanıcı hesabı ≠ uygulama profili ≠ form sahibi ≠ form yanıtlayıcısı. Bu kimlikler ayrı doğrulanır. Hesap bağlamak tek başına herhangi bir form üzerinde işlem yetkisi vermez.

Bu belge ürün davranışını ve uygulama öncesi doğrulama koşullarını tanımlar; Google'ın izinleri veya mevcut API özellikleri hakkında doğrulanmamış teknik vaat oluşturmaz.

## 2. Kapsamdaki işlemler

Form şablonu seçme, oluşturma, mevcut formu bağlama, formu açma/okuma, düzenleme, yayımlama, yanıt kabulünü açma/kapatma, paylaşım bağlantısını alma, yanıtları listeleme/yenileme, değerlendirme, yanıta bağlı düzenleme bağlantısı üretme, tekli/toplu yanıt silme, formu kaldırma/arşivleme ve izin/bağlantı yenileme aynı hesap-yetki prensibine tabidir.

Öğrenci bilgi formları, öğretmen görüşleri, proje ödevleri, rehberlik, toplantı, anket ve ileride eklenen Google Forms kullanan modüller bu standarda uyar. Mesajlaşma gönderimi kendi ayrı onay akışını korur.

## 3. Kimlik ve hesap seçimi

1. Kullanıcı, desteklenen Google hesabını uygulamanın mevcut ortak Google oturum altyapısıyla seçer ve gerekli kapsamlar için açık rıza verir.
2. Bir Google işlemi öncesinde etkin Google hesabı, uygulama profili, formun kayıtlı kimliği, form sahipliği/paylaşılmış erişimi ve istenen işlemin gerçek Google izni doğrulanır.
3. Uygulama aynı cihazdaki hesapları birbirine karıştırmaz. Hesap değiştiğinde önceki hesaba ait token, form bağlantısı ve yetki varsayımları yeni hesaba taşınmaz.
4. Hesap başına form ilişkisi, erişim ve son doğrulama bilgileri yalnız gerekli ölçüde tutulur. Token, sır veya gizli anahtar kaynak koda, GitHub'a, loglara veya açık yedeğe yazılmaz.
5. Oturum süresi dolmuş veya gerekli izin verilmemişse işlem durdurulur; kullanıcıya Türkçe, amaca yönelik yeniden bağlanma/izin adımı gösterilir. Hesap izni sessizce genişletilmez.

## 4. Google form sahipliği ve paylaşımı

- Varsayılan olarak öğretmen kendi oluşturduğu form üzerinde kendi yetkileriyle işlem yapar.
- Başkasının formuna erişim yalnız Google'ın gerçekten verdiği paylaşılmış yetki ve okul uygulamasındaki kapsam izinleriyle mümkündür.
- Formun URL'sine veya kimliğine sahip olmak, düzenleme ya da silme izni değildir.
- Form sahipliğini aktarma, ortak hesaba taşıma veya formu başka hesabın adına yeniden oluşturma otomatik yapılmaz; bu tür işlemler ayrıca açık kullanıcı kararı ve teknik uygunluk kontrolü gerektirir.
- Bireysel Öğretmen (Flutter/SQLite) ve Okul/Kurumsal (Flutter/API/SQL Server) veri alanları ayrıdır; birinin Google kaydı diğerine otomatik aktarılmaz.

## 5. Forms API ve Apps Script çalışma ilkeleri

1. Google Forms API'nin desteklediği işlemler, mümkünse etkin kullanıcının OAuth yetkisiyle doğrudan ve mevcut ortak servis üzerinden yapılır.
2. Forms API'nin doğrudan karşılamadığı işlemlerde (örneğin mevcut projedeki yanıt silme betiği) Apps Script veya başka bir aracının kullanımı **ayrıca değerlendirilir**. Çalıştırılabilir API'nin erişim modeli, gerekli OAuth kapsamları, Cloud projesi, dağıtım sürümü ve hesabın gerçek çalıştırma yetkisi belgelenir ve doğrulanır.
3. `MYSELF` / **Yalnızca ben** olarak dağıtılmış, tek bir hesaba bağlı betik **çok kullanıcılı çözüm sayılmaz**. Bu dağıtımın varlığı diğer öğretmenlerin hesabında çalışacağı anlamına gelmez.
4. Her öğretmene ayrı betik dağıtılması veya ortak hizmet üzerinden işlem yapılması ancak uygulanabilirlik, bakım, güvenlik, maliyet ve Google platform kuralları değerlendirildikten ve kapsam onaylandıktan sonra seçilir. Bu belge iki seçeneği de otomatik zorunlu tutmaz.
5. Uygulama, doğru dağıtım kimliğini ve yayımlanmış sürümün beklenen protokolünü işlemden önce doğrular. Kod düzenleyicisindeki güncel kodun yayımlanmış dağıtımda çalıştığı varsayılmaz. Sabit dağıtım kimliği herkes için evrensel varsayılan olarak kabul edilmez.
6. Hesap/betik yetkisi eksikse, başka kullanıcının hesabına veya geliştiricinin hesabına sessiz geçiş yapılmaz. İşlem güvenli biçimde durdurulur.

## 6. Silme ve diğer geri dönüşü zor işlemler

- Yanıt silme, form silme, yanıtlara erişimi kapatma ve yetki değiştirme gibi işlemler için mevcut açık onay kuralları geçerlidir.
- Her yanıt için **form kimliği + kesin Google yanıt kimliği + etkin hesap/yetki + yerel kayıt kapsamı** yeniden doğrulanır. Öğrenci adı, okul numarası veya listedeki sıra kesin yanıt kimliği yerine kullanılamaz.
- Google'da yanıtın silindiği doğrulanmadan yerel ham yanıt silinmez. Hata veya kısmi başarıda kalan kayıtlar ve sebep gösterilir; tekrarlı deneme yanlış kaydı silemez.
- Daha önce açık onayla öğrenci ana kaydına aktarılmış veriler ve ODY kayıtları korunur. Google E-Tablo kopyaları ile eski yedeklerin ayrı saklandığı açıkça belirtilir.
- Üretimdeki gerçek form/yanıt üzerinde otomatik test çalıştırılmaz; gerçek silme yalnız açık kullanıcı onaylı hedef kayıtla yapılır.

## 7. Ortak kullanıcı deneyimi

- Kullanıcı kurulum ayrıntılarını bilmek zorunda değildir. İlk kullanımda uygulama, Google hesabını seçme → yetkileri açıklama → erişimi doğrulama → işlemi sürdürme akışını Türkçe yönlendirir.
- Hesap uygun değilse **hangi hesapla bağlı olduğu, neyin eksik olduğu, hangi güvenli adımı atması gerektiği** açıklanır. Ham API hatası tek başına gösterilmez.
- Kullanıcının aynı formu yeniden oluşturmasına neden olabilecek sessiz tekrarlar engellenir. Mevcut taslak, Google form kimliği ve kurtarma akışları korunur.
- Mesaj paylaşımı, SMS/WhatsApp gönderme ve öğrenci bilgilerini güncelleme için mevcut ayrı kullanıcı onayları devam eder.

## 8. Mevcut kurulumun geçiş yaklaşımı

1. Mevcut form servisleri, ortak oturum, profil ayarları, Apps Script bağlantıları ve modül çağrıları haritalanır.
2. Önce mevcut tek hesaplı kullanım bozulmadan ikinci bir Google hesabında **salt okunur** oturum, form kimliği ve yetki davranışı sınanır.
3. Silme dâhil yazma işlemlerinin çok hesaplı mimarisi, Google platformunun gerçek erişim kuralları doğrulanarak ayrı bir uygulama adımında kararlaştırılır.
4. Eski formlar, onaylar, yerel veri, dağıtım kimlikleri ve yedekler kendiliğinden dönüştürülmez veya silinmez. Uyumsuz bağlantılar güvenli uyarıyla korunur.
5. Yeni kod geliştirmesi, Google Cloud/OAuth ayarlarının değiştirilmesi, Apps Script dağıtımının yenilenmesi ve gerçek formda işlem yapılması **ayrı yetki ve doğrulama kapılarıdır**.

## 9. Test ve regresyon kabul ölçütleri

En az şu durumlar uygun test ortamlarında değerlendirilir: A ve B Google hesaplarıyla bağımsız giriş; hesap değiştirme; aynı cihazda iki profil; kendi formu; paylaşılan form; erişimsiz form; eksik/süresi bitmiş OAuth izni; eski/yanlış Apps Script dağıtımı; oluşturma ve yeniden deneme; okuma/yayımlama/düzenleme; tekli/toplu silmede kısmi başarı; Google-yerel senkronizasyonu; Bireysel/Kurumsal ayrımı; mevcut Google formları ve öğrenci kayıtları için regresyon.

Gerçek cihaz ve iki ayrı Google hesabıyla uçtan uca doğrulama olmadan **çok kullanıcılı hazır** denilemez. Yapılmamış testler başarılı gösterilmez.

## 10. Üst kurallarla ilişki ve yetki sınırı

Bu standart `AGENTS.md`, `CALISMA_STANDARDI.md`, `KOMUTLAR.md`, `MIMARI_STANDARDI.md`, `YETKILENDIRME_STANDARDI.md`, `FORM_MODULU_STANDARTI.md` ve `TEST_VE_REGRESYON.md` ile birlikte uygulanır. Çelişkide veri koruyan ve yetkiyi genişletmeyen yaklaşım esas alınır; önemli çelişki kullanıcıya bildirilir.

**Bu dosyanın kabulü tek başına Flutter, Google Cloud, Apps Script veya GitHub üzerinde değişiklik yapma izni vermez.** GitHub'a uygulamak için `YAZ`; canlı hesapta kritik değişiklikler ve gerçek veri silme için ayrıca açık onay gerekir.
