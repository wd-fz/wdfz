// Evaluated inside the original game's browser. Expected data comes from its actual
// applySave / SAVE_SCHEMA, not from the Godot converter.
() => {
  const clone = x => JSON.parse(JSON.stringify(x));
  const capture = () => { const d={v:1,clockVersion:2}; SAVE_SCHEMA.forEach(f=>f.save(d)); return clone(d); };
  freshState('hard');
  GameModules.emit('newGame',{diff:'hard',mode:'normal'});
  const room=INTERIORS.teach1, own=ClassroomLayout.ownSeat, seat=ClassroomLayout.anchor(room,own);
  Object.assign(S,{mode:'in',room:'teach1',x:seat.x,y:seat.y,seated:true,seat:ClassroomLayout.seat('teach1',own.col,own.row),talent:'immune'});
  Mechanics.runSeed='migration-fixture';
  DayEvents.seed();
  const base=capture(), cases=[];
  const add=(id,edit) => {
    const input=clone(base); edit(input);
    freshState(input.diff); const prepared=applySave(input);
    // The real continuation also restores scene-owned height before collision.
    if(S.mode==='in') {
      const R=INTERIORS[S.room];
      if(R.spiral) spiralRestore(prepared.spiral);
      if(R.onEnter) R.onEnter({stairHeight:S.floorY,restoreVisit:true});
    }
    // Just like the actual restore path, decode older per-cell exploration maps before capture.
    for(const room of Object.keys(RT.exploration||{})) ExplorationMap.seen(room);
    cases.push({id,save:input,expected:capture(),floorY:S.floorY||0});
  };
  add('seated',()=>{});
  add('old-classroom',d=>{
    d.layoutVersion=3;d.seat={room:'teach1',col:48,row:6,seatId:'teach1:48:6',facing:-Math.PI/2};
    d.x=room.ox+48.5*room.tw;d.y=room.oy+6.5*room.th;
    d.openDoors={'teach1:48:15':1};
  });
  add('inspection',d=>{
    d.tsec=770;
    d.rt.inspection={seen:{'1:0':true},warned:{'1:0':true},queue:[],settled:{},calm:0,calmRoom:'teach1',
      current:{day:1,slot:0,t:2.4,look:.3,move:.2,result:'present',excused:false,compliant:true,room:'teach1',
        points:[{x:seat.x+30,y:seat.y},{x:seat.x,y:seat.y+40}]}};
    const cv=document.createElement('canvas');cv.width=64;cv.height=36;
    const cx=cv.getContext('2d');cx.fillStyle='#376057';cx.fillRect(0,0,64,36);cx.fillStyle='#ffffff';cx.fillText('SAVE',8,24);
    d.rt.photos=[{an:'',cap:'原版相机',img:cv.toDataURL('image/jpeg',.6),day:1,t:770,place:'教室',flash:0}];
  });
  add('routes', d=>{
    d.day=2;d.tsec=925;d.san=57;d.viol=23;d.stam=34;d.tt=17;
    d.bag=['torch','brolly','key','coil','phone','chalk','pill'];d.hot=['torch','pill'];
    d.use={torch:true,phone:false,brollyShield:true};d.pillT=7.2;d.snackT=4.1;
    d.talentState.consumed={fatalProtection:true,faceRemedy:false};
    const door=[]; for(let r=0;r<room.rows;r++) for(let c=0;c<room.cols;c++) if(room.grid[r][c]==='=') door.push('teach1:'+c+':'+r);
    d.openDoors={[door[0]]:1,[door[1]]:1};
    d.actCool={eat:SchoolClockFixture(d.day,d.tsec)+12};
    Object.assign(d.rt,{wakes:1,hacked:true,data:true,dataSource:'terminal',faceQuiz:{order:[0,1,2],done:2,used:[0,1,2]},
      pressureClock:SchoolClockFixture(2,930),pressureSeen:1,coilTaken:1,lensTaken:1,geoMaps:2,
      portalDiary:true,portalBlueprints:{2:true,4:true},portalWork:{5:1},portalSketch:false,
      deskUsed:{'teach1:48:11':true},pendingLoot:{'teach1:49:11':'snack'},hwTaken:true,keyMiss:3,
      body:{injury:36,restT:9,medDay:{1:true}},midnightMeal:{night:1,until:1880,n:1},
      patrolNotes:{note1:1},exploration:{teach1:{'2:3':1,'3:3':1}},
      investigation:{entries:{portalDiary:{text:'原存档日记',kind:'事实',source:'隧道',day:2}},recent:['portalDiary'],focus:'portal'},
      dayEvents:{1:'none',2:'celebration'},daySaid:{'2:celebration':1},lessons:{'2:9':{done:true}},
      atmos:{stares:{'2:teach1:0':1},shift:{},shiftPose:{},seats:{},said:{},left:{}},visits:{'2:teach1':2}});
    d.clues={portalDiary:true,'investigation:portalDiary':true};
    d.fn={v:15,on:true,note:true,n:1,next:24,shown:true,used:{},left:3,done:false};
    d.mods.mechanics.activePlaySeconds=123.5;
    d.mods.phoneDevice.initialized=true;d.mods.phoneDevice.battery=63;d.mods.phoneDevice.network=true;
    d.mods.phoneDevice.wireless={status:'complete',elapsed:180,target:180};
    d.mods.phoneDevice.download={status:'running',elapsed:21,target:60};
    d.mods.broadcast.book=true;d.mods.broadcast.fuse=true;d.mods.broadcast.completed=1;
    d.mods.broadcast.clock=52;d.mods.broadcast.nextCall=128;
    d.mods.runScore.ledger=[{cat:'clue',text:'找到日记',pts:15,clock:1900}];d.mods.runScore.minSan=42;
    d.mods['chalk-marks']={v:1,serial:1,marks:[{n:1,s:'x',room:'teach1',face:'floor',x:seat.x,y:seat.y,h:0,a:0}]};
  });
  add('old-clock', d=>{d.clockVersion=1;d.day=3;d.tsec=30;d.actCool={eat:3*1440+50};d.anCool={rain:1420};});
  add('anomaly', d=>{
    d.seated=false;d.anId='hand';d.anT=3.2;d.anAcc=.4;d.anNext=48;d.anPre='rain';d.anPreNext=72;
    d.anData={asked:true,chosen:null};d.anChoiceMs=1800;
    d.rt.anHist=['rain','hand'];d.rt.anSeen={rain:1,hand:1};d.rt.preTold=1;
    d.mods.patrolWorld.locked=true;d.mods.patrolWorld.lock=2.3;d.mods.patrolWorld.lastSeen={scene:'teach1',x:seat.x,y:seat.y,fy:0};
  });
  add('garage',d=>{
    const r=INTERIORS.garage1; d.seated=false;d.room='garage1';d.x=r.ox+55.5*r.tw;d.y=r.oy+13.5*r.th;
    d.roam={on:true,x:d.x-80,y:d.y,cd:.72,seen:true,litAcc:.8,stage:'approach',waitT:0,lureTold:true,toldSpot:true,goneTold:false,backTold:false};
    d.rt.lure={x:d.x-54,y:d.y,t:4.3};d.rt.carRight='12:4';d.rt.carTried={'12:8':1};
  });
  add('stair',d=>{
    const id=Object.keys(INTERIORS).find(k=>INTERIORS[k].stairwell),r=INTERIORS[id];
    d.seated=false;d.room=id;d.x=r.cx;d.y=r.cy;d.stairwell={id,height:4.2};
  });
  add('stair-platform',d=>{
    const s=STAIR_LAYOUT[0],r=INTERIORS[s.id];
    d.seated=false;d.room=s.id;d.x=r.cx;d.y=r.cy-1.8/U2M;d.stairwell={id:s.id,height:s.rise*2};
  });
  add('spiral',d=>{const r=INTERIORS.bell1;d.seated=false;d.room='bell1';d.x=r.cx;d.y=r.cy;d.spiral={state:'top',a:SPIRAL.amax,th:SPIRAL.th0};});
  add('maze',d=>{
    const r=INTERIORS.lift_dream;d.seated=false;d.room='lift_dream';d.x=r.cx-7/U2M;d.y=r.cy-36.8/U2M;
    d.mods['void-maze']={t:321.5,falls:2,fy:4,told:{long:1}};
    d.rt.elevatorRide={host:'lab',origin:3,target:3,phase:'dream',rare:true,remaining:0,pending:null};
  });
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',cases};
  function SchoolClockFixture(day,t){return (day-1-(t>=LIGHTS_OUT+10&&day>1?1:0))*1440+t;}
}
