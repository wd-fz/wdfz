// The camera-relative stage starts at the origin, facing +z, so source lookAt targets are local.
() => {
  running=false;QUALITY=2;
  Object.assign(S,{mode:'out',room:null,x:0,y:0,ang:Math.PI/2,pitch:0,eyeLift:0,floorY:0,seated:false,dead:false});
  const snap=o=>{
    if(Array.isArray(o))return o.map(snap);
    const result={p:o.position.toArray(),q:o.quaternion.toArray(),s:o.scale.toArray(),visible:o.visible,figureColors:[]};
    if(o.material)Object.assign(result,{color:o.material.color.toArray(),alpha:o.material.opacity,fog:o.material.fog,depthTest:o.material.depthTest,vertexColors:o.material.vertexColors});
    result.meshMaterials=[];o.traverse(n=>{if(n.geometry?.userData.fxKind)result.meshMaterials.push({color:n.material.color.toArray(),vertexColors:n.material.vertexColors,fog:n.material.fog});});
    return result;
  };
  const cases=[],times=[0,.5,.9,.91,1.1,1.11,1.3,1.31,1.5,1.51,1.7,1.71,1.9,1.91,2,2.2,2.44,2.68,2.92,3.1,3.15,3.25,3.5,3.75,4.2];
  for(const size of [[1280,720],[1280,800],[1600,720]])for(const shake of [1,0]){
    GLR.cam.aspect=size[0]/size[1];GLR.cam.updateProjectionMatrix();
    deathFX('crowd',{preview:true});const c=ANFX.cg,frames=[];c.shk=shake;
    const props={floor:c.F.children[0],walls:c.walls,lamp:c.lamp,full:c.full[0],segs:Object.values(c.segs),leaf_l:c.leafL,leaf_r:c.leafR,out:c.out,card:c.card,photo:c.photo,hands:c.hands,edges:c.edges};
    for(const t of times){
      const view={ang:S.ang,pitch:0,eyeLift:0};DeathCG.update(c,t,view);
      frames.push({t,view,fov:GLR.cam.fov,shade:c.veilMesh.material.opacity,props:Object.fromEntries(Object.entries(props).map(([name,o])=>[name,snap(o)]))});
    }
    cases.push({size,shake,frames});anfxClear();
  }
  const cv=LiftCrowdFx.tex().image;
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',eye:EYE,baseAng:S.ang,cases,textureSize:[cv.width,cv.height],textures:{full:cv.toDataURL('image/png')}};
}
