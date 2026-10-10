const fs=require('fs');
function load(p){ let t=fs.readFileSync(p,'utf8'); if(t.charCodeAt(0)===0xFEFF) t=t.slice(1); const j=JSON.parse(t); let it=j.customMessage.items; if(typeof it==='string') it=JSON.parse(it); return it; }
const a=load('cache/et_before.json'), b=load('cache/et_after.json');
console.log('before='+a.length+' after='+b.length);
const A=new Map(a.map(o=>[o.guid,o]));
const moved=[], added=[];
for(const o of b){
  const p=A.get(o.guid);
  if(!p){ added.push(o); continue; }
  const d=Math.hypot((o.x-p.x)||0,(o.z-p.z)||0);
  if(d>0.05) moved.push({guid:o.guid,name:o.name,x0:p.x,z0:p.z,x1:o.x,z1:o.z,d:d.toFixed(2)});
}
console.log('--- ????? ---');
for(const m of moved) console.log('  guid='+m.guid+' name="'+m.name+'" ('+m.x0+','+m.z0+') -> ('+m.x1+','+m.z1+')  ?? '+m.d);
console.log('--- ????? ---');
for(const o of added) console.log('  guid='+o.guid+' name="'+o.name+'" ('+o.x+','+o.z+')');
if(!moved.length && !added.length) console.log('  (???????????)');
