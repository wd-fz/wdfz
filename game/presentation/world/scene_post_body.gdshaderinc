uniform float tunnel=0.0;
uniform float blur=0.0;
uniform float focus=0.0;
uniform float drain=0.0;
uniform float warp=0.0;
uniform float breath=0.0;
uniform float pulse=0.0;
uniform float ghost=0.0;
uniform vec2 ghost_dir=vec2(1.0,0.0);
uniform float halo=0.0;
uniform float blink=0.0;
uniform float t=0.0;
uniform float normal=0.0;
uniform float brightness=1.0;
uniform float exposure=1.0;
uniform float grain=1.0;
uniform float san=1.0;
uniform float gaze=0.0;
uniform float red=0.0;
uniform float hurt=0.0;
uniform float bloom=0.0;
uniform bool lite=false;

float hash(vec2 p){p=fract(p*vec2(443.8975,397.2973));p+=dot(p,p.yx+19.19);return fract((p.x+p.y)*p.x);}
vec3 linear_color(vec3 c){return mix(c/12.92,pow((c+.055)/1.055,vec3(2.4)),step(vec3(.04045),c));}
vec3 srgb(vec3 c){c=clamp(c,vec3(0),vec3(1));return mix(c*12.92,1.055*pow(c,vec3(1.0/2.4))-.055,step(vec3(.0031308),c));}
vec3 scene(vec2 p){return linear_color(textureLod(screen_tex,vec2(p.x,1.0-p.y),0.0).rgb);}
vec3 aces(vec3 x){return clamp((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14),vec3(0),vec3(1));}
vec3 disk_blur(vec2 p,vec2 r,float rotation,float lod){
	vec3 s=vec3(0);float n=lite?6.0:12.0;
	for(int i=0;i<12;i++){if(float(i)>=n){break;}float fi=float(i)+.5;float rr=sqrt(fi/n);float th=fi*2.39996+rotation;
		vec2 uv=clamp(p+vec2(cos(th),sin(th))*rr*r,vec2(.001),vec2(.999));s+=linear_color(textureLod(screen_tex,vec2(uv.x,1.0-uv.y),lod).rgb);}
	return s/n;
}
void fragment(){
	vec2 res=1.0/SCREEN_PIXEL_SIZE;
	vec2 uv=vec2(SCREEN_UV.x,1.0-SCREEN_UV.y);
	// Three.js gl_FragCoord is bottom-up; Godot's canvas is top-down.
	vec2 frag=vec2(FRAGCOORD.x,res.y-FRAGCOORD.y);
	vec2 dc=uv-.5;vec2 q=dc*2.0;float e=length(q);float fx=1.0-normal;
	if(warp>.001&&fx>0.0){
		vec2 asp=vec2(res.x/res.y,1);vec2 p=dc*asp;float r=length(p);
		float a=.045*warp*sin(t*.31)*cos(t*.13+1.7)*fx;
		p=vec2(p.x*cos(a)-p.y*sin(a),p.x*sin(a)+p.y*cos(a));p*=1.0-.04*warp*breath*fx;
		vec2 w=vec2(sin(p.y*6.0+t*.9)+.6*sin((p.x+p.y)*4.1-t*.7),sin(p.x*5.2-t*.8)+.6*sin((p.x-p.y)*3.7+t*1.1));
		p+=w*.0125*warp*smoothstep(.03,.22,r)*fx;uv=p/asp+.5;
	}
	uv=clamp(uv,vec2(.001),vec2(.999));
	float bpx=(mix(3.2*blur*blur,13.0*blur,smoothstep(.15,.85,e))+4.5*focus)*fx;
	vec3 col=scene(uv);
	if(bpx>=.3){float rpx=bpx*min(res.x,res.y)/720.0;vec3 bl=disk_blur(uv,vec2(rpx)/res,hash(frag)*6.2832,log2(max(1.0,rpx*(lite?.7:.45))));col=mix(col,bl,smoothstep(.3,1.2,bpx));}
	if(ghost>.001){vec2 go=ghost_dir*(10.0*min(res.x,res.y)/720.0)/res;col=mix(col,scene(clamp(uv+go,vec2(.001),vec2(.999))),.5*ghost*smoothstep(.05,.3,e)*fx);}
	vec3 glow=vec3(0);
	if(bloom>0.0){vec3 bl=vec3(0);vec2 asp=vec2(res.y/res.x,1);
		for(int i=0;i<12;i++){float a=float(i)*.5236+.26;vec2 o=vec2(cos(a),sin(a))*asp;
			bl+=max(scene(uv+o*.007)-.62,vec3(0));bl+=max(scene(uv+o*.017)-.62,vec3(0))*.65;bl+=max(scene(uv+o*.034)-.62,vec3(0))*.35;}
		glow=bl/12.0*bloom;col+=glow;}
	if(halo>.001){vec3 hl=vec3(0);vec2 asp=vec2(res.y/res.x,1);
		for(int i=0;i<6;i++){float a=float(i)*1.0472+.5;vec2 o=vec2(cos(a),sin(a))*asp;
			hl+=max(scene(uv+o*.012)-.55,vec3(0))*(lite?1.6:1.0);if(!lite){hl+=max(scene(uv+o*.026)-.55,vec3(0))*.6;}}
		col+=min(hl/6.0*halo*.9*fx,max(vec3(0),vec3(.5)-glow));}
	col=aces(col*brightness*exposure*.96);
	float lum=dot(col,vec3(.2126,.7152,.0722));col=mix(vec3(lum),col,mix(.46+.49*gaze,1.0,normal));
	col*=vec3(1.03,1,.985);float lm=dot(col,vec3(.299,.587,.114));
	vec3 tint=mix(vec3(.66,.90,1.02),vec3(1,.98,.90),smoothstep(.04,.50,lm));col*=mix(tint,vec3(1),normal);
	col=col*col*(3.0-2.0*clamp(col,vec3(0),vec3(1)))*.28+col*.72;
	col=max(col-.009*fx,vec3(0))*(1.0+.009*fx);
	if(drain>.001){col=mix(col,vec3(dot(col,vec3(.2126,.7152,.0722))),.7*drain*fx);}
	float vg=distance(uv,vec2(.5));col*=1.0-.84*smoothstep(.20,.95,vg*1.28)*fx;
	if(tunnel>.001){float crawl=0.0;if(warp>.001){float th=atan(q.y,q.x+.000001);crawl=(.05*sin(th*3.0+t*.6)+.035*sin(th*5.0-t*.9))*warp;}
		float rr=1.6-1.15*tunnel-.09*pulse;col*=1.0-smoothstep(rr-.12,rr+.42,e+crawl)*min(1.0,tunnel*2.2)*.96*fx;}
	col*=mix(vec3(1),vec3(1,.32,.27),hurt*.85);
	col=mix(col,vec3(.16,0,0),hurt*.55*smoothstep(.28,.95,vg*1.3));
	col=mix(col,vec3(dot(col,vec3(.5,.4,.1)))*vec3(1.35,.22,.18),red*.75);
	col=mix(col,col*vec3(1.12,.93,.66),gaze*.7);
	col=mix(col,vec3(.022,.011,0),gaze*.85*smoothstep(.24,.86,vg*1.25));
	col*=1.0-blink*fx;
	vec3 outc=srgb(col);float gn=hash(frag+floor(t*24.0)*17.31)-.5;
	float glum=dot(outc,vec3(.299,.587,.114));float wob=clamp((.75-san)/.75,0.0,1.0);
	outc+=vec3(.011)*(1.0-smoothstep(0.0,.3,glum))*fx;
	outc+=vec3(gn)*(.012+.026*(1.0-smoothstep(.03,.45,glum)))*(1.0+.7*wob)*fx*grain;
	outc+=vec3((hash(frag*1.37+vec2(3.1,7.7))-.5)/255.0);
	COLOR=vec4(outc,1);
}
