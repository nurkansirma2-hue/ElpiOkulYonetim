# GitHub ve Codex

YAZ kuralları için ../01_Calisma/KOMUTLAR.md geçerlidir.

## 7A. HEDEFLİ İNCELEME VE CODEX KAYNAK TASARRUFU

1. Her görevde önce ilgili modül ve gerçek bağımlılıkları belirlenir.
2. İlk aşamada dosya adları, yolları ve semboller araştırılır. Proje kaynakları topluca okunmaz.
3. Değiştirilecek dosyanın güncel tam içeriği okunur. Diğer dosyalar yalnızca gerektiği ölçüde incelenir.
4. Ortak servis, model, navigasyon, veri kaynağı veya yetkilendirme etkileniyorsa inceleme kapsamı genişletilir.
5. Mevcut proje belgeleri ve önceki görev sonuçları kullanılır; güncellikleri doğrulanmadan gerçek kaynak yerine geçmez.
6. Gereksiz tekrarlanan analizler, geniş terminal çıktıları ve kapsam dışı testler yapılmaz.
7. Basit görevlerde hedefli analiz ve test; riskli görevlerde gerekli kapsamlı analiz ve test uygulanır.
8. Tam dosya teslimi gerekiyorsa uzun kodu sohbet içinde tekrarlamak yerine gerçek uzantılı dosya olarak sunmak tercih edilir.
9. OKU, YAZ, ODY, veri güvenliği, yetkilendirme ve regresyon kuralları aynen korunur.
10. Gerekli doğrulamalar tamamlandığında çalışma sonlandırılır. Kaynak tasarrufu gerekçesiyle zorunlu güvenlik kontrolleri atlanmaz.

## 21. YEREL/GITHUB GÜVENLİĞİ

Dosya değişikliği gerektiren görevden önce Git durumu kontrol edilir.

Önceden var olan yerel değişiklikler kullanıcıya ait kabul edilir; silinmez, resetlenmez, restore edilmez veya üzerine yazılmaz.

Yerel dosya GitHub’dan daha güncelse eski GitHub sürümü esas alınmaz. Erişilebilen yerel dosya kullanıcıdan tekrar istenmez; yalnızca inceleme veya hazırlık için önce push yapması zorunlu tutulmaz.

Kullanıcı değişiklikleri güvenle korunabiliyorsa onaylı kapsamda ilerlenebilir. Çakışma veya güvenle ayrıştırılamayan durum varsa kullanıcı kararı alınır.

Mevcut düzen korunur:

- **GithubdanGuncelle:** GitHub → bilgisayar
- **GitHubGuncelle:** Bilgisayar → GitHub

OKU/YAZ işlemleri için kullanıcıya gereksiz BAT çalıştırma yükü verilmez. Yerel güncelleme gerektiğinde mevcut düzen kullanılır.

Açık onay olmadan yıkıcı Git işlemleri, `git reset --hard`, `git clean -f`, `git clean -fd`, zorla checkout/restore veya force push yapılmaz.

Kullanıcı istemeden branch oluşturulmaz, değiştirilmez veya silinmez; merge/rebase yapılmaz.

## 33. CHATGPT / CODEX KARARINI KULLANICIYA YÜKLEME

Ana görüşme ve karar merkezi ChatGPT Okul Yönetim Projesidir.

Proje genelinde arama, çoklu dosya değişikliği, bağımlılık analizi, yerel build/test veya kapsamlı hata araştırması gerekiyorsa Codex kullanımı değerlendirilir ve gerekiyorsa işe başlamadan kullanıcı bilgilendirilir.

Basit OKU/YAZ işleri gereksiz yere Codex’e taşınmaz. Kullanıcı zaten uygun ortamda çalışıyorsa yeniden araç seçmesi istenmez.

Codex işi tamamlandığında ana geliştirme görüşmesine ChatGPT Projesinde devam etmek için gerekli kısa sonuç ve durum aktarılır.

## 34. CHATGPT – GITHUB – CODEX CLOUD SENKRONİZASYON GÜVENLİĞİ

1. GitHub `master` dalı projenin tek ana kaynağıdır. Bu, başka bir ortamda henüz GitHub'a gönderilmemiş kullanıcı değişikliklerini silme veya yok sayma izni değildir.
2. ChatGPT ve Codex Cloud, erişebildikleri ölçüde her kod değişikliği öncesinde GitHub'ın güncel hedef dal commit kimliğini ve kendi çalışma kopyalarının hangi commit'e dayandığını doğrular. Doğrulama yapılamıyorsa bunun nedeni raporlanır; eşitlik varsayılmaz.
3. Çalışma ortamı ile GitHub farklı commit'lerdeyse önce commit ve ilgili dosya farkları incelenir. Eski koddan yeni kodun üzerine körlemesine yazılmaz.
4. Kaydedilmemiş çalışmalar, kullanıcıya ait yerel değişiklikler, mevcut branch'ler ve açık PR'lar korunur. Bunlar otomatik silinmez, sıfırlanmaz veya ezilmez.
5. Codex Cloud'da önceden açılmış bir oturumun, GitHub'a yapılan yeni commit'lerle otomatik eşitlendiği varsayılmaz. Görev başlangıcında ve GitHub'a yazmadan önce güncellik yeniden kontrol edilir.
6. Çakışma varsa otomatik üzerine yazma, force push, reset, clean veya yetkisiz merge/rebase yapılmaz. Güvenle uzlaştırılamayan fark kullanıcıya bildirilir ve riskli işlem durdurulur.
7. GitHub'a yazmadan hemen önce hedef dalın son commit'i ve değiştirilecek dosyaların güncel sürümleri tekrar kontrol edilir. Yalnızca onaylanan kapsam yazılır; uzaktaki yeni değişiklikler korunur.
8. `UYGULA` çalışma ortamında onaylı geliştirme kapsamına izin verir; GitHub'da commit/push için ayrıca açık `YAZ` gerekir. `D`, `OKU` veya test başarısı bu yetkiyi vermez.
9. İşlem sonunda kaynak ve hedef commit kimlikleri, senkronizasyonun doğrulanıp doğrulanmadığı, yazılan dosyalar ve varsa çakışma veya erişim sınırlamaları kısa biçimde raporlanır.
10. Bu güvenlik kuralları hem ChatGPT hem Codex çalışmalarında geçerlidir. Sürekli/otomatik bulut eşitlemesi vaat etmez; mevcut üst standartları ve yetki sınırlarını değiştirmez.
