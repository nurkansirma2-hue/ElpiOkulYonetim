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
