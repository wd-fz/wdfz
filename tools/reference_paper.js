() => {
  running=false;S.screen='play';S.dead=false;S.floorY=0;S.mode='in';S.room='admin1';
  GLR.roomMesh=GLR.roomMesh||new THREE.Group();
  const R=INTERIORS.admin1,w=WindowGaze.windows(R)[0],frames=[];
  S.x=w.x;S.y=w.y+36;S.ang=-Math.PI/2;S.pitch=0;
  const base={kind:'danger',room:R.id,c:w.c,r:w.r,phase:'fly',t:0,lx:w.x,ly:w.y+24,text:'reference',id:'reference'};
  const snap=()=>{
    const group=GLR.scene.getObjectByName('paper-plane'),p=group.children[0],h=group.children[1];
    return {plane:{p:p.position.toArray(),rotation:p.rotation.toArray(),visible:p.visible,color:'#'+p.material.color.getHexString(),emission:'#'+p.material.emissive.getHexString()},
      hand:{p:h.position.toArray(),visible:h.visible},camera:{p:GLR.cam.position.toArray(),direction:GLR.cam.getWorldDirection(new THREE.Vector3()).toArray()}};
  };
  for(const phase of ['fly','ground','wait','read','aim','flight'])for(const t of phase==='fly'?[0,.6,1.2,1.8,2.4]:[0]){
    const e=Object.assign({},base,{phase,t,f:{x:w.x,y:w.y+24,h:1.6,yaw:-1.3,pitch:.2,clean:1}});
    RT.paper={ev:e};GameModules.emit('frame',0);frames.push({e,snapshot:snap()});
  }
  const group=GLR.scene.getObjectByName('paper-plane'),p=group.children[0];
  const geometry={points:Array.from(p.geometry.attributes.position.array),normals:Array.from(p.geometry.attributes.normal.array),
    hand:group.children[1].children.map(h=>({p:h.position.toArray(),size:[h.geometry.parameters.width,h.geometry.parameters.height,h.geometry.parameters.depth],color:'#'+h.material.color.getHexString(),emission:'#'+h.material.emissive.getHexString()}))};
  // Exercise the original private solid()/flyStep() through tick, one synthetic tile at a time.
  const solid=[],originalRows=R.grid;
  try{
    const chars=[...new Set(originalRows.flatMap(row=>Array.from(row)))];
    for(const ch of chars)for(const height of [.5,.85,1.5]){
      const c=3,r=3,rows=originalRows.map(row=>Array.from(row));
      rows[r][c]=ch;R.grid=rows;
      const e=Object.assign({},base,{phase:'flight',limit:10,t:0,f:{x:R.ox+(c+.5)*R.tw,y:R.oy+(r+.5)*R.th,h:height,yaw:0,pitch:0,clean:1}});
      RT.paper={ev:e};PaperPlane.keys.l=PaperPlane.keys.r=PaperPlane.keys.u=PaperPlane.keys.d=0;
      S.dead=false;S.screen='play';GameModules.emit('tick',.000001);
      const errors=GameModules.errors().filter(x=>x.who==='paper-plane');if(errors.length)throw Error(JSON.stringify(errors));
      if(e.t===0&&e.phase==='flight')throw Error('original paper tick did not advance: '+JSON.stringify({dead:S.dead,screen:S.screen,state:RT.paper}));
      solid.push({ch,height,blocked:e.phase==='hunt',why:e.why||null});
    }
  }finally{R.grid=originalRows;}
  RT.paper=null;GameModules.emit('frame',0);
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',room:R.id,window:w,frames,geometry,solid};
}
