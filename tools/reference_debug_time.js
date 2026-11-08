// Run the old pure calendar rules directly; never obtain expected values from Godot.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const [root,out]=process.argv.slice(2);
if(!root||!out)throw Error('Usage: node tools/reference_debug_time.js <old-repo> <output.json>');
const file=path.resolve(root,'game3d/js/domain/game-time.js'),rule=require(file);
const lights=Number(fs.readFileSync(path.resolve(root,'game3d/js/core.js'),'utf8').match(/var LIGHTS_OUT=(\d+)/)[1]);
const cases=[];
for(const day of [1,2,4])for(const time of [440,440.1,650,920,1340,1349.9,1350,1440,1499.9])for(const minutes of [0,.001,10,60,300,1060,1500,3180]){
  let t=time,d=day,left=minutes;
  while(left>0){const s=rule.backwardSlice(t,d,left,lights);t=s.to;d=s.day;left=s.remaining;}
  cases.push({day,time,minutes,after:{day:d,time:t}});
}
fs.writeFileSync(out,JSON.stringify({source:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),cases}));
