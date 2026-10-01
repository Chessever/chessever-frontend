// Pure WebCrypto verifier; also exercised by offline Node tests.
export function parseCallback(url: string) {
  const parsed = new URL(url);
  const query = parsed.search.slice(1);
  if (query.length > 8192) throw new Error('invalid_callback');
  const marker = query.indexOf('&signature=');
  if (marker < 1 || !/^&signature=[^&]+&key_id=\d+$/.test(query.slice(marker))) {
    throw new Error('invalid_signature_layout');
  }
  const params = parsed.searchParams;
  for (const key of params.keys()) {
    if (params.getAll(key).length !== 1) throw new Error('duplicate_parameter');
  }
  const required = ['ad_unit', 'custom_data', 'user_id', 'transaction_id', 'timestamp', 'signature', 'key_id'];
  for (const key of required) if (!params.get(key)) throw new Error('missing_parameter');
  if (!/^[\da-f-]{36}$/i.test(params.get('custom_data')!) ||
      !/^[\da-f-]{36}$/i.test(params.get('user_id')!) ||
      !/^[\w-]{1,256}$/.test(params.get('transaction_id')!)) throw new Error('invalid_parameter');
  return { params, signed: new TextEncoder().encode(query.slice(0, marker)) };
}

function decode64(value: string) {
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
}

// Google's ECDSA signatures are DER; WebCrypto requires fixed-width r || s.
export function derToRaw(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  if (bytes.length < 8 || bytes[0] !== 0x30 || bytes[1] !== bytes.length - 2) throw new Error('invalid_der');
  let offset = 2;
  const raw = new Uint8Array(64);
  for (let part = 0; part < 2; part++) {
    if (bytes[offset++] !== 2) throw new Error('invalid_der');
    let size = bytes[offset++];
    if (!size || size > 33 || offset + size > bytes.length) throw new Error('invalid_der');
    let integer = bytes.slice(offset, offset + size);
    offset += size;
    if (integer[0] & 0x80) throw new Error('negative_der');
    if (integer.length === 33) {
      if (integer[0] !== 0) throw new Error('invalid_der');
      integer = integer.slice(1); size--;
    }
    raw.set(integer, part * 32 + 32 - size);
  }
  if (offset !== bytes.length) throw new Error('invalid_der');
  return raw;
}

export async function verifyCallback(url: string, pem: string) {
  const callback = parseCallback(url);
  const keyBytes = decode64(pem.replace(/-----[^-]+-----|\s/g, ''));
  const key = await crypto.subtle.importKey('spki', keyBytes,
    { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
  const valid = await crypto.subtle.verify({name: 'ECDSA', hash: 'SHA-256'}, key,
    derToRaw(decode64(callback.params.get('signature')!)), callback.signed);
  if (!valid) throw new Error('invalid_signature');
  return callback.params;
}
