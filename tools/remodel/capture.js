/* Injected into the old build's page (wd-fz.github.io@0bf508a) by capture_primitives.py.
   Records the parameters of every primitive the old build's own figGeo() lays down for a figure kind:
   nothing in the old code is changed; the model-pack lookup is bypassed for the call so the primitive path runs. */
(function(){
  'use strict';
  window.__wdfzFigurePrims = function(kind){
    var rec = [], KP = window.Kit.prototype, keep = {}, names = ['rod','blob','bevel','cyl','box'];
    names.forEach(function(n){
      keep[n] = KP[n];
      KP[n] = function(){ rec.push({t:n, a:Array.prototype.slice.call(arguments, 1).map(function(v){ return typeof v === 'number' ? Math.round(v * 1e6) / 1e6 : v; })}); return keep[n].apply(this, arguments); };
    });
    var A = window.Assets, get = A.get;
    A.get = function(n){ return /^fig_/.test(String(n)) ? null : get.apply(this, arguments); };
    var cache = window.FIG_GEO, saved = {};
    Object.keys(cache).forEach(function(k){ saved[k] = cache[k]; delete cache[k]; });
    try{ window.figGeo(kind); }
    finally{
      names.forEach(function(n){ KP[n] = keep[n]; });
      A.get = get;
      Object.keys(cache).forEach(function(k){ delete cache[k]; });
      Object.keys(saved).forEach(function(k){ cache[k] = saved[k]; });
    }
    return {kind:kind, spec:window.FIG_SPEC[kind], prims:rec};
  };
})();
