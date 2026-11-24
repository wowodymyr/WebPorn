(function(){
  function find(root){ var v=root.querySelectorAll('video'); var out=Array.prototype.slice.call(v); var all=root.querySelectorAll('*'); for(var i=0;i<all.length;i++){ if(all[i].shadowRoot) out=out.concat(find(all[i].shadowRoot)); if(all[i].tagName=='IFRAME'){ try{ if(all[i].contentDocument) out=out.concat(find(all[i].contentDocument)); }catch(e){} } } return out; }
  var vs=find(document), v=vs[0];
  if(!v){ var f=document.querySelector('iframe'); return 'no video '+document.title.slice(0,40)+(f?' iframe '+String(f.src).slice(0,80):''); }
  if(v.paused && !window.__wpPlayed){ window.__wpPlayed=1; v.muted=true; var p=v.play(); if(p&&p.catch) p.catch(function(e){ window.__wpErr=String(e); }); }
  var b=v.buffered, r=[]; for(var i=0;i<b.length;i++) r.push(b.start(i).toFixed(0)+'-'+b.end(i).toFixed(0));
  return ['n',vs.length,'src',String(v.currentSrc).slice(0,34),'rs',v.readyState,'ns',v.networkState,'t',v.currentTime.toFixed(1),'d',(v.duration||0).toFixed(0),'paused',v.paused,'err',v.error&&v.error.code,window.__wpErr||'','buf',r.join(',')].join(' ');
})()
