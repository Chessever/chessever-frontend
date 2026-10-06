/** Drop-in transport handoff for the canonical onesignal-dispatch Edge Function.
 * A stable outbox ID + payload + sorted audience makes producer retries idempotent.
 * Never fall back to OneSignal after a failed handoff: acceptance may be uncertain.
 */
export async function handoffNotification(
  endpoint: string, secret: string, outboxId: string, userIds: string[],
  notification: {title:string;body:string;url:string|null;data:Record<string,unknown>;iosSound?:string;androidSound?:string},
):Promise<void> {
  if (!endpoint.startsWith('https://') || !secret) throw new Error('Notification service is not configured');
  const recipients=[...new Set(userIds)].sort();if(!recipients.length)return;
  const canonical=(value:unknown):string=>{
    if(Array.isArray(value))return `[${value.map(canonical).join(',')}]`;
    if(value!==null && typeof value==='object')return `{${Object.entries(value).sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>`${JSON.stringify(k)}:${canonical(v)}`).join(',')}}`;
    return JSON.stringify(value)??'null';
  };
  const hash=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonical({outboxId,notification,recipients})));
  const eventKey=`${outboxId}:${Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('')}`;
  const res=await fetch(`${endpoint.replace(/\/$/,'')}/internal/notifications`,{method:'POST',headers:{authorization:`Bearer ${secret}`,'content-type':'application/json; charset=utf-8'},
    body:JSON.stringify({eventKey,userIds:recipients,title:notification.title,body:notification.body,data:notification.data,url:notification.url??'',
      ttlSeconds:['game_started','round_started'].includes(String(notification.data.type))?900:86400,
      iosSound:notification.iosSound,androidSound:notification.androidSound}),signal:AbortSignal.timeout(15000)});
  if(!res.ok)throw new Error(`Notification handoff failed: ${res.status}`);
}
