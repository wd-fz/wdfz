() => {
  running=false;
  const clone=x=>JSON.parse(JSON.stringify(x)), now=Date.now;
  const content={deaths:DEATH_ARCHIVE,cuts:ARCHIVE_CUTS,outdoor:DEATH_STAGE_OUT};
  const migrations=[],deaths=[];
  try {
    Date.now=()=>123456;
    for(const log of [{},{counts:{grip:7,rain:2},sources:{patrol:3,garage:2,'an:rain':1,unknown:1}},{counts:{grip:1},sources:{patrol:3,'void_lost':1}}]) {
      localStorage.setItem('wdfz3d_deaths',JSON.stringify(log));const state=DeathArchive.migrate(DeathArchive.blank());
      migrations.push({log,state:clone(state),visible:DeathArchive.visible(state).map(e=>e.id)});
    }
    localStorage.removeItem('wdfz3d_deaths');
    for(const source of ['patrol','san','void_lost','rules_knock','',null])for(const debug of [false,true])for(const replay of [false,true])for(const ctx of [null,'debug']) {
      const blank=DeathArchive.blank();blank.migrated=1;DeathArchive.write(blank);
      DEV.on=debug;ArchiveReplay.on=replay;KILL_CTX=ctx;
      const first=DeathArchive.record(source,'laugh'),second=DeathArchive.record(source,'laugh');
      deaths.push({source,fx:'laugh',debug,replay,ctx,first:first?first.id:null,second:second?second.id:null,state:clone(DeathArchive.read())});
    }
    DEV.on=false;ArchiveReplay.on=false;KILL_CTX=null;
    const blank=DeathArchive.blank();blank.migrated=1;DeathArchive.write(blank);
    const before={deaths:DeathArchive.visible(blank).map(e=>e.id),cuts:DeathArchive.visibleCuts(blank).map(e=>e.id)};
    DeathArchive.markSeen('cut:void_in');const seen=clone(DeathArchive.read());
    const locked=DeathArchive.locked(seen).filter(e=>!e.id.startsWith('x.')).map(e=>e.id);
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',content,migrations,deaths,before,seen,locked,opening:proSeen(),ends:endsSeen()};
  } finally {Date.now=now;DEV.on=false;ArchiveReplay.on=false;KILL_CTX=null;}
}
