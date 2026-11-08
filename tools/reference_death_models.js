() => {
  running=false;QUALITY=2;
  Object.assign(S,{mode:'out',room:null,x:1000,y:400,ang:0,pitch:0,eyeLift:0,floorY:0,dead:false});
  const pose=o=>({p:o.position.toArray(),q:o.quaternion.toArray(),s:o.scale.toArray(),alpha:o.material?.opacity});
  const instances=o=>Array.from({length:o.count},(_,i)=>{const m=new THREE.Matrix4();o.getMatrixAt(i,m);return m.toArray();});
  const cases=[];
  for(const kind of ['floor','gaze','swarm']){
    deathFX(kind,{preview:true});const c=ANFX.cg,frames=[];
    const geometry=kind==='swarm'?{vertices:Array.from(c.wingIM.geometry.attributes.position.array),indices:Array.from(c.wingIM.geometry.index.array)}:null;
    const initial=kind==='gaze'?c.eyes.map(e=>e.userData.e):kind==='swarm'?c.moths:null;
    for(const t of [0,.2,.7,1.14,1.15,1.7,2.1,2.6,2.9,3.15]){
      const view={ang:0,pitch:0,eyeLift:0};DeathCG.update(c,t,view);
      frames.push({t,view,shade:c.veilMesh.material.opacity,
        props:kind==='floor'?{cup:pose(c.cup),body:pose(c.cup.children[0]),lid:pose(c.lid)}:
          kind==='gaze'?{eyes:c.eyes.map(pose),smile:pose(c.smile)}:
          {wings:instances(c.wingIM),bodies:instances(c.bodyIM),glow:pose(c.glow)}});
    }
    cases.push({kind,geometry,initial,frames});anfxClear();
  }
  // Sample real moth update, including quality counts, random state and per-instance matrices.
  const weather=[];
  for(const quality of [0,2,4]){
    QUALITY=quality;ANFX.grp=new THREE.Group();GLR.scene.add(ANFX.grp);
    PresentationRandom.seed(909);wxMothSpawn(ANFX.grp,1000,400);
    const st=WX.moth,initial=st.ms.map(m=>({p:m.p.toArray(),v:m.v.toArray(),a:m.a,r:m.r,sp:m.sp,ph:m.ph,fl:m.fl,h:m.h})),frames=[];
    Object.assign(AN,{active:true,id:'moth',acc:0});S.diff='hard';
    for(const step of [{dt:.016,acc:0},{dt:.05,acc:2},{dt:.03,acc:4.5},{dt:.1,acc:0}]){
      GLR.cam.position.set(1000*U2M+1,1.65,400*U2M-1);AN.acc=step.acc;wxMothUpdate(step.dt);
      frames.push({...step,distance:st.dist,wings:instances(st.wing),bodies:instances(st.body),dust:Array.from(st.dp),life:Array.from(st.dl)});
    }
    weather.push({quality,count:st.n,dust:st.dl.length,initial,frames});wxClear();anfxClear();
  }
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',eye:EYE,cup:CUP_DIM,cases,weather,textures:{'moth-glow':shadeTex('pool').image.toDataURL('image/png')}};
}
