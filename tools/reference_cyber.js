() => {
  running=false;
  const proto=CanvasRenderingContext2D.prototype,fill=proto.fillText,stroke=proto.strokeRect;
  const look=cutLook, samples=[];let canvas=null,ops=[],view=[];
  proto.fillText=function(text,x,y){if(this.canvas===canvas)ops.push({kind:'text',text,x,y,font:this.font,color:this.fillStyle,width:this.measureText(text).width});return fill.apply(this,arguments);};
  proto.strokeRect=function(x,y,w,h){if(this.canvas===canvas)ops.push({kind:'rect',rect:[x,y,w,h],color:this.strokeStyle,line:this.lineWidth});return stroke.apply(this,arguments);};
  cutLook=(...args)=>{view=args;GLR.cam.position.set(args[0],args[1],args[2]);};
  try {
    for(const [aspect,fov] of [[.5,72],[.79,60],[.8,72],[16/9,72],[16/9,90]]) {
      GLR.cam.aspect=aspect;GLR.cam.fov=fov;GLR.cam.updateProjectionMatrix();
      const d={};CUT_DEF.cyber.setup(d);canvas=d.arch.cv;
      for(const t of [7.2,7.4,7.7,7.95,8.3,8.97,9.7,10.4,10.8]) {
        ops=[];d.arch.key=null;CUT_DEF.cyber.frame(t/16,d);
        samples.push({aspect,fov,t,portrait:d.portrait,size:[canvas.width,canvas.height],screen:d.scr,
          view:[view[0]-d.x,view[1],view[2]-d.z,view[3]-d.x,view[4],view[5]-d.z],ops});
      }
      if(CUT_DEF.cyber.clean)CUT_DEF.cyber.clean(d);
      if(CUT.grp){GLR.scene.remove(CUT.grp);ThreeBackend.disposeGroup(CUT.grp);CUT.grp=null;}
      Engine.endStage();canvas=null;
    }
    return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',samples};
  } finally {proto.fillText=fill;proto.strokeRect=stroke;cutLook=look;}
}
