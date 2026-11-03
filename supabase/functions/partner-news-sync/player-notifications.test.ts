import { test } from 'node:test';
import assert from 'node:assert/strict';
import { articleText, extractPlayers, processPlayerNotifications, validateExtraction, type NotificationArticle } from './player-notifications.ts';
const article: NotificationArticle = { article_id: 1, lease: 'lease-1', title: 'Denis Lazavik speaks about chess', summary: 'Denis Lazavik praised local players.', content: 'Denis Lazavik said: “There are many talented players.” Mark Smirnov also participated.' };
const subject = { name: 'Denis Lazavik', mention: 'Denis Lazavik', role: 'quotation', evidence: 'Denis Lazavik said: “There are many talented players.”' };
const answer = (value: unknown, status = 'completed') => Response.json({status, output:[{type:'message',content:[{type:'output_text',text:JSON.stringify(value)}]}]});
test('only text is supplied: image paths, alt names and URL destinations are excluded', async () => {
 const withImage = { ...article, content: article.content+'\n![Magnus Carlsen](https://cdn.test/Players/Carlsen.jpg)\n[reference](https://ratings.fide.com/profile/123)' };
 let body: any;
 await extractPlayers(withImage,{apiKey:'synthetic',model:'configured-model'},async (_url, init) => { body=JSON.parse(String(init?.body));return answer({players:[subject]}); });
 assert.equal(body.store,false);assert.equal(body.text.format.strict,true);
 assert.doesNotMatch(body.input,/Carlsen|Players\/|ratings\.fide|https:/);
 assert.match(body.input,/Mark Smirnov/);assert.match(body.instructions,/incidental mentions/);
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
 for(const res of [new Response('no',{status:429}),answer({players:[subject]},'incomplete'),Response.json({status:'completed',output:[{type:'message',content:[{type:'refusal'}]}]})]){
  await assert.rejects(extractPlayers(article,{apiKey:'synthetic',model:'configured-model'},async()=>res));
 }
});
test('verified directory identity is published through the leased DB job, never a push provider', async () => {
 const calls: Array<{name:string,args:Record<string,unknown>}> = [];
 const client={rpc:async(name:string,args:Record<string,unknown>)=>{
  calls.push({name,args});
  return {error:null,data:name==='claim_partner_news_notifications'?[article]:name==='resolve_partner_news_player'?[{fide_id:'123',name:'Lazavik, Denis'}]:true};
 }};
 await processPlayerNotifications(client,{apiKey:'synthetic',model:'configured-model'},async()=>answer({players:[subject]}));
 assert.deepEqual(calls.map(c=>c.name),['claim_partner_news_notifications','resolve_partner_news_player','complete_partner_news_notification']);
 assert.deepEqual(calls[2].args.p_subjects,[{...subject,name:'Lazavik, Denis',fide_id:'123'}]);
 assert.equal(calls[2].args.p_lease,'lease-1');
});
test('ambiguous and absent identities are omitted; an empty job does not call AI', async () => {
 for(const candidates of [[],[{fide_id:'1',name:'Denis Lazavik'},{fide_id:'2',name:'Denis Lazavik'}]]){
  let completed:unknown;
  await processPlayerNotifications({rpc:async(name,args)=>({error:null,data:name==='claim_partner_news_notifications'?[article]:name==='resolve_partner_news_player'?candidates:(completed=args.p_subjects)})},{apiKey:'synthetic',model:'fixture'},async()=>answer({players:[subject]}));
  assert.deepEqual(completed,[]);
 }
 await processPlayerNotifications({rpc:async()=>({error:null,data:[]})},{apiKey:'synthetic',model:'fixture'},async()=>{throw Error('must not call AI');});
});
test('transient failure records a bounded diagnostic against the same lease', async () => {
 let completion:any;
 await processPlayerNotifications({rpc:async(name,args)=>({error:null,data:name==='claim_partner_news_notifications'?[article]:(completion=args)})},{apiKey:'synthetic',model:'fixture'},async()=>new Response('',{status:503}));
 assert.equal(completion.p_error,'ai_http_503');assert.equal(completion.p_article_id,1);assert.equal(completion.p_lease,'lease-1');
});
