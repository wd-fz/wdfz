// Executes the original presentation code with its own geometry and random source.
() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x)),scenarios=[],models=[],ground=[],walls=[];
  const savedWorld=GLR.outMesh;
  function node(n){
    const d={p:n.position.toArray(),r:[n.rotation.x,n.rotation.y,n.rotation.z],q:n.quaternion.toArray(),s:n.scale.toArray(),v:n.visible};
    if(n.material){d.color=n.material.color.getHexString();d.alpha=n.material.opacity;}
    if(n.userData.vx!==undefined)d.velocity=clone(n.userData);
    return d;
  }
  function snapshot(kind){
    const st=ANFX[kind],names=kind==='cup'?['cup','ring','core','lidWrap','lid']:['can','ring','core','pool'];
    const result={};for(const name of names)result[name]=node(st[name]);
    result.particles=(st.chips||st.foam).map(node);
    if(kind==='cup')result.attached_lid=st.cup.userData.lid.visible;
    return result;
  }
  // Known flat render surfaces exercise the original cupGroundY ray, not a replacement formula.
  for(const gy of [0,.008,.12])for(const kind of ['cup','cola'])for(const initial of [0,1,2]){
    QUALITY=2;PresentationRandom.seed(42);
    const surface=new THREE.Mesh(new THREE.PlaneGeometry(1000,1000),new THREE.MeshBasicMaterial());
    surface.rotation.x=-Math.PI/2;surface.position.y=gy;surface.updateMatrixWorld(true);GLR.outMesh=surface;
    Object.assign(S,{mode:'out',room:null,x:1200,y:400,ang:.7,floorY:0,dead:false});
    const fall=kind==='cup'?cupFallTime():colaFallTime(),tf=1.25,tl=tf+fall;
    const data={phase:initial,wob:tf,warn:tf,tf,tl,lx:1216,ly:410,wall:{x:1190/SC,y:390/SC,nx:1,ny:0}};
    const start=initial===0?0:initial===1?tf+fall*.45:tl+.3;
    Object.assign(AN,{id:kind,active:true,t:start,acc:0,data});
    anfxSpawn(kind,S.x,S.y);
    const spec={kind,gy,initial,t:start,data:clone(data),me:{x:S.x,y:S.y},before:snapshot(kind),frames:[]};
    function frame(dt,phase,t){
      AN.t=t;AN.data.phase=phase;S.x+=dt*9;S.y+=dt*4;
      anfxUpdate(dt);
      const p=worldToScene(S.x,S.y,null);
      spec.frames.push({dt,t,data:clone(AN.data),feet:[p.x,0,p.z],state:snapshot(kind)});
    }
    if(initial===0){
      let t=0;for(const dt of [0,.016,.2,.6,.4]){t+=dt;frame(dt,0,t);}
      frame(0,1,tf);frame(.016,1,tf+.016);frame(fall*.5-.016,1,tf+fall*.5);frame(fall*.5,1,tl);
      frame(0,2,tl);
    }else frame(0,initial,start);
    let t=initial===0?tl:start;
    const phase=initial===1?1:2;
    for(const dt of [.016,.17,.3,.6,1,2]){t+=dt;frame(dt,phase,t);}
    scenarios.push(spec);anfxClear();surface.geometry.dispose();surface.material.dispose();
  }
  for(let tier=0;tier<5;tier++){
    QUALITY=tier;
    for(const kind of ['cup','lid','cola','foam']){
      const m=kind==='cup'?cupModel(false):kind==='lid'?cupLidMesh():kind==='foam'?new THREE.Mesh(new THREE.SphereGeometry(.05,6,4),colaMats().foam):colaModel();m.scale.setScalar(1);m.updateMatrixWorld(true);
      const box=new THREE.Box3().setFromObject(m),mesh=[];
      m.traverse(o=>{if(o.isMesh)mesh.push({vertices:o.geometry.attributes.position.count,triangles:(o.geometry.index?.count||o.geometry.attributes.position.count)/3,texture:o.material.map?.image?.width||0});});
      models.push({kind,tier,min:box.min.toArray(),max:box.max.toArray(),mesh});
    }
  }
  QUALITY=2;GLR.outMesh=buildOutdoorGeometry();GLR.outMesh.updateMatrixWorld(true);
  for(const id of CUP_BLD){
    const b=objById(id);
    for(const p of [[b.x-2,b.y-2],[b.x+b.w/2,b.y-2],[b.x+b.w+2,b.y+b.h/2],[b.x+b.w/2,b.y+b.h+2]]){
      S.mode='out';S.x=p[0]*SC;S.y=p[1]*SC;walls.push({x:S.x,y:S.y,result:clone(cupWall())});
    }
  }
  for(const origin of [[1200,400],[1390,500],[410,340]])for(let x=-2;x<=2;x++)for(let z=-2;z<=2;z++){
    const p=worldToScene(origin[0]+x*10,origin[1]+z*10,null);
    const y=cupGroundY(p.x,p.z),hit=CUP_RAY.intersectObject(GLR.outMesh,true)[0];
    ground.push({x:p.x,z:p.z,y,hit:hit?{name:hit.object.name,kind:hit.object.geometry.type,data:clone(hit.object.userData),material:hit.object.material.name,instance:hit.instanceId,normal:hit.face.normal.toArray()}:null});
  }
  GLR.outMesh=savedWorld;
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',scenarios,models,ground,walls};
}
