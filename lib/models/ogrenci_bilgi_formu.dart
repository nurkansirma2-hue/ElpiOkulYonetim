/// Rehberlik servisinin Öğrenci Bilgi Formu alanları. Anahtarlar form
/// geçmişindeki cevapları sürümler arasında korumak için sabittir.
const ogrenciBilgiFormuBolumleri = <String, List<String>>{
  'Öğrenci Bilgisi': [
    'Form tarihi',
    'Adınız Soyadınız',
    'Sınıfınız',
    'Okul numaranız',
    'Okulunuz',
    'Cinsiyetiniz',
    'Doğum yeriniz',
    'Doğum tarihiniz',
    'Adresiniz',
    'Okul öncesi eğitim aldınız mı?',
    'Ne yapmaktan hoşlanırsınız?',
    'Yakın zamanda taşındınız mı, okul değiştirdiniz mi?',
    'Kendinize ait teknolojik aletleriniz var mı? Varsa günde/haftada ne kadar süre kullanırsınız?',
    'Sürekli kullandığınız ilaç ve tıbbi cihaz var mı? Nedir?',
    'Sürekli bir hastalığınız var mı? Varsa nedir?',
    'Ders dışı faaliyetleriniz nelerdir?',
    'Hâlâ etkisi altında olduğunuz bir olay yaşadınız mı? Yaşamışsanız açıklayınız.',
  ],
  'Veli Bilgisi': [
    'Veli adı soyadı',
    'Veli yakınlığı',
    'Veli telefon numarası',
    'Veli eğitim durumu',
    'Veli mesleği',
  ],
  'Anne Bilgisi': [
    'Anne adı soyadı',
    'Anne doğum yeri / doğum tarihi',
    'Anne öz mü?',
    'Anne sağ mı?',
    'Anne engel durumu var mı?',
    'Anne eğitim durumu',
    'Anne mesleği',
  ],
  'Baba Bilgisi': [
    'Baba adı soyadı',
    'Baba doğum yeri / doğum tarihi',
    'Baba öz mü?',
    'Baba sağ mı?',
    'Baba engel durumu var mı?',
    'Baba eğitim durumu',
    'Baba mesleği',
  ],
  'Aile Bilgisi': [
    'Kaç kardeşsiniz?',
    'Ailenizin kaçıncı çocuğusunuz?',
    'Okula giden kardeş sayınız',
    'Aile üyelerinde sürekli bir hastalığı/engeli olan biri var mı? Varsa yazınız.',
    'Evinizde sizinle birlikte kim/kimler yaşıyor? Yakınlık derecelerini belirtiniz.',
  ],
};

List<String> get ogrenciBilgiFormuSorulari =>
    ogrenciBilgiFormuBolumleri.values.expand((s) => s).toList();

const googleOgrenciSecimSorusu =
    'Bilgilerini dolduracağınız öğrenciyi seçiniz.';
const googleElleKimlikSorulari = {
  'Adınız Soyadınız',
  'Okul numaranız',
  'Sınıfınız',
  'Okulunuz',
};

String googleOgrenciSecenegi(Map<String, Object?> o) =>
    '${o['OkulNo'].toString().trim()} – ${o['Ad'].toString().trim()} ${o['Soyad'].toString().trim()}'
        .replaceAll(RegExp(r'\s+'), ' ');

/// Ön izlemede onaylanan bir öğrenci formu. Boş değerler bir silme isteği değildir.
class RehberlikFormAktarimi {
  RehberlikFormAktarimi({
    required this.ogrenciId,
    required this.beklenenSonFormId,
    required Map<String, String> cevaplar,
  }) : cevaplar = Map.unmodifiable(cevaplar);
  final int ogrenciId;
  final int? beklenenSonFormId;
  final Map<String, String> cevaplar;
}
