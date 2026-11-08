// Independent observations of the original navigation / persistent patroller.
() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x)),point=(x,z,h=0)=>{const p=VoidMaze.toWorld(x,z);return PatrolNav.point('lift_dream',p.x,p.y,h);};
  const start=point(0,0),exits=MAZE_CFG.exits.map(e=>point(e.x,e.z,e.h));
  const paths=[],sight=[],saves=[],flows=[];
  for(const [id,a,b] of [['south',start,exits[0]],['north',start,exits[1]],['south-return',exits[0],start],['north-return',exits[1],start],['between-exits',exits[0],exits[1]],['pit',start,point(0,-32,4)]]){
    const path=PatrolNav.path(a,b);paths.push({id,a,b,path,length:path?PatrolNav.length(path):null});
  }
  const points=[start,...exits,...paths.slice(0,2).flatMap(p=>p.path.filter((_,i)=>i%9===0)),point(0,-32,4),point(0,0,10)];
  for(const a of points)for(const b of points) sight.push({a,b,seen:PatrolNav.los(a,b)});
  for(const [id,p] of [['spawn',start],['ramp',paths[0].path.find(p=>p.fy<-.5&&p.fy>-6)],['exit',exits[1]],['unsupported',point(0,0,10)]]){
    freshState('hard');Object.assign(S,{mode:'in',room:'lift_dream',x:start.x,y:start.y,floorY:0,tsec:700,screen:'play',san:90});
    RT.elevatorRide={host:'lab',origin:4,target:4,phase:'dream',rare:true,remaining:0,pending:null};
    Object.assign(PAT,{room:p.scene,x:p.x,y:p.y,fy:p.fy,mazeGateway:{host:'lab',origin:4},permanent:true,locked:true,safety:0});
    const save={v:1,clockVersion:2};SAVE_SCHEMA.forEach(f=>f.save(save));
    freshState('hard');applySave(clone(save));saves.push({id,save:clone(save),expected:clone(PAT)});
  }
  for(const [id,host,origin,leaving] of [['teach-entry','teach',1,false],['lab-entry','lab',4,false],['lab-return','lab',4,true]]){
    freshState('hard');const floor=host+origin,l=Elevator.landing(host,origin),landing=PatrolNav.point(floor,l.x,l.y);
    const player=leaving?PatrolNav.tilePoint(floor,30,18):paths[0].path[Math.min(50,paths[0].path.length-1)];
    const a=leaving?paths[0].path.at(-1):landing;
    Object.assign(S,{mode:'in',room:player.scene,x:player.x,y:player.y,floorY:player.fy||0,tsec:700,screen:'play',san:90,seated:false});
    RT.elevatorRide={host,origin,target:origin,phase:'dream',rare:true,remaining:0,pending:null};
    // The real scene-boundary hook records the elevator used to enter the maze.
    GameModules.emit('leaveRoom',floor,'lift_dream');
    Object.assign(PAT,{room:a.scene,x:a.x,y:a.y,fy:a.fy,permanent:true,locked:false,safety:0,afterBlink:0});
    const before=clone(PAT),steps=[];
    for(let i=0;i<21;i++){PatrolWorld.tick(.1);steps.push(clone(PAT));}
    flows.push({id,host,origin,leaving,player,before,steps});
  }
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',paths,sight,saves,flows};
}
