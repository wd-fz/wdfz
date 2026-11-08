() => {
  running=false;
  Object.assign(S,{screen:'play',dead:false,mode:'in',room:'teach1',day:2,tsec:620,floorY:0});
  RT.atmos={stares:{},shift:{},shiftPose:{},seats:{},said:{}};
  Atmos.A.window=null;Atmos.A.stare=null;
  const frame=()=>GameModules.emit('frame',0),floors=[],windows=[];
  const snap=o=>{
    const s={p:o.position.toArray(),q:o.quaternion.toArray(),s:o.scale.toArray(),children:o.children.map(snap)};
    if(o.geometry){
      const m=o.material,p=o.geometry.parameters;
      s.material={color:m.color.getHexString(),alpha:m.opacity,unlit:!!m.isMeshBasicMaterial,fog:m.fog,depthWrite:m.depthWrite,texture:!!m.map,add:m.blending===THREE.AdditiveBlending};
      s.geometry=o.geometry.type==='CylinderGeometry'?{cylinder:[p.radiusTop,p.radiusBottom,p.height,p.radialSegments]}:{plane:[p.width,p.height]};
    }
    return s;
  };
  let texture=null;
  for(const host of ['teach','lab','admin'])for(let floor=1;floor<=5;floor++){
    S.room=host+floor;AtmosFx.clear();frame();
    const f=AtmosFx.F;
    const sample={room:S.room,props:f.grp?f.grp.children.map(snap):[],shifts:[]};
    if(f.signs.length)texture=f.signs[0].material.map.image.toDataURL('image/png');
    if(f.props)for(const [kind,pose] of [['push',{dx:-.6,dy:.8,angle:-.6435}],['face',{dx:1,dy:0,angle:1.2}],['face',null]]){
      RT.atmos.shift[S.day+':'+S.room]=null;frame();
      RT.atmos.shift[S.day+':'+S.room]=kind;
      RT.atmos.shiftPose[S.day+':'+S.room]=pose;
      GLR.cam.position.set(3,1.65,5);frame();
      sample.shifts.push({kind,pose,camera:GLR.cam.position.toArray(),props:snap(f.props)});
    }
    floors.push(sample);
  }
  const lab=objWorld(objById('lab')),anchor={x:lab.x+lab.w*.5,y:lab.y+lab.h*.5,height:16.2};
  for(const floor of [1,3,5])for(const cls of [0,2])for(const seed of [.1,.9])for(const anchored of [false,true]){
    S.room='teach'+floor;const R=INTERIORS[S.room];
    const record={room:S.room,cls:S.room+':'+cls,seed,seen:0,gone:false};
    if(anchored)record.anchor=anchor;
    const camera=[(cls===0?-25:5)+(seed-.5)*4,1.65,0],yaw=seed<.5?0:Math.PI;
    GLR.cam.position.fromArray(camera);GLR.cam.rotation.set(0,yaw,0);GLR.cam.updateMatrixWorld(true);
    Atmos.A.window=record;frame();
    const f=AtmosFx.F.fig;
    const box=new THREE.Box3().setFromObject(f);
    windows.push({record:JSON.parse(JSON.stringify(record)),camera,yaw,position:f.position.toArray(),scale:f.scale.toArray(),bounds:[box.min.toArray(),box.max.toArray()],looking:Atmos.A.windowLook});
  }
  const before=AtmosFx.F.fig.position.toArray();
  GLR.cam.position.x+=3;Atmos.A.window.seen=.5;frame();
  const stable=AtmosFx.F.fig.position.toArray();
  S.dead=true;frame();const cleared=AtmosFx.F.grp===null&&AtmosFx.F.fig===null;
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',floors,windows,anchor,before,stable,cleared,textures:{'exit-sign':texture}};
}
