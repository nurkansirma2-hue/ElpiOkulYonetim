# OKUL YÖNETİM PROJESİ — AGENTS.md

Bu dosya kök Flutter proje dizini ve alt dizinleri için geçerlidir. Alt dizinlerde özel AGENTS.md varsa çelişmeyen kurallar birlikte uygulanır. Ana amaç minimum müdahale ile gerçek ihtiyacı çözmek; otonom düşünme otonom yetki değildir. YAZ olmadan GitHub değişikliği, commit veya push yapılmaz. OKU salt incelemedir. Güncel gerçek proje ve kullanıcı verileri korunur. Kritik işlemler açık onay gerektirir.

## Proje konumu ve GitHub deposu

- Bu Windows bilgisayarındaki ana proje klasörü `C:\OkulYonetim` yolundadır.
- GitHub deposu `nurkansirma2-hue/ElpiOkulYonetim` adresindedir.
- Dosya değiştirmeden önce geçerli çalışma klasörünün hedef proje kopyasına ait olduğunu ve Git uzak adresinin bu depoyu gösterdiğini doğrula. Codex worktree veya bulut kopyasında ilgili çalışma kökünü ve depo kimliğini doğrula.

## Kullanıcıya bildirim ve ilerleme aktarımı

- Bildirimlerde, ilerleme mesajlarında ve sonuç raporlarında kullanıcının ana projesi `C:\OkulYonetim` ve yapılan işin sonucu esas alınır.
- Stage, geçici hazırlık klasörü, worktree ve benzeri iç çalışma adları veya yolları rutin bildirimlerde öne çıkarılmaz. Kullanıcı açıkça sorarsa veya gerçek bir engeli, gerekli izni ya da kullanıcıdan beklenen işlemi açıklamak için zorunluysa belirtilir.
- Geçici çalışma dosyalarının yönetimi ve gerekli aktarım/doğrulama AI tarafından yapılır; kullanıcıya bu klasörleri takip etme veya eşitleme yükü verilmez.
- Hazırlanan değişiklik ile ana projeye uygulanmış değişiklik açıkça ayrılır. Gerçek hedef, hata, eksik aktarım veya gerekli onay gizlenmez; başarı durumu doğru bildirilir.

## Talimat yükleme
Her proje görevinde aşağıdaki temel belgelerin güncel içeriklerini oku; ardından tablodaki ilgili belgelerin tamamını oku. Bu bir programlama importu değil, zorunlu okuma yönergesidir. Birden çok kapsam varsa birleşimini uygula; kapsam genişlerse yeniden değerlendir. İlgisiz kaynakları topluca okuma. Erişilemeyen zorunlu belgeyi bildir; güvenli uygulama için gerekliyse değişikliği durdur. Alt belge kendi başına yetki vermez. Önemli çelişkilerde güvenli yaklaşımı koru ve kullanıcı kararı al.

- [ CALISMA_STANDARDI ](docs/01_Calisma/CALISMA_STANDARDI.md)
- [ KOMUTLAR ](docs/01_Calisma/KOMUTLAR.md)
- [ OZ_DENETIM_STANDARDI ](docs/05_Kalite/OZ_DENETIM_STANDARDI.md)

## Göreve göre yönlendirme

| Standart | Ne zaman okunur |
|---|---|
| [MIMARI_STANDARDI.md](docs/02_Mimari/MIMARI_STANDARDI.md) | Mimari / kod değişikliği |
| [VERITABANI_STANDARDI.md](docs/02_Mimari/VERITABANI_STANDARDI.md) | SQL / SQLite / veri |
| [YETKILENDIRME_STANDARDI.md](docs/02_Mimari/YETKILENDIRME_STANDARDI.md) | Yetki / yeni modül / kapsam |
| [TASARLA.md](docs/03_Tasarim/TASARLA.md) | TASARLA |
| [IMPORT_EXPORT_STANDARDI.md](docs/04_Ortak_Sistemler/IMPORT_EXPORT_STANDARDI.md) | Import / export |
| [TEST_VE_REGRESYON.md](docs/05_Kalite/TEST_VE_REGRESYON.md) | Hata / test / kod değişikliği |
| [KOD_SUNUM_STANDARDI.md](docs/05_Kalite/KOD_SUNUM_STANDARDI.md) | Kod teslimi |
| [GITHUB_CODEX_STANDARDI.md](docs/06_Proje_Yonetimi/GITHUB_CODEX_STANDARDI.md) | Git / Codex / proje inceleme |
| [DOSYA_VE_ODY_STANDARDI.md](docs/06_Proje_Yonetimi/DOSYA_VE_ODY_STANDARDI.md) | ODY / ZIP |
| [UI_STANDARDI.md](docs/03_Tasarim/UI_STANDARDI.md) | Flutter UI |
| [GORSEL_UYGULAMA.md](docs/03_Tasarim/GORSEL_UYGULAMA.md) | UYGULA |
| [FORM_MODULU_STANDARTI.md](docs/04_Ortak_Sistemler/FORM_MODULU_STANDARTI.md) | Form / Google Forms |
| [GOOGLE_FORM_HESAP_VE_YETKI_STANDARDI.md](docs/04_Ortak_Sistemler/GOOGLE_FORM_HESAP_VE_YETKI_STANDARDI.md) | Google Forms hesabı / OAuth / Apps Script / form erişimi ve bütün Google form işlemleri |
| [MESAJLASMA_STANDARTI.md](docs/04_Ortak_Sistemler/MESAJLASMA_STANDARTI.md) | Mesaj / alıcı / form paylaşımı |
| [ORTAK_LISTE_ARAC_CUBUGU.md](docs/04_Ortak_Sistemler/ORTAK_LISTE_ARAC_CUBUGU.md) | Ortak liste kalıbı açıkça istendiğinde |

Flutter ekranı oluşturulurken veya değiştirilirken docs/03_Tasarim/UI_STANDARDI.md okunur; mevcut ortak UI bileşenleri kullanılır. Form işlemlerinde FORM_MODULU_STANDARTI ve GOOGLE_FORM_HESAP_VE_YETKI_STANDARDI birlikte okunur. Form paylaşımı veya mesajlaşma bağlantısı varsa MESAJLASMA_STANDARTI da okunur. Google Forms işlemleri etkin kullanıcının kendi Google hesabının gerçek izinleri ve uygulama kapsamı doğrulanarak yürütülür; geliştiricinin kişisel hesabına bağımlı varsayılmaz. Ortak liste standardı otomatik genel dönüşüm yetkisi değildir. GitHub işlemlerinde GitHub/Codex standardı zorunludur. Yeni standart eklendiğinde yönlendirme tablosu kullanıcı onayıyla güncellenir.

## Zorunlu veri sürekliliği — kritik koruma

- **Temel ilke:** Uygulama kaldığı yerden devam eder; mevcut kullanıcı veritabanı ve yedekler güncelleme, APK, kod, migration veya Git senkronizasyonu nedeniyle otomatik sıfırlanmaz, silinmez, boş veritabanıyla değiştirilmez.
- Bireysel SQLite ve kurumsal SQL Server verileri ayrı korunur. Mod değiştirmek veri silmez. Hata durumunda sessizce boş veritabanına geçilmez.
- Veri etkili şema değişikliklerinde doğrulanmış geri dönüş yedeği, sürümlü veri koruyan migration ve gerekli kayıt/uyumluluk testleri şarttır. Yedekleme kaynak veriyi değiştirmez; geri yükleme mevcut veritabanını otomatik ezmez.
- **Genel `YAZ` komutu veri silmeye/sıfırlamaya, veri kaybettiren migration'a veya mevcut veri üzerine geri yüklemeye izin vermez.** Bunlar için riskleri gösteren ayrıca açık ve özel kullanıcı onayı gerekir.
- Test APK'sı ve gerçek uygulama verileri ayrıdır. Uygulama kaldırma, cihaz kaybı ve benzeri durumlar için bağımsız yedek gerekir.
- Her veritabanı/yedek görevi için ayrıntılı ve bağlayıcı [VERITABANI_STANDARDI.md](docs/02_Mimari/VERITABANI_STANDARDI.md) okunur. Yapılmayan veri koruma veya geri yükleme testi başarılı sayılmaz.

## SON İLKE

Kullanıcı AI’yı yönetmekle uğraşmamalı; projesini yönetmelidir.

AI’nın görevi sürekli yeni prompt beklemek değil; hedefi anlamak, mevcut sistemi kullanmak, öngörülebilir eksikleri bulmak, çözümünü eleştirmek, gerekli testleri yapmak ve kullanıcının gerçekten karar vermesi gereken noktaya olgun bir sonuçla gelmektir.

AI kullanıcının yerine yetki kullanmaz, tercih uydurmaz ve mükemmellik bahanesiyle sonsuz geliştirme döngüsüne girmez.

