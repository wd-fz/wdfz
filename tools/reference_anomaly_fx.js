// Samples the actual original models and frame updates, not a second implementation.
() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x)), scenarios=[];
  const kinds=['exercise','hand','leak','rite','feast','lamps','chalk','roster','broad','repeat','shifting','cold','raindots','stare','necker','shadow','twin'];
  function sample(){
    return {p:ANFX.grp.position.toArray(),children:ANFX.grp.children.map(o=>({type:o.type,p:o.position.toArray(),r:[o.rotation.x,o.rotation.y,o.rotation.z],q:o.quaternion.toArray(),s:o.scale.toArray(),v:o.visible,
      geo:o.geometry?.parameters||null,color:o.material?.color?.getHexString(),alpha:o.material?.opacity,depthWrite:o.material?.depthWrite,items:ANFX.items.indexOf(o),data:clone(o.userData)}))};
  }
  for(const kind of kinds) for(const tier of (kind==='stare'?[0,1,2,3,4]:[2])){
    const room=['exercise','necker','shadow','raindots'].includes(kind)?null:INTERIORS[kind==='feast'?'canteen1':'teach1'];
    const scene=room?room.id:'out',me=room?{x:room.ox+30.5*room.tw,y:room.oy+17.5*room.th}:{x:1200,y:400};
    Object.assign(S,{mode:room?'in':'out',room:room?.id||null,x:me.x,y:me.y,ang:.7,floorY:0,dead:false});QUALITY=tier;
    const data={pts:Array.from({length:5},(_,i)=>({x:me.x+8+i*6,y:me.y-4+i*5})),c:{x:me.x+36,y:me.y},x:me.x+27,y:me.y+18};
    Object.assign(AN,{id:kind,active:true,t:0,acc:0,data});
    PresentationRandom.seed(42);SKIP.tex={};
    const source=kind==='rite'?data.c:kind==='twin'?{x:data.x,y:data.y}:kind==='necker'?{x:BOUND.x1*SC+16,y:me.y}:kind==='hand'?aheadPoint(8):me;
    anfxSpawn(kind,source.x,source.y);
    const before=sample(),frames=[];
    for(const dt of [0,.016,.17,.43,1,3,.016]){
      S.x+=dt*9;S.y+=dt*4;AN.acc+=dt*.3;AN.data.hit=AN.acc>1;
      const p=worldToScene(S.x,S.y,room);GLR.cam.position.set(p.x,1.65,p.z);
      anfxUpdate(dt);frames.push({dt,feet:[p.x,0,p.z],acc:AN.acc,hit:AN.data.hit,state:sample()});
    }
    scenarios.push({kind,tier,scene,me,ang:.7,source,data:clone(data),before,frames});anfxClear();
  }
  PresentationRandom.seed(42);SKIP.tex={};
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',scenarios,
    textures:{'eye-red':gazeEyeTex('red').image.toDataURL(),'eye-gold':gazeEyeTex('gold').image.toDataURL(),'rain-words':handTex('明天的天气：阴').image.toDataURL()}};
}
