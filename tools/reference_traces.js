// Keep the original trace list/indexing and original hash2 Number/bitwise behaviour.
() => {
  running=false;QUALITY=2;
  const clone=x=>JSON.parse(JSON.stringify(x)),cases=[],hashes=[];
  const surface=new THREE.Mesh(new THREE.PlaneGeometry(1000,1000),new THREE.MeshBasicMaterial());
  surface.rotation.x=-Math.PI/2;surface.position.y=.12;surface.updateMatrixWorld(true);GLR.outMesh=surface;
  function capture(scene,dynamic){
    S.mode=scene==='out'?'out':'in';S.room=scene==='out'?null:scene;
    RT.traces=clone(dynamic);tracesBuild(true);
    cases.push({scene,dynamic:clone(dynamic),gy:.12,children:TR.g.children.map(n=>({p:n.position.toArray(),q:n.quaternion.toArray(),s:n.scale.toArray(),
      alpha:n.material?.opacity,color:n.material?.color?.getHexString(),triangles:n.geometry?(n.geometry.index?.count||n.geometry.attributes.position.count)/3:null}))});
  }
  for(const scene of ['teach1','garage1','dorm1','teach6','out','lab1','teach2'])capture(scene,[]);
  for(const k of ['puddle','stain','chalkring','moths','rows','feet','paper','handprint','fence','cup','bowl','dust']){
    capture('out',[{k,room:null,x:1200,y:400,a:.7,pts:[{x:1200,y:400},{x:1216,y:410}]}]);
  }
  capture('out',[{k:'dust',room:'teach1',x:1200,y:400},{k:'cup',room:null,x:1200,y:400},
    {k:'puddle',room:null,x:1210,y:410},{k:'handprint',room:'teach2',x:1210,y:410},{k:'cup',room:null,x:1220,y:400}]);
  for(let a=0;a<40;a++)for(let b=0;b<19;b++)hashes.push([a,b,hash2(a,b)]);
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',cases,hashes};
}
