// Run in the pinned Web runtime. No expectations are computed by the Godot port.
() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x));
  const saved={fact:gameFact,kill,os};
  const eligibility=[],scenarios=[],lights=[],frames=[],saves=[];
  try {
    freshState('hard');S.screen='play';S.mode='in';S.room='teach2';S.seated=false;S.tsec=760;
    AN.active=false;RT.inspection=null;patReset();
    for(const run of [0,59.99,60,120])for(const rare of [false,true])for(const unsafe of [false,true])for(const roll of [0,.00999,.01,.99]) {
      LiftCrowd.CR.run=run;AN.active=unsafe;GameRandom.bind(()=>roll);
      const ride={rare};const allowed=LiftCrowd.eligible(ride);GameModules.emit('liftBoard',ride);
      eligibility.push({run,rare,unsafe,roll,allowed,crowd:ride.crowd});
    }
    for(const spec of [{id:'stay',host:'lab',floor:2},{id:'leave',host:'teach',floor:3,leave:2},
      {id:'late-leave',host:'teach',floor:5,leave:6.2},{id:'reenter',host:'lab',floor:4,leave:2,reenter:2.3},
      {id:'protected',host:'teach',floor:1,protected:true}]) {
      freshState('hard');patReset();AN.active=false;RT.inspection=null;LiftCrowd.CR.run=120;
      const room=INTERIORS[spec.host+spec.floor];const pos=Elevator.world(room,-1.225,0);
      Object.assign(S,{screen:'play',mode:'in',room:room.id,x:pos.x,y:pos.y,ang:0,pitch:0,eyeLift:0,seated:false,tsec:760});
      const lift=Elevator.state(spec.host);Object.assign(lift,{floor:spec.floor,target:spec.floor,door:0,dir:0,hold:0,phase:'idle',remaining:0});
      RT.elevatorRide={host:spec.host,origin:spec.floor,target:spec.floor,phase:'cabin',rare:false,pending:spec.floor===5?1:5,crowd:1,remaining:0};
      const facts=[],deaths=[];gameFact=(kind,f)=>facts.push({kind,...clone(f)});os=()=>{};
      kill=(text,fx,source)=>{deaths.push({text,fx,source});S.dead=!spec.protected;};
      GameRandom.bind(()=>.99);
      Elevator.depart();
      const steps=[];
      for(let i=0;i<=90;i++) {
        const t=Math.round(i*.1*1e8)/1e8;
        if(i>0) {
          const a=spec.leave!==undefined&&t>=spec.leave&&!(spec.reenter!==undefined&&t>=spec.reenter)?1.2:-1.225;
          const p=Elevator.world(room,a,0);S.x=p.x;S.y=p.y;
          Elevator.tick(.1);GameModules.emit('tick',.1);
        }
        steps.push({t,state:clone(LiftCrowd.state()||{}),door:lift.door,dir:lift.dir,hold:lift.hold,
          phase:lift.phase,target:lift.target,remaining:lift.remaining,ride:clone(RT.elevatorRide||{}),dead:!!S.dead});
        if(i===20&&!spec.leave) {
          const d={v:1,clockVersion:2};SAVE_SCHEMA.forEach(f=>f.save(d));saves.push({id:spec.id,save:clone(d)});
        }
        if(deaths.length || (i>35&&!LiftCrowd.state()))break;
      }
      scenarios.push({...spec,steps,facts,deaths});
    }
    freshState('hard');Object.assign(S,{screen:'play',mode:'in',room:'teach2',seated:false,tsec:760,ang:0,pitch:0,eyeLift:0});
    for(const reduced of [false,true])for(let i=0;i<=80;i++) {
      SET.reduceFlash=reduced?1:0;RT.liftCrowd=null;const baseline=lightState().ptK;
      RT.liftCrowd={host:'teach',floor:2,phase:'full',age:i*.05};const st=lightState();
      lights.push({t:i*.05,reduced,mul:st.ptK/baseline,steady:st.steady});
    }
    RT.liftCrowd=null;
    for(const shake of [false,true]) {
      SHAKE_ON=shake;const group=new THREE.Group();GLR.scene.add(group);const c=DeathCG.build('crowd',group,false);
      for(let i=0;i<=168;i++) {
        const t=i*.025,view={};DeathCG.update(c,t,view);
        const segments=Object.keys(c.segs).filter(k=>c.segs[k].visible).sort().join('');
        frames.push({t,shake,yaw:view.ang,pitch:view.pitch,lift:view.eyeLift,shade:c.veilMesh.material.opacity,
          gap:(c.leafL.position.x-.225)*2,lit:(c.walls[0].material.color.r/c.walls[0].userData.c0.r-.25)/.75,
          segments,full:c.full[0].visible,end:c.card.visible,hands:c.hands.map(h=>({pos:h.position.toArray(),on:h.visible}))});
      }
      group.removeFromParent();ThreeBackend.disposeGroup(group);
    }
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',eligibility,scenarios,lights,frames,saves};
  } finally {GameRandom.bind(RandomRules.create(1).next);gameFact=saved.fact;kill=saved.kill;os=saved.os;}
}
