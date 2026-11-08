() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x)),C=CampusRules,H=window.__rulesHooks,store=window.__rulesStore;
  const content={rules:C.RULES,evidence:C.EVID,bundles:C.BUNDLES,refutations:C.REFUTE,achievements:C.ACH};
  const bundles=Object.entries(C.BUNDLES).map(([id,ids])=>({id,valid:C.validBundle(ids)}));
  const seeds=Array.from({length:256},(_,i)=>['seed-'+i,C.pickBundle('seed-'+i)]);
  for(const s of ['','0','test','武大附中','🎓'])seeds.push([s,C.pickBundle(s)]);
  const spots=[];
  for(const bundle of Object.keys(C.BUNDLES)){store.reset();Object.assign(C.state(),{on:1,bundle});spots.push({bundle,spots:clone(C.spots())});}
  let events=[],choices=[],timers=[];
  const oldChoice=UI.choice,oldClose=UI.closeChoice,oldKill=kill,oldFact=gameFact,oldOS=os,oldScope=Lifecycle.scope,oldStats=PlayerStats.changeSan;
  UI.choice=(text,options)=>{choices.push(options);events.push({kind:'choice',text,labels:options.map(o=>o.label)});};UI.closeChoice=()=>{};
  kill=(msg,fx,source)=>events.push({kind:'kill',msg,fx,source});gameFact=(kind,data)=>events.push(Object.assign({kind:'fact',fact:kind},data));
  os=text=>events.push({kind:'notice',text});PlayerStats.changeSan=(amount)=>{S.san=Math.max(0,S.san+amount);events.push({kind:'san',amount});};
  Lifecycle.scope=()=>({timeout:(fn,ms)=>timers.push({fn,ms})});
  const cases=[];
  for(const type of ['knock','ticket','borrowed'])for(const selection of [0,1]){
    store.reset();Object.assign(C.state(),{on:1,bundle:'A'});S.san=60;S.day=1;S.room='dorm1';S.screen='play';S.dead=false;DEV.on=false;
    localStorage.removeItem('wdfz3d_rules_records_v1');events=[];choices=[];timers=[];
    C[type]();const waits=timers.map(t=>t.ms);timers.forEach(t=>t.fn());choices[0][selection].fn();
    cases.push({type,selection,waits,events:clone(events),san:S.san,granted:Object.keys(C.records())});
  }
  const ticks=[];
  for(const bundle of Object.keys(C.BUNDLES))for(const room of ['dorm1','teach1','canteen1','admin1'])for(const time of [690,720,1060,1339.9,1340])for(const dt of [7.99,8,25]) {
    freshState('hard');store.reset();Object.assign(C.state(),{on:1,bundle});Object.assign(S,{screen:'play',mode:'in',room,tsec:time,day:1,dead:false});UI.chooseOpen=false;
    events=[];choices=[];timers=[];H.tick(dt);
    ticks.push({bundle,room,time,dt,state:clone(C.state()),events:clone(events),waits:timers.map(t=>t.ms)});
  }
  const saves=[];
  for(const bundle of Object.keys(C.BUNDLES)) {
    freshState('hard');store.reset();Object.assign(C.state(),{on:1,bundle,read:{R02:1,R03:1,E03:1},marks:{R03:'存疑'},knock:{0:1},ticket:{1:1},name:{1:1},nameT:14,run:{gaze:1}});
    Object.assign(S,{screen:'play',mode:'in',room:'teach1',tsec:690,day:1,dead:false});RT.rulesMode={v:1,ver:'1.1.0',bundle};
    const save={v:1,clockVersion:2};SAVE_SCHEMA.forEach(f=>f.save(save));save.mods['mod:campus-rules']=clone(store.save());
    saves.push({bundle,save});
  }
  freshState('hard');Object.assign(S,{screen:'play',mode:'in',room:'dorm1',ang:0,pitch:0,eyeLift:0,seated:false});
  SHAKE_ON=false;const group=new THREE.Group();GLR.scene.add(group);const stage=DeathCG.build('rules_knock',group,false),frames=[];
  for(let i=0;i<=140;i++){const t=i*.05,view={};DeathCG.update(stage,t,view);frames.push({t,pitch:view.pitch,lift:view.eyeLift,shade:stage.veilMesh.material.opacity,feet:stage.feet.map(f=>f.visible),ink:{x:stage.ink.position.x,scale:stage.ink.scale.x}});}
  group.removeFromParent();ThreeBackend.disposeGroup(group);
  UI.choice=oldChoice;UI.closeChoice=oldClose;kill=oldKill;gameFact=oldFact;os=oldOS;Lifecycle.scope=oldScope;PlayerStats.changeSan=oldStats;
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',content,bundles,seeds,spots,cases,ticks,saves,frames};
}
