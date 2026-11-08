// Run the original fragment shader on a known SDR image. Expected pixels come
// from WebGL, not a second implementation of the curve in the Godot tests.
() => {
  const n=64,source=[],linear=new Float32Array(n*n*4);
  const decode=x=>x<=.04045?x/12.92:Math.pow((x+.055)/1.055,2.4);
  for(let y=0;y<n;y++)for(let x=0;x<n;x++){
    const c=[x*4,y*4,(x^y)*4,255];source.push(...c);
    const at=((n-1-y)*n+x)*4;
    c.forEach((v,i)=>linear[at+i]=i===3?1:decode(v/255));
  }
  const tex=new THREE.DataTexture(linear,n,n,THREE.RGBAFormat,THREE.FloatType);
  tex.minFilter=tex.magFilter=THREE.LinearFilter;tex.needsUpdate=true;
  const mat=GLR.glPost.clone(),u=mat.uniforms;
  const sc=new THREE.Scene(),cam=new THREE.OrthographicCamera(-1,1,1,-1,0,1);
  const geo=new THREE.PlaneGeometry(2,2);sc.add(new THREE.Mesh(geo,mat));
  const rt=new THREE.WebGLRenderTarget(n,n,{depthBuffer:false,stencilBuffer:false});
  const ren=GLR.renderer, old=ren.getRenderTarget(),oldSpace=ren.outputColorSpace;
  const parameters={normal:'uFx',brightness:'uBright',exposure:'uExpo',gaze:'uGaze',red:'uRed',hurt:'uHurt',drain:'uDrain',tunnel:'uTunnel',blink:'uBlack'};
  const cases=[];
  try{
    ren.outputColorSpace=THREE.LinearSRGBColorSpace;
    for(const config of [{},{normal:.35},{normal:1},{brightness:.7},{brightness:1.3},{exposure:.6},{gaze:.9},{red:.8},{hurt:.7},{drain:.8},{tunnel:.7},{blink:.5},{normal:1,drain:.8,tunnel:.7,blink:.5}]){
      for(const key in u)if(typeof u[key].value==='number')u[key].value=0;
      u.uBright.value=u.uExpo.value=u.uSan.value=1;
      u.uRes.value.set(n,n);u.tDiffuse.value=tex;
      for(const key in config)u[parameters[key]].value=config[key];
      ren.setRenderTarget(rt);ren.render(sc,cam);
      const pixels=new Uint8Array(n*n*4),top=[];
      ren.readRenderTargetPixels(rt,0,0,n,n,pixels);
      for(let y=0;y<n;y++)for(let x=0;x<n;x++){const i=((n-1-y)*n+x)*4;top.push(...pixels.slice(i,i+4));}
      cases.push({config,pixels:top});
    }
  }finally{ren.setRenderTarget(old);ren.outputColorSpace=oldSpace;rt.dispose();tex.dispose();mat.dispose();geo.dispose();}
  const light=[];
  for(const room of ['teach1','garage1','portal_tunnel','out'])for(const t of [600,1200])for(const normal of [0,.5,1])for(const fake of [0,1]){
    freshState('hard');S.mode=room==='out'?'out':'in';S.room=room==='out'?null:room;S.tsec=t;AN.active=false;
    GLR.worldNorm=normal;GLR.fnNorm=fake;GLR.gaze=0;
    const v=lightState();light.push({room,t,normal,fake,day:v.day,amb:v.amb,hemi:v.hemi,dir:v.dir,pt:v.ptK});
  }
  return {reference:'wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc',size:n,source,cases,light};
}
