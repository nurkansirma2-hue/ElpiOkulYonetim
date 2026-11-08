/** Fotoğraflı öğretmen görüşü. Mevcut MYSELF API dağıtımına eklenir. */
function okulOgretmenGorusKurulumKontrol() {
  return {protocol: 'okul-ogretmen-gorus/v1', ready: true, version: 1};
}

/** Aynı requestId ve aynı içerikle tekrar çağrı aynı formu döndürür. */
function okulOgretmenGorusFormOlustur(istek) {
  const veri = ogGirdi_(istek);
  const hash = ogHash_(JSON.stringify(veri));
  const lock = LockService.getUserLock();
  lock.waitLock(10000);
  try {
    const props = PropertiesService.getUserProperties();
    const key = ogAnahtar_(veri.requestId);
    let kayit = JSON.parse(props.getProperty(key) || 'null');
    if (kayit && kayit.hash !== hash) {
      throw new Error('Bu istek başka içerikle kaydedilmiş. Mevcut form değiştirilmedi.');
    }
    if (!kayit) {
      // Fotoğraflar eklenirken form yanıtlayanlara açık değildir.
      const form = FormApp.create(veri.baslik, false);
      kayit = {formId: form.getId(), hash: hash, ready: false};
      // Öğrenci adları, fotoğraflar ve token kullanıcı özelliklerinde tutulmaz.
      props.setProperty(key, JSON.stringify(kayit));
    }
    const form = FormApp.openById(kayit.formId);
    if (kayit.ready) {
      ogSinifGorusuZorunlu_(kayit, form);
      return ogSonuc_(veri.requestId, kayit, form);
    }
    if (form.isPublished() || form.getResponses().length) {
      throw new Error('Tamamlanmamış form yayımlanmış veya yanıt almış; otomatik değiştirilmedi.');
    }
    form.setDescription(veri.sinif + ' • ' + veri.yil + '\n' +
      'Sınıfın genel durumunu ve görüş bildirmek istediğiniz öğrencileri değerlendirin.\n' +
      'Bu form yalnız sınıfta ders veren öğretmenlere yöneliktir. Bağlantıyı paylaşmayın.');
    form.setPublishingSummary(false);
    form.setCollectEmail(false);
    form.setConfirmationMessage('Görüşleriniz kaydedildi. Teşekkür ederiz.');

    // Kesilen çağrıda tamamlanmış sorular korunur; aynı sıradan devam edilir.
    const mevcut = form.getItems();
    let sira = 0;
    const sorular = {ogretmen: '', ders: '', sinif: '', ogrenciler: {}};
    function soru(tip, baslik, zorunlu, foto) {
      const onceki = mevcut[sira++];
      if (onceki && (String(onceki.getType()) !== tip || onceki.getTitle() !== baslik)) {
        throw new Error('Form soruları dışarıdan değiştirilmiş; otomatik üzerine yazılmadı.');
      }
      let item;
      if (tip === 'IMAGE') {
        item = onceki ? onceki.asImageItem() : form.addImageItem().setTitle(baslik);
        item.setImage(Utilities.newBlob(foto.bytes, foto.mime, 'ogrenci.' + foto.ext));
        item.setWidth(240);
      } else if (tip === 'LIST') {
        item = onceki ? onceki.asListItem() : form.addListItem().setTitle(baslik);
        item.setChoiceValues(foto).setRequired(zorunlu);
      } else if (tip === 'TEXT') {
        item = onceki ? onceki.asTextItem() : form.addTextItem().setTitle(baslik);
        item.setRequired(zorunlu);
      } else {
        item = onceki ? onceki.asParagraphTextItem() : form.addParagraphTextItem().setTitle(baslik);
        item.setRequired(zorunlu);
      }
      return String(item.getId());
    }
    sorular.ogretmen = soru(veri.ogretmenler ? 'LIST' : 'TEXT', 'Öğretmen adı', true, veri.ogretmenler);
    sorular.ders = soru(veri.dersler ? 'LIST' : 'TEXT', 'Girdiğiniz ders / dersler', true, veri.dersler);
    sorular.sinif = soru('PARAGRAPH_TEXT', 'Sınıfın genel durumu hakkındaki görüşünüz', true);
    veri.ogrenciler.forEach(o => {
      const baslik = (o.no ? o.no + ' • ' : '') + o.ad;
      if (o.foto) soru('IMAGE', baslik, false, o.foto);
      sorular.ogrenciler[o.id] = soru('PARAGRAPH_TEXT', baslik + ' — Öğrenci hakkındaki görüşünüz', false);
    });
    if (mevcut.length > sira) {
      throw new Error('Formda beklenmeyen ek sorular var; otomatik silinmedi.');
    }
    kayit.ready = true;
    kayit.sorular = sorular;
    props.setProperty(key, JSON.stringify(kayit));
    return ogSonuc_(veri.requestId, kayit, form);
  } finally {
    lock.releaseLock();
  }
}

/** Uygulamadaki ön izleme/onaydan sonra ayrıca çağrılır; mesaj göndermez. */
function okulOgretmenGorusYayinla(requestId, beklenenFormId) {
  const lock = LockService.getUserLock();
  lock.waitLock(10000);
  try {
    const kayit = ogKayit_(requestId, beklenenFormId);
    const form = FormApp.openById(kayit.formId);
    ogSinifGorusuZorunlu_(kayit, form);
    form.setPublishingSummary(false);
    form.setPublished(true);
    form.setAcceptingResponses(true);
    return ogSonuc_(requestId, kayit, form);
  } finally {
    lock.releaseLock();
  }
}

/** Mevcut formun yanıtlarını koruyarak genel görüş alanını zorunlu yapar. */
function ogSinifGorusuZorunlu_(kayit, form) {
  const soru = form.getItems().find(i => String(i.getId()) === kayit.sorular.sinif);
  if (!soru || String(soru.getType()) !== 'PARAGRAPH_TEXT') {
    throw new Error('Sınıf görüşü sorusu bulunamadı; form sorularını kontrol edin.');
  }
  soru.asParagraphTextItem().setRequired(true);
}

/** FormApp item kimlikleri kullanılır; Forms REST questionId ile karıştırılmaz. */
function okulOgretmenGorusYanitlari(requestId, beklenenFormId, offset) {
  const kayit = ogKayit_(requestId, beklenenFormId);
  if (offset === undefined || offset === null) offset = 0;
  if (!Number.isInteger(offset) || offset < 0) throw new Error('Yanıt sayfa konumu geçersiz.');
  const tum = FormApp.openById(kayit.formId).getResponses();
  const yanitlar = tum.slice(offset, offset + 50).map(r => {
    const alanlar = {};
    r.getItemResponses().forEach(v => { alanlar[String(v.getItem().getId())] = String(v.getResponse()); });
    const ogrenciler = {};
    Object.keys(kayit.sorular.ogrenciler).forEach(id => {
      const cevap = alanlar[kayit.sorular.ogrenciler[id]] || '';
      if (cevap.trim()) ogrenciler[id] = cevap;
    });
    return {
      responseId: r.getId(), tarih: r.getTimestamp().toISOString(),
      ogretmen: alanlar[kayit.sorular.ogretmen] || '',
      ders: alanlar[kayit.sorular.ders] || '',
      sinifGorusu: alanlar[kayit.sorular.sinif] || '', ogrenciler: ogrenciler
    };
  });
  const sonraki = offset + yanitlar.length;
  return {protocol: 'okul-ogretmen-gorus/v1', requestId: requestId,
    formId: kayit.formId, yanitlar: yanitlar, toplam: tum.length,
    nextOffset: sonraki < tum.length ? sonraki : null};
}

function ogAnahtar_(id) {
  if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{32,64}$/.test(id)) {
    throw new Error('Görüş formu istek kimliği geçersiz.');
  }
  return 'ogretmen-gorus-v1:' + id;
}

function ogKayit_(requestId, formId) {
  const kayit = JSON.parse(PropertiesService.getUserProperties().getProperty(ogAnahtar_(requestId)) || 'null');
  if (!kayit || !kayit.ready || kayit.formId !== formId) {
    throw new Error('Bu hesaba ait tamamlanmış görüş formu bulunamadı veya form kimliği uyuşmuyor.');
  }
  return kayit;
}

function ogSonuc_(requestId, kayit, form) {
  return {protocol: 'okul-ogretmen-gorus/v1', requestId: requestId,
    formId: kayit.formId, ready: kayit.ready, published: form.isPublished(),
    acceptingResponses: form.isAcceptingResponses(),
    editUrl: form.getEditUrl(), responderUrl: form.getPublishedUrl()};
}

function ogMetin_(deger, ad, max, bos) {
  if (typeof deger !== 'string' || deger.length > max || (!bos && !deger.trim())) {
    throw new Error(ad + ' geçersiz.');
  }
  return deger.trim();
}

function ogHash_(metin) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, metin,
    Utilities.Charset.UTF_8).map(b => ('0' + ((b + 256) % 256).toString(16)).slice(-2)).join('');
}

/** Tüm girdi ve fotoğraflar Google'da herhangi bir form açılmadan doğrulanır. */
function ogGirdi_(g) {
  if (!g || typeof g !== 'object' || Array.isArray(g)) throw new Error('Form isteği geçersiz.');
  ogAnahtar_(g.requestId);
  const sonuc = {
    requestId: g.requestId,
    kapsam: ogMetin_(g.kapsam, 'Okul/profil/yıl/atama/toplantı kapsamı', 300, false),
    baslik: ogMetin_(g.baslik, 'Form başlığı', 200, false),
    sinif: ogMetin_(g.sinif, 'Sınıf', 50, false),
    yil: ogMetin_(g.yil, 'Eğitim yılı', 30, false), ogrenciler: []
  };
  for (const alan of ['ogretmenler', 'dersler']) {
    if (g[alan] !== undefined) {
      if (!Array.isArray(g[alan]) || !g[alan].length || g[alan].length > 200) {
        throw new Error('Öğretmen ve ders seçeneklerini ders programından tamamlayın.');
      }
      sonuc[alan] = [...new Set(g[alan].map(v => ogMetin_(v, 'Açılır liste seçeneği', 300, false)))];
    }
  }
  if (!Array.isArray(g.ogrenciler) || !g.ogrenciler.length || g.ogrenciler.length > 100) {
    throw new Error('Formda 1 ile 100 arasında öğrenci olmalıdır.');
  }
  const ids = new Set();
  let toplam = 0;
  g.ogrenciler.forEach(o => {
    if (!o || !Number.isSafeInteger(o.id) || o.id <= 0 || ids.has(o.id)) {
      throw new Error('Öğrenci kimliği geçersiz veya tekrarlı.');
    }
    ids.add(o.id);
    const ogrenci = {id: o.id, no: ogMetin_(o.no, 'Okul numarası', 30, true),
      ad: ogMetin_(o.ad, 'Öğrenci adı', 200, false), foto: null};
    if (o.foto !== undefined && o.foto !== null) {
      const f = o.foto;
      if (!f || !['image/jpeg', 'image/png'].includes(f.mime) ||
          typeof f.base64 !== 'string' || !f.base64.length || f.base64.length > 140000 ||
          f.base64.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(f.base64)) {
        throw new Error('Fotoğraf PNG/JPEG ve en fazla 100 KB olmalıdır.');
      }
      const bytes = Utilities.base64Decode(f.base64);
      const b = bytes.map(x => (x + 256) % 256);
      const png = b.length >= 8 && [137,80,78,71,13,10,26,10].every((x,i) => b[i] === x);
      const jpg = b.length >= 4 && b[0] === 255 && b[1] === 216 && b[2] === 255;
      if (bytes.length > 102400 || !(f.mime === 'image/png' ? png : jpg)) {
        throw new Error('Fotoğraf türü veya boyutu geçersiz.');
      }
      toplam += bytes.length;
      if (toplam > 8 * 1024 * 1024) throw new Error('Toplam fotoğraf boyutu 8 MB sınırını aşıyor.');
      ogrenci.foto = {mime: f.mime, ext: png ? 'png' : 'jpg', bytes: bytes};
    }
    sonuc.ogrenciler.push(ogrenci);
  });
  return sonuc;
}
