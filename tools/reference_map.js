() => {
  running=false; S.screen='play';S.mode='out';S.room=null;S.x=1020;S.y=1980;S.ang=.6;
  ExplorationMap.selected='campus';
  const samples=[],proto=CanvasRenderingContext2D.prototype,draw=proto.fillText,rect=proto.fillRect,stroke=proto.strokeRect;
  let record;
  proto.fillText=function(t,x,y){if(this.canvas.id==='mapcv')record.labels.push({text:t,x,y,width:this.measureText(t).width,font:this.font,color:this.fillStyle});return draw.apply(this,arguments);};
  proto.fillRect=function(x,y,w,h){if(this.canvas.id==='mapcv')record.rects.push({rect:[x,y,w,h],color:this.fillStyle});return rect.apply(this,arguments);};
  proto.strokeRect=function(x,y,w,h){if(this.canvas.id==='mapcv'&&!record.extent)record.extent=[w,h];return stroke.apply(this,arguments);};
  try {
    document.getElementById('mapv').style.display='flex';
    const body=document.getElementById('mapc').parentElement.parentElement;
    for(const size of [[620,650],[340,720],[900,420]]) {
      Object.defineProperty(body,'clientWidth',{configurable:true,value:size[0]});
      Object.defineProperty(body,'clientHeight',{configurable:true,value:size[1]});
      record={labels:[],rects:[]}; UI.renderMap();
      const canvas=document.getElementById('mapcv'); record.size=[canvas.width,canvas.height];record.available=[Math.min(size[0]-24,900),size[1]-48];
      samples.push(record);
    }
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',content:{roads:ROADS,bound:BOUND,objects:OBJ.map(o=>({id:o.id,k:o.k,name:o.n,short:o.s||o.n,x:o.x,y:o.y,w:o.w,h:o.h})),gates:[['北门',GATE_N.x,GATE_N.y],['西小门',GATE_W.x,GATE_W.y],['南门',GATE_S.x,GATE_S.y]]},samples};
  } finally {proto.fillText=draw;proto.fillRect=rect;proto.strokeRect=stroke;}
}
