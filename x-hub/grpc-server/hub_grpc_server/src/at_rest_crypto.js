import crypto from 'node:crypto';

export const ENCRYPTED_RECORD_PREFIX = 'xhubenc:v1:';
const PAYLOAD_ALG = 'aes-256-gcm';

function isObject(v) {
  return !!v && typeof v === 'object' && !Array.isArray(v);
}

function toCanonicalValue(v) {
  if (Array.isArray(v)) return v.map((it) => toCanonicalValue(it));
  if (!isObject(v)) return v;
  const out = {};
  for (const k of Object.keys(v).sort()) {
    out[k] = toCanonicalValue(v[k]);
  }
  return out;
}

function ensureBuffer(input, label) {
  if (!Buffer.isBuffer(input)) {
    throw new Error(`invalid ${label}: expected Buffer`);
  }
  return input;
}

function ensureKey32(keyBytes, label) {
  const key = ensureBuffer(keyBytes, label);
  if (key.length !== 32) {
    throw new Error(`invalid ${label}: expected 32-byte key`);
  }
  return key;
}

function b64Encode(buf) {
  return Buffer.from(buf).toString('base64');
}

function b64Decode(raw, label) {
  const text = String(raw || '').trim();
  if (!text) throw new Error(`missing ${label}`);
  let out;
  try {
    out = Buffer.from(text, 'base64');
  } catch {
    throw new Error(`invalid ${label}: bad base64`);
  }
  if (!out.length) throw new Error(`invalid ${label}: empty`);
  return out;
}

function canonicalizeAad(aad) {
  return JSON.stringify(toCanonicalValue(isObject(aad) ? aad : {}));
}

function aesGcmEncrypt({ keyBytes, plaintextBytes, aad }) {
  const key = ensureKey32(keyBytes, 'aes key');
  const pt = ensureBuffer(plaintextBytes, 'plaintext bytes');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(PAYLOAD_ALG, key, iv);
  const aadText = canonicalizeAad(aad);
  cipher.setAAD(Buffer.from(aadText, 'utf8'));
  const ciphertext = Buffer.concat([cipher.update(pt), cipher.final()]);
  const tag = cipher.getAuthTag();
  return {
    iv_b64: b64Encode(iv),
    ct_b64: b64Encode(ciphertext),
    tag_b64: b64Encode(tag),
  };
}

function aesGcmDecrypt({ keyBytes, iv_b64, ct_b64, tag_b64, aad }) {
  const key = ensureKey32(keyBytes, 'aes key');
  const iv = b64Decode(iv_b64, 'iv');
  if (iv.length !== 12) throw new Error('invalid iv: expected 12 bytes');
  const ciphertext = b64Decode(ct_b64, 'ciphertext');
  const tag = b64Decode(tag_b64, 'tag');
  if (tag.length !== 16) throw new Error('invalid tag: expected 16 bytes');

  const decipher = crypto.createDecipheriv(PAYLOAD_ALG, key, iv);
  const aadText = canonicalizeAad(aad);
  decipher.setAAD(Buffer.from(aadText, 'utf8'));
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

function encodeEnvelopeJson(envelopeObj) {
  const json = JSON.stringify(envelopeObj);
  return `${ENCRYPTED_RECORD_PREFIX}${Buffer.from(json, 'utf8').toString('base64')}`;
}

function decodeEnvelopeJson(envelopeText) {
  const raw = String(envelopeText ?? '');
  if (!raw.startsWith(ENCRYPTED_RECORD_PREFIX)) return null;
  const payload = raw.slice(ENCRYPTED_RECORD_PREFIX.length);
  if (!payload) throw new Error('invalid encrypted envelope: empty payload');
  let parsed = null;
  try {
    const json = Buffer.from(payload, 'base64').toString('utf8');
    parsed = JSON.parse(json);
  } catch {
    throw new Error('invalid encrypted envelope: malformed payload');
  }
  if (!isObject(parsed)) throw new Error('invalid encrypted envelope: bad object');
  return parsed;
}

export function parseFixedKeyMaterial(raw) {
  const text = String(raw || '').trim();
  if (!text) return null;

  const tryB64 = (s) => {
    try {
      const out = Buffer.from(s, 'base64');
      return out.length === 32 ? out : null;
    } catch {
      return null;
    }
  };

  const tryHex = (s) => {
    if (!/^[0-9a-fA-F]{64}$/.test(s)) return null;
    try {
      const out = Buffer.from(s, 'hex');
      return out.length === 32 ? out : null;
    } catch {
      return null;
    }
  };

  if (text.startsWith('base64:')) return tryB64(text.slice('base64:'.length));
  if (text.startsWith('hex:')) return tryHex(text.slice('hex:'.length));
  return tryB64(text) || tryHex(text);
}

export function randomDekBytes() {
  return crypto.randomBytes(32);
}

export function wrapDekWithKek({ dekBytes, kekBytes, aad }) {
  const dek = ensureKey32(dekBytes, 'dek');
  const kek = ensureKey32(kekBytes, 'kek');
  return aesGcmEncrypt({ keyBytes: kek, plaintextBytes: dek, aad });
}

export function unwrapDekWithKek({ wrapped, kekBytes, aad }) {
  const kek = ensureKey32(kekBytes, 'kek');
  const clear = aesGcmDecrypt({
    keyBytes: kek,
    iv_b64: wrapped?.iv_b64,
    ct_b64: wrapped?.ct_b64,
    tag_b64: wrapped?.tag_b64,
    aad,
  });
  return ensureKey32(clear, 'unwrapped dek');
}

export function encryptTextWithDek({ plaintext, dekBytes, dekId, kekVersion, aad }) {
  const pt = Buffer.from(String(plaintext ?? ''), 'utf8');
  const dek = ensureKey32(dekBytes, 'dek');
  const did = String(dekId || '').trim();
  const kv = String(kekVersion || '').trim();
  if (!did) throw new Error('missing dekId');
  if (!kv) throw new Error('missing kekVersion');

  const sealed = aesGcmEncrypt({ keyBytes: dek, plaintextBytes: pt, aad });
  return encodeEnvelopeJson({
    v: 1,
    alg: PAYLOAD_ALG,
    dek_id: did,
    kek_version: kv,
    iv_b64: sealed.iv_b64,
    ct_b64: sealed.ct_b64,
    tag_b64: sealed.tag_b64,
  });
}

export function decryptTextWithDek({ envelopeText, dekBytes, aad }) {
  const parsed = decodeEnvelopeJson(envelopeText);
  if (!parsed) {
    return {
      plaintext: String(envelopeText ?? ''),
      encrypted: false,
      dek_id: '',
      kek_version: '',
    };
  }

  if (Number(parsed.v || 0) !== 1) {
    throw new Error('invalid encrypted envelope: unsupported version');
  }
  if (String(parsed.alg || '').toLowerCase() !== PAYLOAD_ALG) {
    throw new Error('invalid encrypted envelope: unsupported algorithm');
  }
  const clear = aesGcmDecrypt({
    keyBytes: ensureKey32(dekBytes, 'dek'),
    iv_b64: parsed.iv_b64,
    ct_b64: parsed.ct_b64,
    tag_b64: parsed.tag_b64,
    aad,
  });
  return {
    plaintext: clear.toString('utf8'),
    encrypted: true,
    dek_id: String(parsed.dek_id || ''),
    kek_version: String(parsed.kek_version || ''),
  };
}

export function parseEncryptedEnvelopeMeta(envelopeText) {
  const parsed = decodeEnvelopeJson(envelopeText);
  if (!parsed) return null;
  return {
    v: Number(parsed.v || 0),
    alg: String(parsed.alg || ''),
    dek_id: String(parsed.dek_id || ''),
    kek_version: String(parsed.kek_version || ''),
  };
}
