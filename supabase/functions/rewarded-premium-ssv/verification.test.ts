import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseCallback,verifyCallback,derToRaw,rewardIdentity,isConsoleVerification} from './verification.ts';

function rawToDer(raw:Uint8Array) {
  const parts = [raw.slice(0,32),raw.slice(32) ].map(bytes => {
    let start=0; while (start<bytes.length-1 && bytes[start]===0) start++;
    bytes=bytes.slice(start);
    if(bytes[0]&128) bytes=Uint8Array.from([0,...bytes]);
    return [2,bytes.length,...bytes];
  });
  const content=parts.flat();return Uint8Array.from([0x30,content.length,...content]);
}
async function signedUrl(identity = true) {
  const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
  const pem='-----BEGIN PUBLIC KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('spki',pair.publicKey)).toString('base64')+'\n-----END PUBLIC KEY-----';
  const content='ad_unit=123'+(identity ? '&custom_data=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' : '')+'&timestamp='+Date.now()+'&transaction_id=tx1'+(identity ? '&user_id=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' : '');
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

test('signed console callback without optional identity verifies but cannot reward', async () => {
  const {pem, url} = await signedUrl(false);
  const params = await verifyCallback(url, pem);
  assert.equal(rewardIdentity(params), null);
  await assert.rejects(verifyCallback(url.replace('ad_unit=123', 'ad_unit=456'), pem), /invalid_signature/);
});
test('only complete app UUID identity is eligible for database verification', async () => {
  const {pem, url} = await signedUrl();
  const params = await verifyCallback(url, pem);
  assert.deepEqual(rewardIdentity(params), {
    attempt: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', user: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  });
  params.set('custom_data', 'SAMPLE_CUSTOM_DATA_STRING');
  assert.equal(rewardIdentity(params), null);
  params.delete('custom_data');
  assert.equal(rewardIdentity(params), null);
});

const googleSetupFixture = {"pem":"-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+nzvoGqvDeB9+SzE6igTl7TyK4JB\nbglwir9oTcQta8NuG26ZpZFxt+F2NDk7asTE6/2Yc8i1ATcGIqtuS5hv0Q==\n-----END PUBLIC KEY-----","url":"https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/rewarded-premium-ssv?ad_network=5450213213286189855&ad_unit=1234567890&reward_amount=10&reward_item=Premium+minutes&timestamp=1790870038860&transaction_id=123456789&signature=MEUCIQCNXBYPjfoYmRhoxzYYcZEmNhOwCQzCJoByoVT6TZldQQIgNm9mS7LoeoS3zoezgZ7LVLfqT6VvuJVXATvA_mytu3I&key_id=3335741209"};

test('verifies the actual Google console callback with form-encoded reward name', async () => {
  const params = await verifyCallback(googleSetupFixture.url, googleSetupFixture.pem);
  assert.equal(params.get('reward_item'), 'Premium minutes');
  assert.equal(isConsoleVerification(params), true);
  assert.equal(rewardIdentity(params), null);
  await assert.rejects(verifyCallback(googleSetupFixture.url.replace('reward_amount=10', 'reward_amount=20'), googleSetupFixture.pem), /invalid_signature/);
});
test('console placeholders cannot identify a real reward attempt', () => {
  const params = new URL(googleSetupFixture.url).searchParams;
  params.set('custom_data', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  params.set('user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
  assert.equal(isConsoleVerification(params), false);
  params.delete('custom_data');
  params.set('transaction_id', 'another_transaction');
  assert.equal(isConsoleVerification(params), false);
});
