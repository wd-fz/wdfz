() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x)), frames=[], crowd=[];
  const R=INTERIORS.teach1;
  S.screen='play'; S.dead=false; S.mode='in'; S.room='teach1'; S.floorY=0;
  S.x=R.ox+48.8*R.tw; S.y=R.oy+11.39*R.th;
  Mechanics.runSeed='classroom-reference'; Classmates.reset();
  const snap=()=>NC.list.map(f=>({p:f.position.toArray(),yaw:f.rotation.y,teacher:!!f.userData.teacher,
    standing:f.userData.standing||0,stood:f.userData.stood||0,visible:f.visible,
    kind:f.userData.teacher?'teacher':f.userData.mesh.geometry===figGeo('sit')?'sit':'person',
    radioIndex:f.userData.radioIndex||0,path:f.userData.radioPath||null}));
  const scenarios=[{viol:0},{viol:35},{viol:70},{viol:92},{viol:0,stare:true},
    {viol:0,stare:true,after:{viol:0,stare:false}},{viol:92,after:{viol:35}},{viol:0,bell:true}];
  for(const c of scenarios){
    Broadcast.state().phase='collect'; S.viol=0; AN.active=false; Classmates.reset(); ncBuild(R);
    const item={context:c,initial:snap(),frames:[]};
    for(let i=0;i<180;i++){
      const ctx=i>=90&&c.after?c.after:c;
      S.viol=ctx.viol; AN.active=!!ctx.stare; AN.id=ctx.stare?'stare':null;
      Broadcast.state().phase=ctx.bell?'bell':'collect'; Classmates.tick(); ncUpdate(1/60);
      if([0,29,59,89,90,119,179].includes(i))item.frames.push({frame:i+1,door:clone(Classmates.state.door),figures:snap()});
    }
    frames.push(item);
  }
  AN.active=false; Broadcast.state().phase='bell'; Broadcast.state().completed=4;
  S.mode='out'; S.room=null; S.viol=0; S.floorY=0;
  for(const left of [60,55,40,20,10,1]){
    Broadcast.state().bell=left;
    BroadcastView.frame(); const p=Broadcast.crowd();
    crowd.push({p:clone(p),figures:BroadcastView.crowd().children.map(f=>({p:f.position.toArray(),yaw:f.rotation.y}))});
  }
  ncClear(); BroadcastView.clear();
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',seed:'classroom-reference',room:'teach1',player:[R.ox+48.8*R.tw,R.oy+11.39*R.th],frames,crowd};
}
