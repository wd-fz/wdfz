() => {
  running=false;
  Object.assign(S,{screen:'play',dead:false,mode:'in',room:'admin1',day:2,tsec:620});
  GLR.roomMesh=GLR.roomMesh||new THREE.Group();
  const dayIs=DayEvents.is,frames=[],textures={},seen=new Set();
  DayEvents.is=id=>id==='checkup';
  const snap=o=>{
    const a={name:o.name,p:o.position.toArray(),q:o.quaternion.toArray(),s:o.scale.toArray(),children:o.children.map(snap)};
    if(o.geometry){o.geometry.computeBoundingBox();a.bounds=[o.geometry.boundingBox.min.toArray(),o.geometry.boundingBox.max.toArray()];a.color=o.material.color?.getHexString();a.emission=o.material.emissive?.getHexString();a.texture=!!o.material.map;a.emissionMap=!!o.material.emissiveMap;}
    return a;
  };
  try{
    for(let seed=0;seed<100&&seen.size<CheckupDay.LINES.length;seed++){
      RT.runSeed=seed;const line=CheckupDay.line();if(seen.has(line))continue;seen.add(line);
      GameModules.emit('clearWorld');GameModules.emit('frame',0);
      const g=CheckupDay.F.grp;if(!g)throw Error('checkup stage missing');
      frames.push({line,index:CheckupDay.LINES.indexOf(line),props:g.children.slice(0,4).map(snap)});
      textures['checkup-chart-'+CheckupDay.LINES.indexOf(line)]=g.children[2].material.map.image.toDataURL('image/png');
      textures['checkup-sign']=g.children[3].material.map.image.toDataURL('image/png');
    }
    if(seen.size!==5)throw Error('not all chart lines sampled');
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',lines:CheckupDay.LINES,frames,textures};
  }finally{DayEvents.is=dayIs;GameModules.emit('clearWorld');}
}
