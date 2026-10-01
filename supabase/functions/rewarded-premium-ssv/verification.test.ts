import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseCallback,verifyCallback,derToRaw} from './verification.ts';

function rawToDer(raw:Uint8Array) {
  const parts = [raw.slice(0,32),raw.slice(32) ].map(bytes => {
    let start=0; while (start<bytes.length-1 && bytes[start]===0) start++;
    bytes=bytes.slice(start);
    if(bytes[0]&128) bytes=Uint8Array.from([0,...bytes]);
    return [2,bytes.length,...bytes];
  });
  const content=parts.flat();return Uint8Array.from([0x30,content.length,...content]);
}
async function signedUrl() {
  const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
  const pem='-----BEGIN PUBLIC KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('spki',pair.publicKey)).toString('base64')+'\n-----END PUBLIC KEY-----';
  const content='ad_unit=123&custom_data=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa&timestamp='+Date.now()+'&transaction_id=tx1&user_id=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  const raw=new Uint8Array(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},pair.privateKey,new TextEncoder().encode(content)));
  const signature=Buffer.from(rawToDer(raw)).toString('base64url');
  return {pem,url:'https://example.invalid/?'+content+'&signature='+signature+'&key_id=1'};
}
test('accepts an authentic signature and rejects payload tampering',async()=>{
  const {pem,url}=await signedUrl();
  assert.equal((await verifyCallback(url,pem)).get('transaction_id'),'tx1');
  await assert.rejects(verifyCallback(url.replace('ad_unit=123','ad_unit=456'),pem),/invalid_signature/);
});
test('rejects wrong signing key',async()=>{
  const a=await signedUrl();const b=await signedUrl();
  await assert.rejects(verifyCallback(a.url,b.pem),/invalid_signature/);
});
test('rejects duplicate parameters and missing signed content',async()=>{
  const {url}=await signedUrl();
  assert.throws(()=>parseCallback(url.replace('ad_unit=123','ad_unit=123&ad_unit=456')),/duplicate_parameter/);
  assert.throws(()=>parseCallback('https://example.invalid/?signature=abc&key_id=1'),/invalid_signature_layout/);
});
test('rejects malformed DER rather than accepting a partial signature',()=>{
  assert.throws(()=>derToRaw(new Uint8Array([0x30,2,2,0])),/invalid_der/);
});
