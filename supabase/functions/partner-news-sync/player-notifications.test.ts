import { test } from 'node:test';
import assert from 'node:assert/strict';
import { articleText, extractPlayers, processPlayerNotifications, validateExtraction, type NotificationArticle, ROOKREVIEW_PLAYER_MODEL, verifyPlayerExtraction } from './player-notifications.ts';
const article: NotificationArticle = { article_id: 1, lease: 'lease-1', title: 'Denis Lazavik speaks about chess', summary: 'Denis Lazavik praised local players.', content: 'Denis Lazavik said: “There are many talented players.” Mark Smirnov also participated.' };
const subject = { name: 'Denis Lazavik', mention: 'Denis Lazavik', role: 'quotation', evidence: 'Denis Lazavik said: “There are many talented players.”' };
const config = { accountId: 'a'.repeat(32), apiToken: 'synthetic' };
const answer = (value: unknown, finish_reason = 'stop') => Response.json({ model:ROOKREVIEW_PLAYER_MODEL, choices: [{ finish_reason, message: { role: 'assistant', content: JSON.stringify(value) } }] });
test('only text is supplied: image paths, alt names and URL destinations are excluded', async () => {
 const withImage = { ...article, content: article.content+'\n![Magnus Carlsen](https://cdn.test/Players/Carlsen.jpg)\n[reference](https://ratings.fide.com/profile/123)' };
 let body: any;
 let requestedUrl: unknown;
 await extractPlayers(withImage,config,async (_url, init) => { requestedUrl=_url;body=JSON.parse(String(init?.body));assert.equal(new Headers(init?.headers).get('authorization'),'Bearer synthetic');return answer({players:[subject]}); });
 assert.equal(requestedUrl,`https://api.cloudflare.com/client/v4/accounts/${config.accountId}/ai/v1/chat/completions`);
 assert.equal(body.model,'@cf/zai-org/glm-5.3-flash');assert.equal(body.reasoning_effort,'low');
 assert.equal(body.store,false);assert.equal(body.stream,false);assert.equal(body.response_format.json_schema.strict,true);
 assert.equal(body.options.rejectIfBusy,true);assert.equal(body.max_completion_tokens,4096);
 const allowed=body.response_format.json_schema.schema.properties.players.items.properties.evidence.enum;
 assert.ok(allowed.length>0);assert.ok(allowed.every((text:string)=>[withImage.title,withImage.summary,withImage.content].join('\n').includes(text)));
 assert.ok(allowed.every((text:string)=>!text.includes('Carlsen')&&!text.includes('https:')));
 assert.doesNotMatch(body.messages[1].content,/Carlsen|Players\/|ratings\.fide|https:/);
 assert.match(body.messages[1].content,/Mark Smirnov/);assert.match(body.messages[0].content,/INCLUDING passing mentions/);assert.match(body.messages[0].content,/ONLY in standings tables/);
});
test('grounded roles only; malformed, duplicate and fabricated output is rejected', () => {
 assert.deepEqual(validateExtraction({players:[subject]},articleText(article)),[subject]);
 assert.deepEqual(validateExtraction({players:[]},articleText(article)),[]);
 for(const bad of [{...subject,role:'participant'},{...subject,evidence:'Invented Denis Lazavik quote'},{...subject,mention:'Magnus'},{...subject,name:'Magnus Carlsen'}]){
  assert.throws(()=>validateExtraction({players:[bad]},articleText(article)));
 }
 assert.throws(()=>validateExtraction({players:[subject,subject]},articleText(article)));
});
test('HTTP errors, refusals and incomplete output never become publication decisions', async () => {
 for(const res of [new Response('no',{status:429}),answer({players:[subject]},'length'),Response.json({model:ROOKREVIEW_PLAYER_MODEL,choices:[{finish_reason:'stop',message:{role:'assistant',refusal:'declined',content:null}}]})]){
  await assert.rejects(extractPlayers(article,config,async()=>res));
 }
});
test('verified directory identity is published through the leased DB job, never a push provider', async () => {
 const calls: Array<{name:string,args:Record<string,unknown>}> = [];
 const client={rpc:async(name:string,args:Record<string,unknown>)=>{
  calls.push({name,args});
  return {error:null,data:name==='claim_partner_news_notifications'?[article]:name==='resolve_partner_news_player'?[{fide_id:'123',name:'Lazavik, Denis'}]:true};
 }};
 await processPlayerNotifications(client,config,async()=>answer({players:[subject]}));
 assert.deepEqual(calls.map(c=>c.name),['claim_partner_news_notifications','resolve_partner_news_player','complete_partner_news_notification']);
 assert.deepEqual(calls[2].args.p_subjects,[{...subject,name:'Lazavik, Denis',fide_id:'123'}]);
 assert.equal(calls[2].args.p_lease,'lease-1');assert.equal(calls[2].args.p_model,ROOKREVIEW_PLAYER_MODEL);
});
test('ambiguous and absent identities are omitted; an empty job does not call AI', async () => {
 for(const candidates of [[],[{fide_id:'1',name:'Denis Lazavik'},{fide_id:'2',name:'Denis Lazavik'}]]){
  let completed:unknown;
  await processPlayerNotifications({rpc:async(name,args)=>({error:null,data:name==='claim_partner_news_notifications'?[article]:name==='resolve_partner_news_player'?candidates:(completed=args.p_subjects)})},config,async()=>answer({players:[subject]}));
  assert.deepEqual(completed,[]);
 }
 await processPlayerNotifications({rpc:async()=>({error:null,data:[]})},config,async()=>{throw Error('must not call AI');});
});
test('transient failure records a bounded diagnostic against the same lease', async () => {
 let completion:any;
 await processPlayerNotifications({rpc:async(name,args)=>({error:null,data:name==='claim_partner_news_notifications'?[article]:(completion=args)})},config,async()=>new Response('',{status:503}));
 assert.equal(completion.p_error,'ai_http_503');assert.equal(completion.p_article_id,1);assert.equal(completion.p_lease,'lease-1');
});

test('invalid Cloudflare account configuration fails before claiming work or sending credentials', async () => {
 for (const accountId of ['', 'another/account', 'a'.repeat(32)+'/evil', 'not-an-account']) {
  const invalid={...config,accountId};
  await assert.rejects(extractPlayers(article,invalid,async()=>{throw Error('must_not_fetch');}),/invalid_ai_config/);
  await assert.rejects(processPlayerNotifications({rpc:async()=>{throw Error('must_not_claim');}},invalid),/invalid_ai_config/);
 }
});
test('truncated, malformed, tool, reasoning-only and provider-error responses cannot publish', async () => {
 const responses=[
  {success:false,errors:[{message:'synthetic'}]},
  {choices:[]},
  {model:'another-model',choices:[{finish_reason:'stop',message:{role:'assistant',content:JSON.stringify({players:[subject]})}}]},
  {choices:[{finish_reason:'stop',message:{role:'assistant',reasoning_content:JSON.stringify({players:[subject]}),content:''}}]},
  {choices:[{finish_reason:'stop',message:{role:'assistant',content:JSON.stringify({players:[subject]}),tool_calls:[{}]}}]},
  {choices:[{finish_reason:'stop',message:{role:'assistant',content:'not JSON'}}]},
 ];
 for (const response of responses) await assert.rejects(extractPlayers(article,config,async()=>Response.json({model:ROOKREVIEW_PLAYER_MODEL,...response})));
});

test('captured GLM answer remains valid exact evidence without requiring incidental extraction', async () => {
 const title='"There are many promising and talented players in Kazakhstan!" — Denis Lazavik';
 const source={...article,title,summary:'Denis Lazavik shared his opinion. Mark Smirnov achieved a norm.',content:'Denis Lazavik won the tournament. Daniil Dubov was runner-up.'};
 // Sanitized answer captured from the connected Cloudflare account on 2026-11-03.
 const player={name:'Denis Lazavik',mention:'Denis Lazavik',role:'subject' as const,evidence:title};
 assert.deepEqual(await extractPlayers(source,config,async()=>answer({players:[player]})),[player]);
});
test('no usable text excerpts means no model request', async () => {
 assert.deepEqual(await extractPlayers({...article,title:'',summary:'',content:''},config,async()=>{throw Error('must_not_fetch');}),[]);
});

test('readiness check uses only fixed synthetic text and cannot claim or publish jobs', async () => {
 let requests=0;
 const checked=await verifyPlayerExtraction(config,async(_url,init)=>{
  requests++;const body=JSON.parse(String(init?.body));
  assert.match(body.messages[1].content,/Magnus Carlsen discusses chess/);
  assert.doesNotMatch(body.messages[1].content,/Denis|lease|article_id/);
  return answer({players:[{name:'Magnus Carlsen',mention:'Magnus Carlsen',role:'subject',evidence:'Magnus Carlsen discusses chess'},{name:'Hikaru Nakamura',mention:'Hikaru Nakamura',role:'subject',evidence:'Magnus Carlsen said that he enjoys playing chess. Hikaru Nakamura was also briefly mentioned in the discussion.'}]});
 });
 assert.deepEqual(checked,{ok:true,model:ROOKREVIEW_PLAYER_MODEL});assert.equal(requests,1);
});
test('readiness does not accept an empty extraction or failed provider', async()=>{
 await assert.rejects(verifyPlayerExtraction(config,async()=>answer({players:[]})),/ai_check_failed/);
 await assert.rejects(verifyPlayerExtraction(config,async()=>new Response('',{status:403})),/ai_http_403/);
});

test('passing prose mentions resolve through the same directory and leased publication path',async()=>{
 const passing={name:'Mark Smirnov',mention:'Mark Smirnov',role:'subject',evidence:article.content};
 let published:any;
 await processPlayerNotifications({rpc:async(name,args)=>({error:null,data:name==='claim_partner_news_notifications'?[article]:name==='resolve_partner_news_player'?[args.p_name==='Mark Smirnov'?{fide_id:'999',name:'Mark Smirnov'}:{fide_id:'123',name:'Denis Lazavik'}]:(published=args.p_subjects)})},config,async(_url,init)=>{
  const body=JSON.parse(String(init?.body));
  assert.match(body.messages[0].content,/central or sustained focus is NOT required/);
  assert.match(body.messages[0].content,/briefly named opponents/);
  assert.match(body.messages[0].content,/score\/result lists, pairing lists/);
  return answer({players:[subject,passing]});
 });
 assert.deepEqual(published.map((p:any)=>p.fide_id),['123','999']);
 assert.equal(published[1].evidence,article.content);
});
test('passing mentions still require exact evidence and an unambiguous directory identity',async()=>{
 const passing={name:'Mark Smirnov',mention:'Mark Smirnov',role:'subject',evidence:article.content};
 assert.throws(()=>validateExtraction({players:[{...passing,evidence:'Mark Smirnov was invented.'}]},articleText(article)));
 let published:any;
 await processPlayerNotifications({rpc:async(name,args)=>({error:null,data:name==='claim_partner_news_notifications'?[article]:name==='resolve_partner_news_player'?[{fide_id:'1',name:'Mark Smirnov'},{fide_id:'2',name:'Mark Smirnov'}]:(published=args.p_subjects)})},config,async()=>answer({players:[passing]}));
 assert.deepEqual(published,[]);
});
