const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');

// Google hesabına veya ağa erişmez; FormApp sözleşmesini sınar.
function ortam() {
  const props = new Map(), forms = new Map();
  let count = 0, nextItem = 1, failImage = false, locked = false;
  class Item {
    constructor(type) { this.type = type; this.id = nextItem++; this.title = ''; }
    getType() { return this.type; }
    getId() { return this.id; }
    getTitle() { return this.title; }
    setTitle(x) { this.title = x; return this; }
    setRequired(x) { this.required = x; return this; }
    asTextItem() { return this; }
    asListItem() { return this; }
    setChoiceValues(v) { this.choices = v; return this; }
    asParagraphTextItem() { return this; }
    asImageItem() { return this; }
    setImage(x) { if (failImage) { failImage = false; throw Error('foto servis hatası'); } this.image = x; return this; }
    setWidth(x) { this.width = x; return this; }
  }
  class Form {
    constructor(id) { this.id = id; this.items = []; this.responses = []; this.published = false; this.accepting = false; }
    getId() { return this.id; }
    getItems() { return [...this.items]; }
    getResponses() { return this.responses; }
    isPublished() { return this.published; }
    isAcceptingResponses() { return this.accepting; }
    getEditUrl() { return `https://docs.google.com/forms/d/${this.id}/edit`; }
    getPublishedUrl() { return `https://docs.google.com/forms/d/e/${this.id}/viewform`; }
    setDescription(x) { this.description = x; return this; }
    setPublishingSummary(x) { this.summary = x; return this; }
    setCollectEmail(x) { this.collectEmail = x; return this; }
    setConfirmationMessage(x) { this.confirmation = x; return this; }
    setPublished(x) { this.published = x; return this; }
    setAcceptingResponses(x) { this.accepting = x; return this; }
    add(type) { const i = new Item(type); this.items.push(i); return i; }
    addTextItem() { return this.add('TEXT'); }
    addListItem() { return this.add('LIST'); }
    addParagraphTextItem() { return this.add('PARAGRAPH_TEXT'); }
    addImageItem() { return this.add('IMAGE'); }
  }
  const api = vm.createContext({
    FormApp: {
      create(title, published) { assert.equal(published, false); const f = new Form('form_' + ++count); forms.set(f.id, f); return f; },
      openById(id) { if (!forms.has(id)) throw Error('Form bulunamadı'); return forms.get(id); }
    },
    PropertiesService: {getUserProperties: () => ({getProperty: k => props.get(k) || null, setProperty: (k,v) => props.set(k,v)})},
    LockService: {getUserLock: () => ({waitLock() { assert.equal(locked, false); locked = true; }, releaseLock() { locked = false; }})},
    Utilities: {
      DigestAlgorithm: {SHA_256: 'sha256'}, Charset: {UTF_8: 'utf8'},
      computeDigest: (a,s,c) => [...crypto.createHash(a).update(s,c).digest()],
      base64Decode: s => [...Buffer.from(s,'base64')],
      newBlob: (bytes,mime,name) => ({bytes,mime,name})
    }
  });
  vm.runInContext(fs.readFileSync(__dirname + '/OgretmenGorus.gs','utf8'),api);
  return {api, props, forms, count: () => count, fail: () => { failImage = true; }, locked: () => locked};
}
function istek() {
  return {requestId: '0123456789abcdef0123456789abcdef', kapsam: 'okul/1/2026/1/42',
    baslik: '9-C görüş', sinif: '9-C', yil: '2026-2027', ogrenciler: [
      {id: 1, no: '3001', ad: 'Birinci öğrenci', foto: {mime: 'image/png', base64: Buffer.from([137,80,78,71,13,10,26,10,0]).toString('base64')}},
      {id: 2, no: '3002', ad: 'İkinci öğrenci', foto: null}
    ]};
}
test('kurulum kontrolü veri oluşturmaz', () => {
  const o = ortam(); assert.equal(o.api.okulOgretmenGorusKurulumKontrol().ready,true);
  assert.equal(o.count(),0); assert.equal(o.props.size,0);
});
test('öğretmen ve ders seçenekleri dolu açılır liste oluşturur', () => {
  const o = ortam(), g = istek();
  g.ogretmenler = ['Öğretmen A', 'Öğretmen B']; g.dersler = ['Matematik', 'Fizik'];
  const r = o.api.okulOgretmenGorusFormOlustur(g), f = o.forms.get(r.formId);
  assert.equal(f.items[0].type, 'LIST'); assert.equal(f.items[1].type, 'LIST');
  assert.equal(f.items[0].choices.join('|'), g.ogretmenler.join('|'));
  assert.equal(f.items[1].choices.join('|'), g.dersler.join('|'));
});
test('fotoğraf ve ayrı açıklama; taslak gizli, özet kapalı, metadata fotoğraf içermez', () => {
  const o = ortam(), r = o.api.okulOgretmenGorusFormOlustur(istek()), f = o.forms.get(r.formId);
  assert.equal(r.ready,true); assert.equal(r.published,false); assert.equal(r.acceptingResponses,false);
  assert.equal(f.items.length,6); assert.equal(f.items[3].type,'IMAGE');
  assert.equal(f.items[4].type,'PARAGRAPH_TEXT'); assert.equal(f.items[5].type,'PARAGRAPH_TEXT');
  assert.equal(f.items[0].required,true); assert.equal(f.items[1].required,true); assert.equal(f.items[2].required,true);
  assert.equal(f.summary,false); assert.equal(f.collectEmail,false);
  assert.equal([...o.props.values()].join('').includes('Birinci'),false);
  assert.equal([...o.props.values()].join('').includes('base64'),false);
});
test('tekrar çağrı yeni form veya soru üretmez; içerik değişikliği reddedilir', () => {
  const o = ortam(), g = istek(), r = o.api.okulOgretmenGorusFormOlustur(g);
  assert.equal(o.api.okulOgretmenGorusFormOlustur(g).formId,r.formId); assert.equal(o.count(),1);
  g.ogrenciler[0].ad = 'Değişti';
  assert.throws(() => o.api.okulOgretmenGorusFormOlustur(g),/başka içerikle/);
  assert.equal(o.count(),1); assert.equal(o.locked(),false);
});
test('yarım kalan fotoğraftan devam eder; soru/form çoğalmaz', () => {
  const o = ortam(); o.fail();
  assert.throws(() => o.api.okulOgretmenGorusFormOlustur(istek()),/foto servis/);
  assert.equal(o.locked(),false);
  const r = o.api.okulOgretmenGorusFormOlustur(istek());
  assert.equal(o.count(),1); assert.equal(o.forms.get(r.formId).items.length,6);
});
test('yarım taslak dışarıdan değiştirilmişse üzerine yazmaz', () => {
  const o = ortam(); o.fail(); assert.throws(() => o.api.okulOgretmenGorusFormOlustur(istek()));
  const f = [...o.forms.values()][0]; f.items[0].title = 'Harici soru';
  assert.throws(() => o.api.okulOgretmenGorusFormOlustur(istek()),/dışarıdan/);
  assert.equal(f.items[0].title,'Harici soru');
});
test('yayımlanmış veya yanıt almış yarım forma dokunmaz', () => {
  for (const yanit of [false,true]) {
    const o = ortam(); o.fail(); assert.throws(() => o.api.okulOgretmenGorusFormOlustur(istek()));
    const f = [...o.forms.values()][0]; if (yanit) f.responses.push({}); else f.published = true;
    assert.throws(() => o.api.okulOgretmenGorusFormOlustur(istek()),/otomatik değiştirilmedi/);
  }
});
test('geçersiz kimlik, tekrar öğrenci, boş ad ve uygunsuz fotoğraf form açmaz', () => {
  const degisimler = [
    g => {g.requestId = 'x';}, g => {g.ogrenciler.push(g.ogrenciler[0]);},
    g => {g.ogrenciler[0].ad = ' ';}, g => {g.ogrenciler = [];},
    g => {g.ogrenciler[0].foto = {mime:'image/svg+xml',base64:'AAAA'};},
    g => {g.ogrenciler[0].foto.base64 = 'https://example.com/photo';},
    g => {g.ogrenciler[0].foto.base64 = 'AAAA';},
    g => {g.ogrenciler[0].foto.base64 = Buffer.alloc(102401).toString('base64');}
  ];
  for (const degistir of degisimler) {
    const o = ortam(), g = istek(); degistir(g);
    assert.throws(() => o.api.okulOgretmenGorusFormOlustur(g)); assert.equal(o.count(),0);
  }
});
test('yayımlama yalnız tamamlanmış aynı formda çalışır; tekrar güvenlidir', () => {
  const o = ortam(), g = istek(), r = o.api.okulOgretmenGorusFormOlustur(g);
  assert.throws(() => o.api.okulOgretmenGorusYayinla(g.requestId,'baska_form'),/uyuşmuyor/);
  const p = o.api.okulOgretmenGorusYayinla(g.requestId,r.formId);
  assert.equal(p.published,true); assert.equal(p.acceptingResponses,true);
  assert.equal(o.api.okulOgretmenGorusYayinla(g.requestId,r.formId).formId,r.formId);
  assert.equal(o.forms.get(r.formId).summary,false);
});
test('farklı hesap veya silinmiş form için sessizce yenisi açılmaz', () => {
  const o = ortam(), g = istek(), r = o.api.okulOgretmenGorusFormOlustur(g);
  const baska = ortam(); assert.throws(() => baska.api.okulOgretmenGorusYayinla(g.requestId,r.formId));
  o.forms.delete(r.formId); assert.throws(() => o.api.okulOgretmenGorusFormOlustur(g),/bulunamadı/);
  assert.equal(o.count(),1);
});
test('yanıtlar gerçek item kimlikleriyle öğrencilere eşlenir; 50li sayfalama', () => {
  const o = ortam(), g = istek(), r = o.api.okulOgretmenGorusFormOlustur(g), f = o.forms.get(r.formId);
  const vals = {0:'Öğretmen',1:'Matematik',2:'Sınıf görüşü',4:'İlk öğrenci görüşü',5:'  '};
  f.responses = Array.from({length:51},(_,i) => ({
    getId: () => 'yanit_' + i, getTimestamp: () => new Date('2026-10-28T09:00:00Z'),
    getItemResponses: () => Object.entries(vals).map(([j,v]) => ({getItem:()=>f.items[j],getResponse:()=>v}))
  }));
  const a = o.api.okulOgretmenGorusYanitlari(g.requestId,r.formId,0);
  assert.equal(a.yanitlar.length,50); assert.equal(a.nextOffset,50);
  assert.equal(a.yanitlar[0].ogrenciler['1'],'İlk öğrenci görüşü');
  assert.equal(a.yanitlar[0].ogrenciler['2'],undefined); assert.equal(a.yanitlar[0].ders,'Matematik');
  const b = o.api.okulOgretmenGorusYanitlari(g.requestId,r.formId,a.nextOffset);
  assert.equal(b.yanitlar.length,1); assert.equal(b.nextOffset,null);
  assert.throws(() => o.api.okulOgretmenGorusYanitlari(g.requestId,r.formId,-1));
  assert.throws(() => o.api.okulOgretmenGorusYanitlari(g.requestId,'yanlis',0));
});
