() => {
  running=false;
  const original=figMesh, dayIs=DayEvents.is;
  const result={reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',exchange:[],gaze:[]};
  figMesh=(kind,mat,scale)=>{const mesh=original(kind,mat,scale);mesh.userData.referenceKind=kind;return mesh;};
  const snap=f=>({kind:f.userData.referenceKind,p:f.position.toArray(),yaw:f.rotation.y,scale:f.scale.toArray(),
    color:'#'+f.material.color.getHexString(),emission:f.material.emissive?'#'+f.material.emissive.getHexString():null,
    unlit:f.material.isMeshBasicMaterial||false,fog:f.material.fog,vertexColors:f.material.vertexColors,visible:f.visible});
  const frame=()=>GameModules.emit('frame',0);
  try{
    S.screen='play';S.dead=false;S.floorY=0;S.mode='out';S.room=null;
    S.x=1080;S.y=900;GLR.outMesh=GLR.outMesh||new THREE.Group();
    RT.exchange={phase:'waiting',search:[],prog:0};
    for(const phase of ['waiting','qualified','escort'])for(const progress of phase==='escort'?[0,200,500,900]:[0]){
      RT.exchange.phase=phase;RT.exchange.prog=progress;
      RT.exchange.search=phase==='escort'?[{x:1000,y:800},{x:1040,y:700},{x:900,y:500}]:[];
      frame();const group=GLR.scene.getObjectByName('exchange');
      if(!group)throw Error('exchange group missing');
      if(!result.sign){
        const panel=group.children[7],post=group.children[8],canvas=panel.material.map.image;
        result.sign={panel:{p:panel.position.toArray(),size:[panel.geometry.parameters.width,panel.geometry.parameters.height],color:'#'+panel.material.color.getHexString(),emission:'#'+panel.material.emissive.getHexString(),fog:panel.material.fog,side:panel.material.side,emissionMap:panel.material.emissiveMap===panel.material.map},post:{p:post.position.toArray(),size:[post.geometry.parameters.width,post.geometry.parameters.height,post.geometry.parameters.depth],color:'#'+post.material.color.getHexString()},textureSize:[canvas.width,canvas.height]};
        result.textures={'exchange-sign':canvas.toDataURL('image/png')};
      }
      result.exchange.push({phase,progress,player:[S.x,S.y],path:JSON.parse(JSON.stringify(Exchange.route())),members:Exchange.members(),figures:group.children.slice(0,7).map(snap)});
    }
    RT.exchange.phase='over';frame();
    S.mode='in';S.room='admin1';GLR.roomMesh=GLR.roomMesh||new THREE.Group();
    const R=INTERIORS.admin1,ws=WindowGaze.windows(R);
    for(const nz of [1,-1]){
      const w=ws.find(v=>v.nz===nz);if(!w)throw Error('gaze window missing');
      RT.windowGaze={ev:{room:R.id,c:w.c,r:w.r,id:'reference-'+nz}};
      for(const dx of [-2,0,2]){
        S.x=w.x+dx/U2M;S.y=w.y+nz*4/U2M;frame();
        const group=GLR.scene.getObjectByName('window-gaze');group.updateMatrixWorld(true);
        const eyes=group.children[1],direction=new THREE.Vector3();eyes.getWorldDirection(direction);
        result.gaze.push({room:R.id,window:w,player:[S.x,S.y],body:snap(group.children[0]),
          eyes:{p:eyes.position.toArray(),direction:direction.toArray(),size:eyes.children[0].geometry.parameters.radius,scale:eyes.children[0].scale.toArray(),color:'#'+eyes.children[0].material.color.getHexString()}});
      }
    }
    RT.windowGaze.ev=null;frame();
    const player=worldToScene(S.x,S.y,R);
    const points=[{x:S.x+30,y:S.y+20},{x:S.x-40,y:S.y+12}];
    InspectionView.buildFx({room:R.id,points});
    result.inspection={room:R.id,player:[S.x,S.y],points,figures:INSPECT_FX.group.children.map(f=>({p:f.position.toArray(),body:snap(f.children[0]),direction:[f.userData.scatterX,f.userData.scatterZ]})),frames:[]};
    S.x+=500;S.y-=200;
    for(let t=.2;t<=.8;t+=.2){InspectionView.scatterTick(.2,{t,duration:.8});result.inspection.frames.push({t,figures:INSPECT_FX.group?INSPECT_FX.group.children.map(f=>({p:f.position.toArray(),alpha:f.children[0].material.opacity})):[]});}
    DayEvents.is=id=>id==='checkup';S.tsec=620;frame();
    const check=GLR.scene.getObjectByName('checkup-day');if(!check)throw Error('checkup group missing');
    result.checkup=check.children[check.children.length-1].children.map(snap);
    S.room='teach1';const T=INTERIORS.teach1;S.x=T.ox+48.8*T.tw;S.y=T.oy+11.39*T.th;
    PresentationRandom.seed(1);
    fnPeopleBuild();result.fake={room:S.room,player:[S.x,S.y],figures:FN_P.grp.children.map(f=>({p:f.position.toArray(),yaw:f.rotation.y,body:snap(f.children[0])}))};
    fnPeopleClear();
    const errors=GameModules.errors().filter(e=>['exchange','window-gaze','checkup'].includes(e.who));
    if(errors.length)throw Error(JSON.stringify(errors));
    return result;
  }finally{figMesh=original;DayEvents.is=dayIs;InspectionView.clearFx();}
}
