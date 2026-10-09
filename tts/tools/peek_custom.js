const fs=require('fs');
const save=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const st=save.ObjectStates||[];
console.log('top-level objects: '+st.length);
const byName={};
for(const o of st){ byName[o.Name]=(byName[o.Name]||0)+1; }
console.log('names: '+JSON.stringify(byName));
for(const want of ['Custom_Token','Custom_Model','Custom_Assetbundle']){
  const o=st.find(x=>x.Name===want);
  if(!o){ console.log('-- no '+want); continue; }
  console.log('\n===== '+want+' guid='+o.GUID+' fields: '+Object.keys(o).sort().join(','));
  const pick={};
  for(const k of ['Name','Nickname','Transform','CustomImage','CustomToken','CustomMesh','CustomAssetbundle','LuaScript']) if(o[k]!==undefined) pick[k]=o[k];
  console.log(JSON.stringify(pick,null,1).slice(0,1200));
}
