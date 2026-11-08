// Execute the original modules and hooks, not a second implementation of their rules.
() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x));
  const saved={kill,os,gameFact,triggerEnding,cutLook,cutFade,roll:WudaKid.roll};
  const near=[],knife=[],gifts=[],taps=[],frames=[],saves=[];
  try {
    os=()=>{};gameFact=()=>{};
    for(const scene of ['gear1','teach1'])for(const took of [false,true])for(const offset of [[0,0],[1.49,0],[1.5,0],[0,-1.49],[1,1],[1.1,1.1]]) {
      freshState('hard');const r=INTERIORS[scene];RT.knife={took:took?1:0,held:0,done:0,cap:null};
      Object.assign(S,{mode:'in',room:scene,x:r.ox+(6.5+offset[0])*r.tw,y:r.oy+(1.5+offset[1])*r.th});
      near.push({scene,took,offset,near:Knife.near()});
    }
    const sequences=[
      {id:'bag-success',actions:[['tick',.3],['bag'],['tick',.3],['bag']]},
      {id:'at-deadline',actions:[['bag'],['tick',1],['bag']]},
      {id:'after-deadline',actions:[['bag'],['tick',1.00001],['bag'],['tick',1]]},
      {id:'hot-only',actions:[['hot'],['hot'],['tick',1.1],['tick',1]]},
      {id:'hot-then-bag',actions:[['hot'],['bag'],['tick',1.1]]},
      {id:'bag-hot-bag',actions:[['bag'],['hot'],['bag']]},
      {id:'pre-equipped',held:true,actions:[]},
      {id:'already-done',done:true,actions:[]},
      {id:'missing',missing:true,actions:[]},
      {id:'wait',actions:[['tick',0],['tick',-.2],['tick',.5],['tick',.5],['tick',.00001]]}
    ];
    for(const spec of sequences) {
      freshState('hard');Object.assign(S,{screen:'play',mode:'in',room:'gear1',dead:false,bag:spec.missing?[]:['small_knife'],hot:['small_knife',null],seated:false,tsec:900});
      RT.knife={took:1,held:spec.held?1:0,done:spec.done?1:0,cap:null};
      const deaths=[],ends=[];kill=(text,fx,source)=>{deaths.push({text,fx,source});S.dead=true;};triggerEnding=id=>ends.push(id);
      const caught=GameModules.first('patrolCatch',{msg:'caught'})===true;
      if(!caught)kill('caught','grip','patrol');
      const steps=[];
      const snapshot=action=>steps.push({action,state:clone(Knife.state()),dead:!!S.dead,has:hasItem('small_knife'),deaths:clone(deaths),ends:ends.slice()});
      snapshot(['catch']);
      for(const action of spec.actions) {
        if(action[0]==='tick')GameModules.emit('tick',action[1]);
        else if(!S.dead&&hasItem('small_knife')) {USE_SOURCE=action[0]==='hot'?'hot':null;GameModules.first('itemUse','small_knife');USE_SOURCE=null;}
        snapshot(action);
        if(spec.id==='bag-success'&&action[0]==='bag'&&saves.length===0) {
          const d={v:1,clockVersion:2};SAVE_SCHEMA.forEach(f=>f.save(d));saves.push({kind:'capture',save:clone(d)});
        }
      }
      knife.push({...spec,caught,steps});
    }
    for(const armed of [false,true])for(const speedrun of [false,true])for(const roll of [0,.029999,.03,.99]) {
      freshState('hard');Object.assign(S,{screen:'play',bag:[],hot:[null,null],talent:'night'});
      if(armed)localStorage.setItem('wdfz_wuda','1');else localStorage.removeItem('wdfz_wuda');
      WudaKid.reset();WudaKid.roll=()=>roll;
      const picked=WudaKid.newGame({mode:speedrun?'speedrun':'normal'}),lines=[];
      os=t=>lines.push(t);
      WudaKid.tick(5.9);const before=clone(WudaKid.state);WudaKid.tick(.11);WudaKid.tick(9);
      gifts.push({armed,speedrun,roll,picked,bag:S.bag.slice(),hot:S.hot.slice(),before,after:clone(WudaKid.state),lines});
      if(armed&&!speedrun&&roll===.99){const d={v:1,clockVersion:2};SAVE_SCHEMA.forEach(f=>f.save(d));saves.push({kind:'gift',save:clone(d)});}
    }
    localStorage.removeItem('wdfz_wuda');
    for(const ms of [1000000,1000400,1000800,1001000,1001500,1002000,1005000,1006599,1006600,1006601,1007000])taps.push({ms,result:WudaKid.tap(null,ms),armed:WudaKid.armed()});
    let view=[],fade=0;cutLook=(...args)=>view=args;cutFade=k=>fade=k;os=()=>{};
    const d={st:Array.from({length:4},()=>new THREE.Object3D()),blade:new THREE.Object3D(),handA:new THREE.Object3D(),form:new THREE.Object3D(),stamp:new THREE.Object3D(),lockerDoor:new THREE.Object3D(),said:{}};
    for(let i=0;i<=320;i++){
      const k=i/320;CUT_DEF.knife.frame(k,d);
      frames.push({k,view,fade,stage:d.st.findIndex(s=>s.visible),blade_y:d.blade.position.y,hand_y:d.handA.position.y,form_x:d.form.position.x,stamp_y:d.stamp.position.y});
    }
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',near,knife,gifts,taps,frames,saves};
  } finally {kill=saved.kill;os=saved.os;gameFact=saved.gameFact;triggerEnding=saved.triggerEnding;cutLook=saved.cutLook;cutFade=saved.cutFade;WudaKid.roll=saved.roll;USE_SOURCE=null;}
}
