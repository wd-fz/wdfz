// Capture actual meshes and matrices from the pinned Web implementation.
() => {
  running=false;QUALITY=2;
  Object.assign(S,{mode:'in',room:'teach2',x:1000,y:400,ang:0,pitch:0,eyeLift:0,floorY:0,seated:false,dead:false});
  const geometry={},geometryChecks={},cases=[];
  // Kit compresses normals/colors. Read decoded components, not the integer/half-float storage.
  const vectors=a=>Array.from({length:a.count},(_,i)=>[a.getX(i),a.getY(i),a.getZ(i)]).flat();
  const snap=o=>{
    if(Array.isArray(o))return o.map(snap);
    const result={p:o.position.toArray(),q:o.quaternion.toArray(),s:o.scale.toArray(),visible:o.visible};
    result.figureColors=[];o.traverse(n=>{if(n.geometry?.userData.figKind)result.figureColors.push(n.material.vertexColors);});
    if(o.material)Object.assign(result,{color:o.material.color.toArray(),alpha:o.material.opacity,fog:o.material.fog,depthTest:o.material.depthTest,vertexColors:o.material.vertexColors});
    if(o.isInstancedMesh)result.instances=Array.from({length:o.count},(_,i)=>{const m=new THREE.Matrix4();o.getMatrixAt(i,m);return m.toArray();});
    return result;
  };
  const times=[0,.2,.62,.65,.8,.83,.89,.92,1.1,1.25,1.34,1.55,1.76,1.95,2.06,2.2,2.41,2.45,2.7,2.96,2.97,3,3.03,3.12,3.5];
  for(const kind of ['void','abyss'])for(const shake of [1,0]){
    deathFX(kind,{preview:true});const c=ANFX.cg,frames=[];c.shk=shake;
    const props=kind==='void'?{hall:c.hall,doors:c.doors}:{ledge:c.ledge,rubble:c.rub,mark:c.mark,pad:c.pad,man:c.man,beam:c.beam,slab:c.pad.children[0],hatch:c.pad.children[1],cone:c.beam.children[0],lens:c.beam.children[1]};
    if(shake===1){
      for(const name of (kind==='void'?['hall']:['ledge','mark','hatch','cone','lens'])){
        const g=props[name].geometry;g.computeBoundingBox();
        const data={vertices:vectors(g.attributes.position),normals:vectors(g.attributes.normal),indices:g.index?Array.from(g.index.array):null};
        if(g.attributes.color)data.colors=vectors(g.attributes.color);
        geometry[name]=data;
        const samples=Array.from(new Set([0,1,2,Math.floor(g.attributes.position.count/3),Math.floor(g.attributes.position.count/2),g.attributes.position.count-1]));
        geometryChecks[name]={bounds:[g.boundingBox.min.toArray(),g.boundingBox.max.toArray()],vertices:g.attributes.position.count,triangles:(g.index?g.index.count:g.attributes.position.count)/3,samples:samples.map(i=>({i,p:data.vertices.slice(i*3,i*3+3),n:data.normals.slice(i*3,i*3+3),...(data.colors?{c:data.colors.slice(i*3,i*3+3)}:{})}))};
      }
    }
    for(const t of times){
      const view={ang:0,pitch:0,eyeLift:0};DeathCG.update(c,t,view);
      frames.push({t,view,shade:c.veilMesh.material.opacity,props:Object.fromEntries(Object.entries(props).map(([name,o])=>[name,snap(o)]))});
    }
    cases.push({kind,shake,frames});anfxClear();
  }
  const p=anfxW2S(S.x,S.y);
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',eye:EYE,world:[p.x,0,p.z],cases,geometry,geometryChecks};
}
