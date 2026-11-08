// Run against the original Web modules. The port never generates its own expectations.
() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x));
  const saved={os,gameFact,doEnterRoom,fadeTo,autoSave,syncCamera,triggerEnding,cutLook,cutFade};
  const rests=[],paths=[],ordinary=[],frames=[],saves=[];
  let facts=[],ends=[];
  function reset(day,tsec,hasTop=true){
    freshState('hard');AN.active=false;patReset();RT.inspection=null;
    Object.assign(S,{screen:'play',mode:'in',room:'dorm2',day,tsec,san:30,viol:20,stam:30,seated:false,ang:0,pitch:0,eyeLift:0,floorY:0,bag:hasTop?['top']:[]});
    const r=INTERIORS.dorm2;S.x=r.ox+5.5*r.tw;S.y=r.oy+3.5*r.th;
    facts=[];ends=[];
  }
  try {
    os=()=>{};gameFact=(kind,data)=>facts.push({kind,...clone(data)});autoSave=()=>{};syncCamera=()=>{};fadeTo=fn=>fn();
    doEnterRoom=id=>{S.mode='in';S.room=id;};triggerEnding=id=>{ends.push(id);S.screen='end';};
    for(const tsec of [700,755,900,1080,1380])for(const hasTop of [false,true])for(const rolls of [[0,0],[.19999,.09999],[.2,0],[.5,0],[0,.1],[.1,.05],[.1,.04999]]){
      reset(1,tsec,hasTop);let at=0;GameRandom.bind(()=>rolls[at++ % rolls.length]);
      const inClass=Inception.classNow(),steps=[];
      for(let i=0;i<2;i++){
        // A second rest attempt remains in the same bedroom/day even after a successful entry.
        const r=INTERIORS.dorm2;Object.assign(S,{room:'dorm2',x:r.ox+5.5*r.tw,y:r.oy+3.5*r.th});
        const intercepted=GameModules.first('restAct','sleep')===true;
        steps.push({intercepted,draws:at,state:clone(Inception.state()),room:S.room});
      }
      rests.push({tsec,hasTop,rolls,inClass,steps});
    }
    const specs=[{id:'unconfirmed-pit',spin:null,exit:false,day:1,tsec:755},{id:'stand-pit',spin:.1,exit:false,day:1,tsec:900},
      {id:'fall-pit-midnight',spin:.9,exit:false,day:1,tsec:1490},{id:'fall-pit-evening',spin:.9,exit:false,day:2,tsec:1060},
      {id:'stand-exit',spin:.1,exit:true,day:2,tsec:800},{id:'fall-exit',spin:.9,exit:true,day:1,tsec:800},
      {id:'unconfirmed-exit',spin:null,exit:true,day:1,tsec:755}];
    for(const spec of specs){
      reset(spec.day,spec.tsec);Inception.enter();
      if(spec.spin!==null){GameRandom.bind(()=>spec.spin);Inception.spin();GameRandom.bind(()=>1-spec.spin);Inception.spin();}
      const before=clone(Inception.state()),start={san:S.san,viol:S.viol,stam:S.stam,day:S.day,tsec:S.tsec};
      if(spec.id==='fall-pit-midnight'){const d={v:1,clockVersion:2};SAVE_SCHEMA.forEach(f=>f.save(d));saves.push(clone(d));}
      const at=Inception.at(spec.exit?Inception.EXIT:{c:9,r:3});S.x=at.x;S.y=at.y;
      const steps=[];
      for(let i=0;i<9;i++){
        GameModules.emit('tick',.2);
        steps.push({state:clone(Inception.state()),room:S.room,eye:S.eyeLift,day:S.day,tsec:S.tsec,san:S.san,viol:S.viol,stam:S.stam,cool:clone(S.actCool||{}),ends:ends.slice()});
      }
      paths.push({...spec,before,start,steps,facts:clone(facts)});
    }
    for(const day of [1,2,4])for(const tsec of [700,1030,1340,1490])for(const key of ['wash','sleep','eat']){
      reset(day,tsec,false);GameRandom.bind(()=>0);const before={day,tsec,san:S.san,viol:S.viol,stam:S.stam};
      doSanAct(key);
      ordinary.push({key,before,after:{day:S.day,tsec:S.tsec,san:S.san,viol:S.viol,stam:S.stam,cool:clone(S.actCool||{})}});
    }
    let view=[],fade=0;cutLook=(...args)=>view=args;cutFade=k=>fade=k;
    const d={st:Array.from({length:4},()=>new THREE.Object3D()),said:{},topB:new THREE.Object3D(),topD:new THREE.Object3D(),finger:new THREE.Object3D(),winB:{material:{color:new THREE.Color()}},sun:{material:{color:new THREE.Color()}}};
    CUT.dt=.05;
    for(let i=0;i<=400;i++){
      const k=i/400;CUT_DEF.inception.frame(k,d);
      frames.push({k,view,fade,stage:d.st.findIndex(s=>s.visible),topB:d.topB.rotation.toArray().slice(0,3),topD:d.topD.rotation.toArray().slice(0,3),finger:d.finger.position.toArray(),window:d.winB.material.color.getHex()});
    }
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',grid:INCEPTION_MAZE,rests,paths,ordinary,frames,saves};
  }finally{Object.assign(window,saved);GameRandom.bind(RandomRules.create(1).next);}
}
