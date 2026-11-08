() => {
  running=false;QUALITY=2;
  Object.assign(S,{mode:'in',room:'teach2',x:1000,y:400,ang:0,pitch:0,eyeLift:0,floorY:0,dead:false});
  const keys={trash:['hinge','lamp','slit'],liftdoor:['lamp','leafL','leafR','out','it','fingers'],grip:['stain','hands'],neck:['head','segs'],shadow:['sh'],twin:['tw'],shatter:['bells','shardIM'],drown:['water','rainIM','bubIM'],water:['stain','drips','bulge'],freeze:['frost','spikeIM','puffs','panes'],stare:['heads'],voice:['spk','rings'],bell:['bell','spot'],follow:['ppl'],deep:['table','dishes','pit','shaft','mouth'],ring:['flames','stones','robes'],loop:['walls','frames','man'],lamps:['lamps','pale'],laugh:['faces','big']};
  const snap=o=>{
    if(Array.isArray(o))return o.map(snap);
    const result={p:o.position.toArray(),q:o.quaternion.toArray(),s:o.scale.toArray(),visible:o.visible};
    result.figureColors=[];o.traverse(n=>{if(n.geometry?.userData.figKind)result.figureColors.push(n.material.vertexColors);});
    if(o.material){result.alpha=o.material.opacity;result.fog=o.material.fog;result.depthTest=o.material.depthTest;result.color=o.material.color?.toArray();}
    if(o.isInstancedMesh)result.instances=Array.from({length:o.count},(_,i)=>{const m=new THREE.Matrix4();o.getMatrixAt(i,m);return m.toArray();});
    if(o.userData.lamp)result.lamp=snap(o.userData.lamp);
    return result;
  };
  const geometry={},geometryChecks={},cases=[],times=[0,.2,.6,1,1.2,1.45,1.7,1.95,2.2,2.4,2.63,2.9,3.06,3.3,3.65,4.2];
  for(const [kind,names] of Object.entries(keys))for(const shake of [1,0]){
    deathFX(kind,{preview:true});const c=ANFX.cg,frames=[];c.shk=shake;
    if(shake===1){
      const selected=kind==='shatter'?{'bell-dome':c.bells[0].geometry,'bell-shard':c.shardIM.geometry}:
        kind==='water'?{'ceiling-bulge':c.bulge.geometry}:kind==='deep'?{'feast-food':c.dishes[0].children[1].geometry}:{};
      for(const [name,g] of Object.entries(selected)){
        g.computeBoundingBox();geometry[name]={vertices:Array.from(g.attributes.position.array),normals:Array.from(g.attributes.normal.array),indices:g.index?Array.from(g.index.array):null};
        geometryChecks[name]={bounds:[g.boundingBox.min.toArray(),g.boundingBox.max.toArray()],vertices:g.attributes.position.count,triangles:(g.index?g.index.count:g.attributes.position.count)/3};
      }
    }
    for(const t of times){
      const view={ang:0,pitch:0,eyeLift:0};DeathCG.update(c,t,view);
      frames.push({t,view,shade:c.veilMesh.material.opacity,props:Object.fromEntries(names.map(name=>[name,snap(c[name])])),cues:Object.keys(c.cued)});
    }
    cases.push({kind,shake,frames});anfxClear();
  }
  const floors=[];
  for(const floor of [1,2,3,4,5]){
    S.room='teach'+floor;deathFX('liftdoor',{preview:true});const c=ANFX.cg;
    floors.push({floor,segments:c.F.children.filter(o=>o.material?.color?.getHexString()==='ffb257').map(snap)});anfxClear();
  }
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',eye:EYE,cases,floors,geometry,geometryChecks};
}
