() => {
  running=false;
  const samples=[],original=SoundPlayer.play;
  try{
    for(const day of [1,2,3,7])for(const time of [700,1330])for(const kind of ['start','end']){
      S.day=day;S.tsec=time;
      const tune=Atmos.bellTune(kind)||{};
      let played=null;
      SoundPlayer.play=(id,opts)=>{played={id,opts};return true;};
      SFX.schoolBell(.45,kind);
      const recipe=SOUND_BANK['event.bellEnd'].layers[0];
      let at=0;const notes=[];
      for(let i=0;i<recipe.n;i++){
        notes.push({at,frequency:recipe.f(tune,i),duration:recipe.dur(tune,i)});
        at+=recipe.every(tune,i);
      }
      samples.push({day,time,kind,tune,played,notes});
    }
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',samples};
  }finally{SoundPlayer.play=original;}
}
