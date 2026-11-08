() => {
  running=false;
  const old={dread:SFX.dread,fade:SoundPlayer.fade,busy:dreadBusy,age:gameAge,allow:Dread.allow,note:Dread.note,policy:GamePolicy.simulationAllowed};
  const cases=[];let busy=false,allowed=true,plays=[],fades=[];
  try{
    Object.assign(S,{screen:'play',mode:'in',room:'teach1',day:1,dead:false,tsec:700});
    GLR.roomLights=[new THREE.Object3D()];GLR.roomLights[0].position.set(0,2.7,7);
    dreadBusy=()=>busy;gameAge=()=>100;Dread.allow=()=>true;Dread.note=()=>{};
    GamePolicy.simulationAllowed=()=>allowed;
    SFX.dread=(cue,place)=>{const h={cue,end:999,gain:{context:{currentTime:0}}};plays.push(cue);return h;};
    SoundPlayer.fade=h=>{fades.push(h.cue);return true;};
    const snapshot=()=>({event:SensoryScenes.state()?.kind||'',plays:plays.slice(),fades:fades.slice(),lamp:SensoryScenes.lampMul(0)});
    for(const action of ['complete','busy','leave','pause','door_answer','door_reopen']){
      SensoryScenes.cancel();plays=[];fades=[];busy=false;allowed=true;S.room='teach1';PresentationRandom.seed(1);
      const frames=[];
      if(action.startsWith('door_'))SensoryScenes.door({room:'teach1',c:10+(action==='door_reopen'?1:0),r:15,x:300,y:300,open:false});
      else if(!SensoryScenes.lamp())throw Error('lamp did not start');
      frames.push(snapshot());
      if(action==='complete'){
        for(let i=0;i<12;i++)SensoryScenes.frame(.25);frames.push(snapshot());
        for(let i=0;i<16;i++)SensoryScenes.frame(.25);frames.push(snapshot());
      }else if(action==='door_answer'){
        for(let i=0;i<6;i++)SensoryScenes.frame(.25);frames.push(snapshot());
        busy=true;SensoryScenes.frame(.1);frames.push(snapshot());
      }else if(action==='door_reopen'){
        SensoryScenes.door({room:'teach1',c:11,r:15,x:300,y:300,open:true});frames.push(snapshot());
      }else{
        if(action==='busy')busy=true;
        if(action==='leave')S.room='lab1';
        if(action==='pause')allowed=false;
        SensoryScenes.frame(.1);frames.push(snapshot());
      }
      cases.push({action,frames});
    }
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',cases,fadeTimeConstant:.04};
  }finally{
    SensoryScenes.cancel();SFX.dread=old.dread;SoundPlayer.fade=old.fade;dreadBusy=old.busy;gameAge=old.age;Dread.allow=old.allow;Dread.note=old.note;GamePolicy.simulationAllowed=old.policy;
  }
}
