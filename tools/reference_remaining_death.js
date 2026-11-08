() => {
  running=false;QUALITY=2;
  const kinds=['vignette','hand','names','chalk','mirror','face','squeeze','slit','wall'],cases=[];
  const capture=()=>{ANFX.grp.updateMatrixWorld(true);return {items:ANFX.items.map(o=>({p:o.position.toArray(),world:o.getWorldPosition(new THREE.Vector3()).toArray(),q:o.quaternion.toArray(),s:o.scale.toArray(),v:o.visible,alpha:o.material?.opacity,color:o.material?.color?.getHexString(),children:o.children.map(c=>({p:c.position.toArray(),q:c.quaternion.toArray(),s:c.scale.toArray(),v:c.visible})),bounds:o.geometry?(o.geometry.computeBoundingBox(),[o.geometry.boundingBox.min.toArray(),o.geometry.boundingBox.max.toArray()]):null})),pitch:ANFX.view.pitch,progress:ANFX.timeline.progress}};
  for(const kind of kinds)for(const ang of [0,.7,-2.3]){
    Object.assign(S,{mode:'out',room:null,x:1200,y:400,ang,pitch:.2,eyeLift:0,floorY:0,dead:false});
    PresentationRandom.seed(42);deathFX(kind,{preview:true});
    const initial=capture(),frames=[];
    for(const dt of [0,.2,.5,.7,.6,.4,.6,.6]){
      S.x+=dt*2;S.y+=dt;S.ang+=dt*.05;
      anfxUpdate(dt);frames.push({dt,feet:[S.x*U2M,0,S.y*U2M],ang:S.ang,state:capture()});
    }
    cases.push({kind,ang,feet:[1200*U2M,0,400*U2M],initial,frames});anfxClear();
  }
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',cases};
}
