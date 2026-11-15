# Komutlar

D/d yalnız devam onayıdır; yerel değişiklik için açık kapsam, GitHub için YAZ gerekir. TASARLA yalnız görsel tasarım; UYGULA onaylı görselin gerçek koda uygulanmasıdır ve YAZ değildir. APK yalnız açık istekle başlatılır; otomatik CI ayrı değerlendirilir. ODY ve MODÜL BİTTİ için ayrıca ../06_Proje_Yonetimi/DOSYA_VE_ODY_STANDARDI.md okunur.

## 18. OKU

**OKU / oku**, GitHub’daki ilgili dosyanın en güncel tam hâlini oku anlamına gelir.

OKU:

- Dosya değiştirmez.
- Commit veya push yapmaz.
- YAZ yetkisi vermez.

GitHub’da bulunan güncel dosya kullanıcıdan tekrar istenmez.

Yerel dosya ile GitHub arasında fark varsa bildirilir. Daha güncel yerel çalışma varken eski GitHub içeriğine göre değişiklik hazırlanmaz.

## 19. YAZ

**YAZ / yaz**, son onaylanan değişiklikleri uygulamak ve GitHub’a commit/push etmek için açık izindir.

Yalnızca onaylanan dosyalar, değişiklikler ve kapsam işleme alınır. YAZ kapsamı genişletmez.

YAZ olmadan commit, push veya GitHub’da dosya değişikliği yapılmaz.

Commit/push öncesinde:

1. Git durumu kontrol edilir.
2. Değişiklikler onaylanan kapsamla karşılaştırılır.
3. Kullanıcıya ait önceden var olan ve onay dışı değişiklikler commit’e alınmaz.
4. Güvenle ayrıştırılamayan değişiklik varsa durulur ve bildirilir.

Commit mesajı işi kısa ve anlaşılır açıklar.

İşlem sonunda GitHub’a gönderilen dosyalar kısaca listelenir. Push başarısız olursa gerçek hata bildirilir ve GitHub’a gönderme işlemi durdurulur; zorlayıcı yöntemlerle aşılmaya çalışılmaz.

## 20. ODY

**ODY = Onaylı Dosya**

ODY verilen dosya ilgili proje/modül kapsamında onaylı sürüm kabul edilir ve mevcut ODY düzeninde korunur.

Dosyanın yolu, sürümü veya içeriği ayırt edilebilir olmalıdır. Yalnızca sohbet hafızasında “onaylandı” demek yeterli değildir.

ODY eski sürümlerle karıştırılmaz. Yerel/GitHub içeriğiyle uyuşmazlık varsa fark değerlendirilir ve gerektiğinde kullanıcıya bildirilir.

ODY tek başına dosya değiştirme, commit veya push yetkisi vermez.

## 41. MODÜL BİTTİ

Kullanıcı “Modül bitti” dediğinde ilgili modül kapsamında oluşturulan veya değiştirilen dosyalar toplanır.

Gerçek dosya uzantıları ve proje klasör yolları korunur.

ZIP, mevcut proje yapısını esas alır. SQL/API/Flutter düzeni uygunsa kullanılır; kaynak yolları belirsizleştiren yapay klasörleme yapılmaz.

Modül dışı kullanıcı dosyaları ve hassas bilgiler pakete eklenmez.
