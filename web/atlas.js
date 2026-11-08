/* Appellation Atlas. A globe of every wine place there is.
   Places are shaded by how well known they are (regions/notoriety.json, from Wikipedia), darkest for the best known,
   compared with the other places on the same view. Tap or pinch into a place to go in; under the map is what is known
   about the place you are in: the rules, the grapes, the climate and the soil, more exact the deeper you go.
   Data: places.json and facts/<id>.json (src/atlas.py facts), geo/world.json, geo/index.json and geo/views/*.json
   (src/atlas.py geo). The place lives in the URL (#/france/burgundy), so the back button and shared links keep it.
   The globe code follows app/app.js; keep the two in step. */
(()=>{
'use strict';
const $=s=>document.querySelector(s), esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const fold=s=>String(s??'').normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase();
const NS='http://www.w3.org/2000/svg';
let GEO,WORLD,PL,VIEWS={},FACTS={},SCORED=false;   // SCORED: notoriety has been fetched
const START={lon:-33.56,lat:18.13,ex:.83775,ey:.9314};   // where the globe opens, and how much of it to fit
const S={p:'world'};
const fmt=n=>n==null?'':Math.round(n).toLocaleString('en-US');
// ---------- the place in the URL
function readHash(){const h=decodeURIComponent(location.hash.replace(/^#\/?/,'')); S.p=h&&PL[h]?h:'world';}
const link=id=>id&&id!=='world'?'#/'+id:'#/';
function go(id){if((id||'world')===S.p) return; location.hash=link(id);}
// ---------- notoriety: a place's shade, against the others on the same view
const score=id=>PL[id]?PL[id][2]:-1;
// Shade by where a place sits between the least and best known places on the same view, so one star (Napa) does not wash
// out the rest. The span is at least 20 points, so places that are nearly equal stay nearly the same shade.
function rangeOf(ids){const v=ids.map(score).filter(x=>x>=0); return v.length?[Math.min(...v),Math.max(...v)]:[0,0];}
function tierOf(s,r){if(s<0) return 0; const lo=Math.min(r[0],r[1]-20), t=(s-lo)/(r[1]-lo); return t>=.85?4:t>=.6?3:t>=.35?2:1;}
const wset=id=>!!(PL[id]&&PL[id][6]);   // in the WSET Level 4 Diploma (regions/wset.json): drawn in gold, the rest in greys
function shade(id,s,r){const t=tierOf(s,r); return wset(id)?`a${Math.max(1,t)}`:`a${t} o`;}

// ---------- the map: an orthographic globe that flies from the world down to the appellation
const RAD=Math.PI/180, TAU=2*Math.PI;
async function view(id){
  if(!VIEWS[id]){const r=await fetch('geo/views/'+id.replace(/\//g,'__')+'.json'); if(!r.ok) return null; const v=await r.json();
    for(const it of v.items) if(it.p) it.g=prep(it.p); if(v.ctx) for(const c of v.ctx) c.g=prep(c.p); v.og=prep(v.outline); VIEWS[id]=v;}
  return VIEWS[id];
}
function viewFor(p){let id=p; while(id&&id!=='world'&&!(GEO.places[id]&&GEO.places[id].view)) id=GEO.places[id]?.parent; return id||'world';}
function el(tag,attrs,parent){const e=document.createElementNS(NS,tag); for(const k in attrs) e.setAttribute(k,attrs[k]); if(parent) parent.appendChild(e); return e;}
function prep(P){
  return P.map(rings=>{let X=0,Y=0,Z=0;
    const rs=rings.map(r=>{const n=r.length/2, lam=new Float64Array(n), cp=new Float64Array(n), sp=new Float64Array(n);
      for(let i=0;i<n;i++){const l=r[2*i]*RAD,p=r[2*i+1]*RAD; lam[i]=l; cp[i]=Math.cos(p); sp[i]=Math.sin(p); X+=cp[i]*Math.cos(l); Y+=cp[i]*Math.sin(l); Z+=sp[i];}
      return {n,lam,cp,sp};});
    const L=Math.hypot(X,Y,Z)||1; X/=L;Y/=L;Z/=L; let m=1;
    for(const r of rs) for(let i=0;i<r.n;i++){const d=r.cp[i]*Math.cos(r.lam[i])*X+r.cp[i]*Math.sin(r.lam[i])*Y+r.sp[i]*Z; if(d<m) m=d;}
    return {rs,c:[X,Y,Z],rad:Math.acos(Math.max(-1,Math.min(1,m)))};});
}
function camOf(lon,lat,R){const l0=lon*RAD,p0=lat*RAD; return {lon,lat,R,l0,c0:Math.cos(p0),s0:Math.sin(p0),v:[Math.cos(p0)*Math.cos(l0),Math.cos(p0)*Math.sin(l0),Math.sin(p0)]};}
function pt(cam,lon,lat){const d=lon*RAD-cam.l0,p=lat*RAD,cp=Math.cos(p),sp=Math.sin(p),cd=Math.cos(d);
  return [cp*Math.sin(d),cam.c0*sp-cam.s0*cp*cd,cam.s0*sp+cam.c0*cp*cd];}
function unpt(cam,x,y){const r=Math.hypot(x,y); if(r>1) return null; const c=Math.asin(r), sc=Math.sin(c), cc=Math.cos(c);
  return [(cam.l0+Math.atan2(x*sc,r*cc*cam.c0-y*sc*cam.s0))/RAD,Math.asin(cc*cam.s0+(r?y*sc*cam.c0/r:0))/RAD];}
function projRing(r,cam){const out=new Array(r.n);
  for(let i=0;i<r.n;i++){const d=r.lam[i]-cam.l0,cd=Math.cos(d),cp=r.cp[i],sp=r.sp[i]; out[i]=[cp*Math.sin(d),cam.c0*sp-cam.s0*cp*cd,cam.s0*sp+cam.c0*cp*cd];}
  return out;}
function cross(a,b){const t=a[2]/(a[2]-b[2]),x=a[0]+t*(b[0]-a[0]),y=a[1]+t*(b[1]-a[1]),L=Math.hypot(x,y)||1; return [x/L,y/L,0];}
function clip(rings){   // cut a polygon at the horizon and close it along the globe's edge (outer rings run counterclockwise)
  const out=[],segs=[];
  for(const r of rings){const n=r.length; let vis=0; for(const p of r) if(p[2]>=0) vis++;
    if(vis===n){out.push(r); continue;} if(!vis) continue;
    let s=0; while(!(r[s][2]>=0&&r[(s-1+n)%n][2]<0)) s++;
    let cur=[cross(r[(s-1+n)%n],r[s])];
    for(let k=0;k<n;k++){const a=r[(s+k)%n],b=r[(s+k+1)%n];
      if(a[2]>=0){cur.push(a); if(b[2]<0){cur.push(cross(a,b)); segs.push(cur); cur=null;}}
      else if(b[2]>=0) cur=[cross(a,b)];}}
  const A=p=>Math.atan2(p[1],p[0]), sg=segs.map(p=>({p,a0:A(p[0]),a1:A(p[p.length-1]),used:false}));
  for(const s0 of sg){if(s0.used) continue; const ring=[]; let s=s0;
    for(let g=0;g<400;g++){s.used=true; for(const q of s.p) ring.push(q);
      let best=null,bd=9; for(const t of sg) if(!t.used||t===s0){let d=(t.a0-s.a1)%TAU; if(d<0) d+=TAU; if(d<bd){bd=d;best=t;}}
      const st=Math.ceil(bd/.06); for(let k=1;k<st;k++){const a=s.a1+bd*k/st; ring.push([Math.cos(a),Math.sin(a)]);}
      if(!best||best===s0) break; s=best;}
    out.push(ring);}
  return out;
}
const M={};
const r1=v=>Math.round(v*10)/10;
function polyD(poly,cam){
  const dot=poly.c[0]*cam.v[0]+poly.c[1]*cam.v[1]+poly.c[2]*cam.v[2], dist=Math.acos(Math.max(-1,Math.min(1,dot)));
  if(dist-poly.rad>M.va||Math.sin(Math.min(poly.rad,1.5))*cam.R<.35) return '';
  let rings=poly.rs.map(r=>projRing(r,cam)); if(dist+poly.rad>Math.PI/2-1e-4) rings=clip(rings);
  const cx=M.W/2,cy=M.H/2,R=cam.R; let d='';
  for(const r of rings) if(r.length>2){d+='M'; for(let i=0;i<r.length;i++) d+=(i?'L':'')+r1(cx+R*r[i][0])+','+r1(cy-R*r[i][1]); d+='Z';}
  return d;
}
function gratD(cam){
  const cx=M.W/2,cy=M.H/2,R=cam.R; let d='';
  const line=pts=>{let on=false; for(const [lo,la] of pts){const p=pt(cam,lo,la); if(p[2]<0){on=false; continue;} d+=(on?'L':'M')+r1(cx+R*p[0])+','+r1(cy-R*p[1]); on=true;}};
  for(let lo=-180;lo<180;lo+=15){const a=[]; for(let la=-80;la<=80;la+=4) a.push([lo,la]); line(a);}
  for(let la=-75;la<=75;la+=15){const a=[]; for(let lo=-180;lo<=180;lo+=4) a.push([lo,la]); line(a);}
  return d;
}
function camFor(v){
  if(v.id==='world'){const h=START; return camOf(h.lon,h.lat,Math.min(M.W/2/h.ex,M.H/2/h.ey)*.94);}
  return camOf(v.center[0],v.center[1],Math.min(M.W/2/v.half[0],M.H/2/v.half[1])*.9);}
function draw(){
  const cam=M.cam, hd=Math.hypot(M.W,M.H)/2; M.va=hd>=cam.R?Math.PI/2:Math.asin(hd/cam.R)+.01;
  M.ocean.setAttribute('r',r1(cam.R)); M.rim.setAttribute('r',r1(cam.R));
  M.grat.setAttribute('d',cam.R<Math.min(M.W,M.H)*2.5?gratD(cam):'');
  for(const f of M.feats) if(f.on()) f.el.setAttribute('d',f.g.map(p=>polyD(p,cam)).join(''));
}
function needWorld(cam,v){
  if(!v.box) return true;
  for(const [X,Y] of [[0,0],[M.W,0],[0,M.H],[M.W,M.H],[M.W/2,0],[M.W/2,M.H],[0,M.H/2],[M.W,M.H/2]]){
    const q=unpt(cam,(X-M.W/2)/cam.R,(M.H/2-Y)/cam.R); if(!q) continue;
    let lo=q[0]; while(lo<v.box[0]-180) lo+=360; while(lo>v.box[0]+180) lo-=360;
    if(lo<v.box[0]||lo>v.box[2]||q[1]<v.box[1]||q[1]>v.box[3]) return true;}
  return false;
}
function addFeat(g,cls,geo,extra){const e=el('path',Object.assign({class:cls},extra||{}),g); const f={el:e,g:geo,on:()=>g.isConnected&&g.style.display!=='none'}; M.feats.push(f); return f;}
function buildView(v,par){   // a view's layers: the land near it, its neighbours, the place itself, its places
  const g=el('g',{class:'vw'}); M.layers.insertBefore(g,null);
  if(v.ctx){const c=el('g',{class:'ctxg'},g); for(const x of v.ctx) addFeat(c,'land',x.g);}
  const sg=el('g',{},g);
  if(par) for(const it of par.items) if(it.g&&it.id!==v.id){const f=addFeat(sg,'rg sib',it.g,{'data-id':it.id}); f.it=it; f.sib=true;}
  if(v.og.length&&v.id!=='world') addFeat(g,'self',v.og);
  if(v.og.length) addFeat(g,'outline',v.og);
  const ig=el('g',{},g);
  for(const it of v.items) if(it.g){const f=addFeat(ig,'rg',it.g,{'data-id':it.id}); f.it=it;}
  g.view=v; return g;
}
function dropView(g){M.feats=M.feats.filter(f=>!g.contains(f.el)); g.remove();}
const kindOf=id=>PL[id]?.[3]||'';
function restyle(){
  const v=M.view; if(!v) return; const rng=rangeOf(v.items.map(i=>i.id));
  M.rng=rng;
  for(const f of M.feats) if(f.it){
    f.el.setAttribute('class',`rg${f.sib?' sib a0':' '+shade(f.it.id,score(f.it.id),rng)}${M.leaf===f.it.id?' sel':''}`);
    f.el.replaceChildren(); el('title',{},f.el).textContent=f.it.name+(kindOf(f.it.id)?` (${kindOf(f.it.id)})`:'');}
}
function labels(){
  const g=M.lab; g.replaceChildren(); const v=M.view, cam=M.cam; if(!v) return;
  const cx=M.W/2,cy=M.H/2,R=cam.R, placed=[], fs=13;
  const scr=([lo,la])=>{const p=pt(cam,lo,la); return p[2]<0?null:[cx+R*p[0],cy-R*p[1]];};
  const free=b=>!(b[0]<2||b[2]>M.W-2||b[1]<2||b[3]>M.H-2||placed.some(o=>b[0]<o[2]-2&&o[0]<b[2]-2&&b[1]<o[3]-2&&o[1]<b[3]-2));
  const live=v.items.filter(i=>i.g).sort((a,b)=>(M.leaf===b.id)-(M.leaf===a.id)||score(b.id)-score(a.id));
  for(const it of v.items) it.s=null;
  for(const it of live){   // too small to tap at this size: add a dot (not on the world view)
    const f=M.feats.find(f=>f.it===it&&!f.sib), bb=f&&f.el.getBBox(); const s=scr(it.l); if(!s) continue; it.s=s; it.dot=v.id!=='world'&&(!bb||Math.max(bb.width,bb.height)<16); it.bb=bb;   // no dots for countries: a small one gets its name only
    if(it.dot){const c=el('circle',{cx:r1(s[0]),cy:r1(s[1]),r:6,class:`dot-m ${shade(it.id,score(it.id),M.rng)}${M.leaf===it.id?' sel':''}`,'data-id':it.id},g); el('title',{},c).textContent=it.name; placed.push([s[0]-5,s[1]-5,s[0]+5,s[1]+5]);}}
  for(const it of live){if(!it.s) continue; const t=it.name, w=t.length*fs*.56, h=fs*1.2, [x,y]=it.s;
    const tries=it.dot?[[x+10,y+4,'start'],[x-10,y+4,'end'],[x,y-11,'middle'],[x,y+h+8,'middle']]
      :[[x,y+fs*.35,'middle'],[x,y-8,'middle'],[x,y+h+4,'middle'],[x+12,y+fs*.35,'start'],[x-12,y+fs*.35,'end'],[x+8,y-8,'start'],[x-8,y-8,'end'],[x+8,y+h+4,'start'],[x-8,y+h+4,'end']];
    if(it===live[0]) tries.push([x,y+fs*.35,'middle','force']);
    for(const [X,Y,a,force] of tries){const x0=a==='middle'?X-w/2:a==='end'?X-w:X; if(!force&&!free([x0,Y-h,x0+w,Y+h*.25])) continue;
      const e=el('text',{x:r1(X),y:r1(Y),'font-size':fs,'text-anchor':a,'data-id':it.id},g); e.textContent=t;   // then its measured box, as the estimate runs short on wide names
      const r=e.getBBox(), bx=[r.x-4,r.y,r.x+r.width+4,r.y+r.height]; if(!force&&!free(bx)){e.remove(); continue;}   // 4px apart at least
      placed.push(bx); break;}}
  if(v.id!=='world'){   // the countries around, for bearings
    const here=v.id.split('/')[0], own=PL[here]?.[0];
    for(const c of WORLD.countries){if(c.n===own) continue; const s=scr(c.l); if(!s) continue; const t=c.n.toUpperCase(), w=t.length*10*.62, bx=[s[0]-w/2,s[1]-10,s[0]+w/2,s[1]+3];
      if(!free(bx)) continue; placed.push(bx); el('text',{x:r1(s[0]),y:r1(s[1]),class:'cl','text-anchor':'middle'},g).textContent=t;}}
}
const ease=k=>k<.5?4*k*k*k:1-Math.pow(-2*k+2,3)/2;
function setWorld(o){M.world.style.opacity=o; M.world.style.display=o>0?'':'none';}
async function fly(v,par){
  const g=buildView(v,par), old=[...M.layers.children].filter(x=>x!==g), a=M.cam, b=camFor(v);
  M.view=v; M.par=par; restyle(); M.lab.replaceChildren();
  const wa=+M.world.style.opacity||0, wb=needWorld(b,v)?1:0; setWorld(Math.max(wa,.001));
  let dl=b.lon-a.lon; dl=((dl+540)%360)-180;
  const zr=Math.abs(Math.log(b.R/a.R)), ms=Math.min(1900,900+zr*160);
  M.busy=true; g.style.opacity=0;
  await new Promise(res=>{const t0=performance.now(); const step=t=>{const k=Math.min(1,(t-t0)/ms), e=ease(k);
    M.cam=camOf(a.lon+dl*e,a.lat+(b.lat-a.lat)*e,Math.exp(Math.log(a.R)+(Math.log(b.R)-Math.log(a.R))*e));
    const fi=Math.min(1,Math.max(0,(e-.15)/.6)); g.style.opacity=fi; for(const o of old) o.style.opacity=1-fi; setWorld(Math.max(.001,wa+(wb-wa)*e));
    draw(); k<1?requestAnimationFrame(step):res();}; requestAnimationFrame(step);});
  for(const o of old) dropView(o); M.cam=b; setWorld(wb); g.style.opacity=1; M.busy=false; draw();
}
async function intro(b){
  const a=camOf(b.lon+300,b.lat-20,b.R*.05), ms=3600, out=k=>1-Math.pow(1-k,3);
  M.busy=true; M.svg.style.opacity=0;
  await new Promise(res=>{const t0=performance.now(); const step=t=>{const k=Math.min(1,(t-t0)/ms), z=ease(Math.min(1,k*1.15)), sp=out(k);
    M.cam=camOf(a.lon+(b.lon-a.lon)*sp,a.lat+(b.lat-a.lat)*sp,Math.exp(Math.log(a.R)+(Math.log(b.R)-Math.log(a.R))*z));
    M.svg.style.opacity=Math.min(1,k*5); draw(); k<1?requestAnimationFrame(step):res();}; requestAnimationFrame(step);});
  M.cam=b; M.svg.style.opacity=''; M.busy=false; draw();
}
function mapSize(){const w=M.box.clientWidth||360, h=Math.round(Math.max(320,Math.min(w*.95,innerHeight*.62))); M.W=w; M.H=h;
  M.svg.setAttribute('viewBox',`0 0 ${w} ${h}`); M.svg.setAttribute('height',h); M.ocean.setAttribute('cx',w/2); M.ocean.setAttribute('cy',h/2); M.rim.setAttribute('cx',w/2); M.rim.setAttribute('cy',h/2);}
function mapInit(){
  M.box=$('#map'); M.feats=[];
  M.svg=el('svg',{role:'img','aria-label':'Globe of the world’s wine places'});
  const defs=el('defs',{},M.svg), gr=el('radialGradient',{id:'sea',cx:'42%',cy:'38%',r:'62%'},defs);
  el('stop',{offset:'0','stop-color':'var(--ocean-hi)'},gr); el('stop',{offset:'1','stop-color':'var(--ocean)'},gr);
  M.ocean=el('circle',{class:'ocean',fill:'url(#sea)'},M.svg); M.grat=el('path',{class:'grat'},M.svg);
  M.world=el('g',{class:'world'},M.svg); for(const c of WORLD.countries){c.g=prep(c.p); addFeat(M.world,'land',c.g);}
  M.layers=el('g',{},M.svg); M.rim=el('circle',{class:'rim'},M.svg); M.lab=el('g',{class:'lab'},M.svg);
  M.box.replaceChildren(M.svg); mapSize();
  const out=document.createElement('button'); out.type='button'; out.className='zout ts-place_subtitle'; out.onclick=zoomOut; out.hidden=true; M.box.appendChild(out); M.out=out;
  M.svg.addEventListener('click',e=>{if(M.dragged||M.busy) return; const t=e.target.closest('[data-id]');
    if(t){pick(t.dataset.id); return;}
    const b=M.svg.getBoundingClientRect(), x=(e.clientX-b.left)*M.W/b.width, y=(e.clientY-b.top)*M.H/b.height;   // a near miss: the closest place within a fingertip
    let best=null,bd=24; for(const it of M.view.items) if(it.s){const d=Math.hypot(it.s[0]-x,it.s[1]-y); if(d<bd){bd=d;best=it;}} if(best) pick(best.id);});
  M.svg.addEventListener('dblclick',e=>{if(!e.target.closest('[data-id]')) zoomOut();});
  const P=new Map(); let g0=null, wt;
  const loc=(x,y)=>{const b=M.svg.getBoundingClientRect(); return [(x-b.left)*M.W/b.width,(y-b.top)*M.H/b.height];};
  const geoAt=(cam,s)=>unpt(cam,(s[0]-M.W/2)/cam.R,(M.H/2-s[1])/cam.R);
  const mid=()=>{const v=[...P.values()], x=v.reduce((t,p)=>t+p[0],0)/v.length, y=v.reduce((t,p)=>t+p[1],0)/v.length;
    return [loc(x,y),v.length>1?Math.hypot(v[0][0]-v[1][0],v[0][1]-v[1][1]):0];};
  const begin=()=>{const [s,d]=mid(); g0={cam:M.cam,s,d,geo:geoAt(M.cam,s),flat:P.size===1&&M.view.id==='world'&&!zoomed()};};
  M.svg.addEventListener('pointerdown',e=>{if(M.busy) return; P.set(e.pointerId,[e.clientX,e.clientY]); if(P.size===1) M.dragged=false; begin();});
  M.svg.addEventListener('pointermove',e=>{if(!P.has(e.pointerId)||M.busy||!g0) return; P.set(e.pointerId,[e.clientX,e.clientY]);
    let [s,d]=mid();
    if(P.size===1){if(!M.dragged&&Math.hypot(s[0]-g0.s[0],s[1]-g0.s[1])<6) return; if(g0.flat&&e.pointerType==='touch') s=[s[0],g0.s[1]];}
    if(!M.dragged){M.dragged=true; M.lab.replaceChildren(); try{M.svg.setPointerCapture(e.pointerId);}catch(_){}}
    look(g0.geo,s,P.size>1&&g0.d?clampR(g0.cam.R*d/g0.d):g0.cam.R,g0.cam);});
  const up=e=>{if(!P.delete(e.pointerId)) return; if(P.size) begin(); else {g0=null; if(M.dragged) settle();}};
  M.svg.addEventListener('pointerup',up); M.svg.addEventListener('pointercancel',up);
  M.svg.addEventListener('wheel',e=>{if(!e.ctrlKey) return; e.preventDefault(); if(M.busy) return;
    const s=loc(e.clientX,e.clientY); M.lab.replaceChildren(); look(geoAt(M.cam,s),s,clampR(M.cam.R*Math.exp(-Math.max(-50,Math.min(50,e.deltaY))*.01)),M.cam);
    clearTimeout(wt); wt=setTimeout(settle,250);},{passive:false});
  M.svg.addEventListener('touchmove',e=>{if(e.touches.length>1) e.preventDefault();},{passive:false});
  for(const t of ['gesturestart','gesturechange']) M.svg.addEventListener(t,e=>e.preventDefault());
  addEventListener('resize',()=>{if(!M.view) return; mapSize(); M.cam=camFor(M.view); draw(); labels();});
}
const baseR=()=>camFor(M.view).R, zoomed=()=>M.cam.R>baseR()*1.03;
function clampR(R){const b=baseR(), w=M.view.id==='world'; return Math.min(b*(w?14:8),Math.max(b*(w?.8:.5),R));}
function look(geo,s,R,cam0){
  let c=geo&&unpt(camOf(geo[0],geo[1],R),(M.W/2-s[0])/R,(s[1]-M.H/2)/R); if(!c) c=[cam0.lon,cam0.lat];
  M.cam=camOf(c[0],Math.max(-80,Math.min(80,c[1])),R); if(M.view.id!=='world') setWorld(needWorld(M.cam,M.view)?1:0); draw();
}
function touchMode(){M.svg.style.touchAction=M.view.id==='world'&&!zoomed()?'pan-y':'none';}
async function settle(){
  if(M.busy||!M.view) return; const v=M.view, b=camFor(v);
  if(v.id!=='world'&&M.cam.R<b.R*.75){zoomOut(); return;}
  if(M.cam.R>b.R*1.03&&await deeper()) return;
  if(M.busy||M.view!==v) return;
  if(M.cam.R<b.R) glide(v.id==='world'?camOf(M.cam.lon,Math.max(-60,Math.min(70,M.cam.lat)),b.R):b); else {labels(); touchMode();}
}
async function deeper(){   // the place that fills most of the screen, near the middle, when it clearly leads and has its own map
  const hd=Math.hypot(M.W,M.H)/2, sc=[];
  for(const f of M.feats) if(f.it&&!f.sib&&f.on()&&f.el.getAttribute('d')){const bb=f.el.getBBox();
    const x0=Math.max(0,bb.x), x1=Math.min(M.W,bb.x+bb.width), y0=Math.max(0,bb.y), y1=Math.min(M.H,bb.y+bb.height); if(x1<=x0||y1<=y0) continue;
    const a=(x1-x0)*(y1-y0)/(M.W*M.H), d=Math.hypot((x0+x1)/2-M.W/2,(y0+y1)/2-M.H/2)/hd; sc.push([f.it,a,a*(1-d*.8)]);}
  sc.sort((p,q)=>q[2]-p[2]); const [best,area,score_]=sc[0]||[];
  if(!best||area<.2||(sc[1]&&sc[1][2]*1.3>score_)) return false;
  if(viewFor(best.id)!==best.id){if(area>.45){go(best.id); return true;} return false;}   // an appellation with nothing inside: zoomed onto it, it is chosen
  const cv=await view(best.id); if(!cv||M.cam.R<camFor(cv).R*.6) return false;
  go(best.id); return true;
}
async function glide(b,ms=500){
  const a=M.cam; let dl=b.lon-a.lon; dl=((dl+540)%360)-180; M.busy=true; M.lab.replaceChildren();
  await new Promise(res=>{const t0=performance.now(); const step=t=>{const k=Math.min(1,(t-t0)/ms), e=ease(k);
    M.cam=camOf(a.lon+dl*e,a.lat+(b.lat-a.lat)*e,Math.exp(Math.log(a.R)+(Math.log(b.R)-Math.log(a.R))*e)); if(M.view.id!=='world') setWorld(needWorld(M.cam,M.view)?1:0);
    draw(); k<1?requestAnimationFrame(step):res();}; requestAnimationFrame(step);});
  M.cam=b; M.busy=false; draw(); labels(); touchMode();
}
function zoomOut(){if(M.busy||!M.view) return; const v=M.view;
  if(M.leaf){go(v.id); return;}
  if(v.id==='world'){if(zoomed()) glide(camFor(v)); return;} go(v.parent);}
let want=null;
async function mapShow(){
  want=S.p; if(M.going) return; M.going=true;
  try{
    while(true){const p=want, v=await view(viewFor(p))||await view('world'), par=v.parent?await view(v.parent):null;
      M.leaf=p!==v.id&&p!=='world'?p:null;
      if(!M.view){const b=camFor(v); buildView(v,par); M.view=v; M.par=par; setWorld(needWorld(b,v)?1:0); restyle();
        if(v.id==='world'&&!matchMedia('(prefers-reduced-motion: reduce)').matches) await intro(b); else {M.cam=b; draw();}}
      else if(M.view.id!==v.id) await fly(v,par);
      else if(M.cam.R>camFor(v).R*1.03&&!M.leaf) await glide(camFor(v));
      if(want===p) break;}
    restyle(); labels();
    const v=M.view; M.out.hidden=v.id==='world'&&!M.leaf;
    M.out.textContent='‹ '+(M.leaf?v.name:v.parent==='world'?'The world':PL[v.parent]?.[0]||'Back');
    touchMode();
  } finally {M.going=false;}
}
function pick(id){
  if(M.busy) return;
  if(S.p===id){go(M.view.id); return;}   // tap the chosen place again to step back out
  go(id);
}
// ---------- under the map: the places here, and what is known about the place you are in
function renderPlaces(){
  const vid=viewFor(S.p), here=Object.keys(GEO.places).filter(i=>GEO.places[i].parent===vid);
  const rng=rangeOf(here);
  const sorted=here.sort((a,b)=>score(b)-score(a)||PL[a][0].localeCompare(PL[b][0]));
  const chain=[]; let id=vid; while(id&&id!=='world'){chain.unshift(id); id=GEO.places[id]?.parent;}
  const leaf=S.p!==vid?S.p:null;
  const crumbs=[['world','The world'],...chain.map(i=>[i,PL[i][0]]),...(leaf?[[leaf,PL[leaf][0]]]:[])];
  $('#crumbs').innerHTML=crumbs.map(([i,n],k)=>k===crumbs.length-1?`<b>${esc(n)}</b>`:`<a href="${link(i)}">${esc(n)}</a>`).join(' › ');
  if(M.allFor!==vid){M.all=false; M.allFor=vid;}
  const bench=sorted.filter(wset), emerg=sorted.filter(i=>!wset(i)), cap=bench.length?12:30, shown=M.all?emerg:emerg.slice(0,cap);
  const step=i=>`<a class="step ts-ladder_step" href="${link(i)}" aria-pressed="${S.p===i}"><i class="sw ${shade(i,score(i),rng)}"></i>${esc(PL[i][0])}${GEO.places[i].source?'':'<small> no map</small>'}</a>`;
  const grp=(head,list,n)=>list.length?`<p class="grp ts-fact_label">${head} <small class="ts-caption">${n}</small></p><div class="steps">${list.map(step).join('')}</div>`:'';
  const body=grp('Benchmark regions',bench,bench.length)+grp('Emerging regions',shown,emerg.length)
    +(emerg.length>shown.length?`<button type="button" class="link ts-caption more" id="allp">Show all ${emerg.length}</button>`:'');
  const where=vid==='world'?'Countries':'Places in '+esc(PL[vid]?.[0]||'');
  $('#places').innerHTML=!sorted.length?'':leaf&&leaf!=='world'   // on a place's own page its neighbours fold away, so its page comes first
    ?`<details class="sibs"${M.sibsOpen?' open':''}><summary class="ts-section_head inside">Other places in ${esc(PL[vid]?.[0]||'')} <small class="ts-caption">${sorted.length}</small></summary>${body}</details>`
    :`<h3 class="ts-section_head inside">${where}</h3>${body}`;
  const sd=$('#places details.sibs'); if(sd) sd.ontoggle=()=>{M.sibsOpen=sd.open;};
  const ap=$('#allp'); if(ap) ap.onclick=()=>{M.all=true; renderPlaces();};
  $('#mapNote').textContent=vid==='world'?'Tap a country or pinch to zoom in. Drag to turn the globe.':'Tap a place to go in. Drag to move. Pinch to zoom in or out.';
}
async function facts(id){
  if(!FACTS[id]){const r=await fetch('facts/'+id.replace(/\//g,'__')+'.json'); FACTS[id]=r.ok?await r.json():null;}
  return FACTS[id];
}
const SKINS=[['red','Red grapes'],['white','White grapes'],['pink','Pink and grey grapes']];
const fact=(label,value,note)=>value==null||value===''?'':`<div class="fact"><span class="ts-fact_label">${label}</span><span class="ts-fact_value">${value}</span>${note?`<span class="ts-fact_note">${note}</span>`:''}</div>`;
const chips=list=>`<div class="chips">${list.map(([g,sk,n])=>`<span class="chip ${sk||''}">${esc(g)}${n!=null?`<b>${n}</b>`:''}</span>`).join('')}</div>`;
const block=(head,body,note)=>body?`<section class="row"><div class="head"><h2 class="ts-section_head">${head}</h2>${note?`<span class="ts-caption">${note}</span>`:''}</div>${body}</section>`:'';
const toF=c=>c*9/5+32, inch=mm=>mm/25.4, ft=m=>Math.round(m*3.281/10)*10;
const reading=xs=>xs&&xs.length?`<div class="why"><p class="why-head ts-fact_label">Why it matters</p><dl>${xs.map(([k,v])=>`<dt class="ts-fact_label">${esc(k)}</dt><dd class="ts-body">${esc(v)}</dd>`).join('')}</dl></div>`:'';
const para=t=>t?`<p class="ts-body soil-text">${esc(t)}</p>`:'';
const bigNote=f=>f.large?`<p class="ts-caption big-note">${f.parts?'Too big and varied for one reading. These figures average all of it; the table further down compares the places inside.':'Too big and varied for one reading. These figures average all of it, hills and valleys alike.'}</p>`:'';
function scale(segs,i,pos,label){   // a row of categories, the place's one lit and marked
  const w=100/segs.length;
  return `<div class="scale" role="img" aria-label="${esc(label)}">${segs.map(([n,r],k)=>`<div class="seg${k===i?' on':''}" style="width:${w}%"><span class="n">${esc(n)}</span><span class="r">${esc(r)}</span></div>`).join('')}`
    +(i>=0?`<i class="mark" style="left:${(i+Math.max(.04,Math.min(.96,pos)))*w}%"></i>`:'')+`</div>`;
}
const GST_F=[['Too cool',-99,13,'under 55°F'],['Cool',13,15,'55 to 59°F'],['Intermediate',15,17,'59 to 63°F'],['Warm',17,19,'63 to 66°F'],['Hot',19,24,'66 to 75°F'],['Too hot',24,99,'over 75°F']];
const WK_F=[['Below Ia',0,850,'under 1,500'],['Ia',850,1111,'1,500 to 2,000'],['Ib',1111,1389,'2,000 to 2,500'],['II',1389,1667,'2,500 to 3,000'],['III',1667,1944,'3,000 to 3,500'],['IV',1944,2222,'3,500 to 4,000'],['V',2222,2700,'4,000 to 4,900'],['Above V',2700,9999,'over 4,900']];
function seg(t,v){const i=t.findIndex(([,lo,hi])=>lo<=v&&v<hi); if(i<0) return [-1,0]; const [,lo,hi]=t[i], a=lo<-50?hi-2:lo, b=hi>90?lo+2:hi>5000?lo+400:hi; return [i,(v-a)/(b-a)];}
function months(vals,unit,cls,south){   // twelve bars, the growing season marked
  if(!vals) return ''; const max=Math.max(...vals.map(Math.abs),1), w=22, h=56, gs=south?[9,10,11,0,1,2,3]:[3,4,5,6,7,8,9];
  const bars=vals.map((v,i)=>{const bh=Math.max(1,Math.abs(v)/max*(h-14)); return `<rect x="${i*w+3}" y="${h-bh-12}" width="${w-6}" height="${bh}" class="${cls}${gs.includes(i)?' gs':''}"/><text x="${i*w+w/2}" y="${h-1}" text-anchor="middle">${'JFMAMJJASOND'[i]}</text>`;}).join('');
  return `<svg class="months" viewBox="0 0 ${12*w} ${h}" role="img" aria-label="Monthly ${unit}">${bars}</svg>`;
}
const SHAPE_NOTE={'Eurostat NUTS, the area it is named for':'The map draws the department, province or region it is named for. The PGI\u2019s own area can differ a little.',
  'Eurostat LAU, the commune it is named for':'The map draws the commune it is named for.',
  'Chile Decreto 464, drawn from its comunas and provinces':'The boundary follows the comunas and provinces that Chile\u2019s Decreto 464 names.',
  'geoBoundaries, the department it is named for':'The map draws the department it is named for. The IG\u2019s own area can be smaller.',
  'geoBoundaries, the province it is named for':'The map draws the province.',
  'IPONZ GI register':'The boundary is the one on New Zealand\u2019s GI register.','Wine Australia GI boundaries':'The boundary is Wine Australia\u2019s. The legal one is the written description in the register.',
  'union of its children':'There is no single boundary for it, so the map joins the places inside it.'};
function renderTitle(id,f){   // the place's name, what it is and which group it is in, above the map
  const cap=x=>x?x[0].toUpperCase()+x.slice(1):x;
  if(id==='world'){$('#ptitle').innerHTML=`<h2 class="ts-sheet_title name">The world</h2>`; $('#shapeNote').hidden=true; return;}
  const kind=f?(f.kind.length?f.kind.map(cap).join(' and '):(f.depth===0?'Country':f.shape==='Eurostat LAU, the commune it is named for'?'Commune':'Region')):'';
  $('#ptitle').innerHTML=`<p class="ts-eyebrow eyebrow">${esc(kind)}${kind?' · ':''}<span class="badge ${wset(id)?'':'o'}">${wset(id)?'Benchmark region':'Emerging region'}</span></p><h2 class="ts-sheet_title name" style="--n:${Math.max(...String(PL[id]?.[0]||id).split(/\s+/).map(w=>w.length))}">${esc(PL[id]?.[0]||id)}</h2>`
    +(f&&f.also.length?`<p class="ts-caption also">Also ${f.also.map(esc).join(', ')}</p>`:'');
  const sn=f&&SHAPE_NOTE[f.shape]; $('#shapeNote').hidden=!sn; $('#shapeNote').textContent=sn||'';
}
function renderInfo(f){
  if(!f){$('#info').innerHTML=''; return;}
  renderTitle(f.id,f);
  const kn=f.known, X={}; let h='';
  const knownLine=(SCORED?`<p class="ts-caption known">${!kn?'No Wikipedia article of its own, so it is drawn in the lightest shade.'
      :`<i class="sw ${shade(f.id,kn.score,M.rng??[kn.score,kn.score])}"></i>${kn.articles
        ?`Scored from ${fmt(kn.articles)} Wikipedia article${kn.articles===1?'':'s'} on it and its places, ${fmt(kn.total)} page views in the last ${kn.days} days in all${kn.best?`. Best known: ${esc(PL[kn.best]?.[0]||kn.best)}`:''}.${kn.langs==null?' No article of its own.':''}`
        :`Known: in ${kn.langs} Wikipedia${kn.langs===1?'':'s'}, ${fmt(kn.views)} page views in the last ${kn.days} days.`}${kn.url?` <a href="${esc(kn.url)}" target="_blank" rel="noopener">Read about it on Wikipedia</a>`:''}`}</p>`:'');
  const sm=f.summary;
  if(sm){
    const k=sm.kinds.map(([k,n])=>`${n} ${k}${n===1?'':'s'}`).join(', ');
    let b=`<div class="facts">${fact('Places inside',fmt(sm.places),k)}${sm.gst?fact('Growing season',`${Math.round(toF(sm.gst[0]))} to ${Math.round(toF(sm.gst[1]))}°F`,'average temperature across its places'):''}</div>`;
    if(sm.grapes.length&&!f.planted) b+=`<p class="ts-caption sub">The grapes most often allowed, and in how many of its ${sm.with_rules} appellation${sm.with_rules===1?'':'s'} with rules:</p>${chips(sm.grapes)}`;
    X.glance=block('At a glance',b);
  }
  const R=f.research;
  if(R&&R.sheet){X.short=block('In short',`<div class="prose">${Object.values(R.sheet).filter(Boolean).map(t=>`<p class="ts-body">${esc(t)}</p>`).join('')}</div>`,'From our research');}
  const pl=f.planted;
  if(pl&&pl.grapes.length){
    const where=pl.scope==='country'?'':pl.scope==='own'?`in ${pl.names.join(' and ')}`:pl.scope==='within'?`across ${pl.names.slice(0,4).join(', ')}${pl.names.length>4?` and ${pl.names.length-4} more`:''}`
      :`across ${pl.names.slice(0,3).join(', ')}${pl.names.length>3?` and ${pl.names.length-3} more`:''}, the wider area it sits in`;
    const top=pl.grapes[0][1]||1, ac=ha=>fmt(Math.round(ha*2.471));
    const other=pl.grapes.find(([g])=>g==='Other'), rows=pl.grapes.filter(([g,ha])=>g!=='Other'&&(ha/pl.ha>=.01||pl.grapes.length<=6)).map(([g,ha,c],k)=>`<div class="gr ${pl.legal?pl.legal[pl.grapes.findIndex(x=>x[0]===g)]||'':''}"><span class="g ts-body"><i class="dot ${c==='W'?'w':c==='R'?'r':'o'}"></i>${esc(g)}</span><span class="bar"><i style="width:${Math.min(100,Math.max(1,ha/top*100))}%"></i></span><span class="pc ts-caption">${Math.round(ha/pl.ha*100)||'<1'}%</span>${pl.legal&&pl.legal[pl.grapes.findIndex(x=>x[0]===g)]==='minor'?'<span class="tag ts-caption">minor role</span>':''}</div>`).join('');
    X.planted=block('What is planted',`<p class="ts-caption sub">${ac(pl.ha)} acres of vines${where?' '+esc(where):''}, ${pl.year}</p>${pl.legal?`<p class="ts-caption sub legal-key"><span><i class="lk main"></i>Can carry the ${esc(f.name)} name</span><span><i class="lk no"></i>Grown here, but sold under another name</span></p>`:''}<div class="planted">${rows}</div>${other?`<p class="ts-caption sub">Other grapes: ${Math.round(other[1]/pl.ha*100)}%</p>`:''}`,'Share of vineyard area');
  }
  const ru=f.rules;
  if(ru){
    let b='';
    for(const [sk,head] of SKINS){const g=ru.grapes.filter(x=>x[1]===sk); if(g.length) b+=`<p class="ts-caption sub">${head}</p>${chips(g)}`;}
    const un=ru.grapes.filter(x=>!x[1]); if(un.length) b+=`<p class="ts-caption sub">Grapes</p>${chips(un)}`;
    if(ru.grapes_other.length) b+=`<p class="ts-caption sub">Also allowed, in smaller roles</p>${chips(ru.grapes_other)}`;
    b+=`<div class="facts">${fact('Wine types',ru.types.join(', '))}${fact('Highest yield',ru.yield_hl?`${fmt(ru.yield_hl)} hl/ha`:ru.yield_kg?`${fmt(ru.yield_kg)} kg/ha`:null,ru.yield_hl&&ru.yield_kg?`${fmt(ru.yield_kg)} kg/ha`:'')}`
      +`${fact('Fewest vines',ru.density?`${fmt(ru.density)} per ha`:null)}${fact('Irrigation',ru.irrigation)}${fact('Protected since',ru.registered?ru.registered.slice(0,4):null)}${fact('Communes',ru.communes.length?fmt(ru.communes.length):null)}</div>`;
    if(ru.communes.length) b+=`<details class="more-d"><summary class="ts-caption">The communes</summary><p class="ts-caption">${ru.communes.map(esc).join(', ')}</p></details>`;
    X.rules=block('The rules',b,'Allowed grapes, not plantings');
  }
  const av=f.ava;
  if(av){
    const b=`<div class="facts">${fact('Approved',av.created?av.created.slice(0,4):null)}${fact('State',av.states.join(', '))}${fact('Counties',av.counties.length?fmt(av.counties.length):null,av.counties.slice(0,6).join(', ')+(av.counties.length>6?'…':''))}</div>`
      +(av.within.length?`<p class="ts-caption sub">Inside</p><div class="chips">${av.within.map(n=>`<span class="chip">${esc(n)}</span>`).join('')}</div>`:'')
      +(av.contains.length?`<p class="ts-caption sub">Holds</p><div class="chips">${av.contains.map(n=>`<span class="chip">${esc(n)}</span>`).join('')}</div>`:'')
      +`<p class="ts-caption sub"><a href="${esc(av.cfr_url)}" target="_blank" rel="noopener">Its boundary in the CFR, § ${esc(av.cfr)}</a></p>`;
    X.ava=block('The AVA',b,'US rules name no grapes');
  }
  const gi=f.gi;
  if(gi){
    const b=`<div class="facts">${fact('Type',esc((gi.type||'GI')[0].toUpperCase()+(gi.type||'GI').slice(1)),gi.year?`Registered ${gi.year}`:'')}${gi.vines_ha?fact('Vineyards',`${fmt(gi.vines_ha)} ha`,`in ${fmt(gi.area_km2)} km² in all`):fact('Area',`${fmt(gi.area_km2)} km²`,'')}</div>`
      +(gi.url?`<p class="ts-caption sub"><a href="${esc(gi.url)}" target="_blank" rel="noopener">Its entry at Wine Australia</a></p>`:'');
    X.gi=block('The GI',b,'Australian GIs name no grapes');
  }
  const c=f.climate, rd=f.reading||{};
  if(c){
    const south=c.lat<0, [gi,gp]=seg(GST_F,c.gst), [wi,wp]=seg(WK_F,c.gdd), wk=f.winkler;
    const b=`<div class="facts">${fact('Growing season',`${Math.round(toF(c.gst))}°F`,'average, April to October'.replace('April to October',south?'October to April':'April to October'))}${fact('Heat',`${fmt(Math.round(c.gdd*1.8/10)*10)} degree days`,'°F, above 50°F')}`
      +`${fact('Rain',`${Math.round(inch(c.rain))} in/year`,`${Math.round(inch(c.gs_rain))} in while the vines grow`)}${fact('Climate type',esc(c.koppen_name||c.koppen),c.koppen?'Köppen '+c.koppen:'')}</div>`
      +`<p class="ts-caption sub">Growing season: ${esc((GST_F[gi]||['?'])[0].toLowerCase())}</p>${scale(GST_F.map(x=>[x[0],x[3]]),gi,gp,'Growing season temperature class')}`
      +`<p class="ts-caption sub">Winkler region ${esc(wk?wk[0]:'')}</p>${scale(WK_F.map(x=>[x[0],x[3]]),wi,wp,'Winkler region')}${wk&&wk[1]?`<p class="ts-body wk">${esc(wk[1])}</p>`:''}`
      +bigNote(f)+reading(rd.climate)
      +`<div class="mrow"><div><p class="ts-caption sub">Average temperature by month, °F</p>${months(c.tavg.map(toF),'temperature','t',south)}</div><div><p class="ts-caption sub">Rain by month, inches</p>${months(c.prec.map(inch),'rain','p',south)}</div></div>`;
    X.climate=block('Climate',b);
  }
  const so=f.soil, rk=f.rocks;
  if(so||rk){
    const rb=rk&&rk.families.length?`<p class="ts-caption sub">The rock beneath</p><div class="rocks">${rk.families.map(([i,v])=>`<span class="rk r-${i}" style="flex:${v}"><b class="ts-caption">${esc(rk.names[i]||i)}</b><small class="ts-caption">${Math.round(v*100)}%</small></span>`).join('')}</div>`+para(rd.soil&&rd.soil.rock):'';
    const b=rb+(so?`<p class="ts-caption sub">The soil, 1 to 2 feet down</p><div class="facts">${fact('Texture',so.texture)}${fact('Clay, silt, sand',`${so.clay}, ${so.silt}, ${so.sand}%`)}${fact('pH',so.ph,so.ph_class)}${fact('Stones',so.stones!=null?`${so.stones}%`:null,'of the soil by volume')}</div>`+para(rd.soil&&rd.soil.top):'')+bigNote(f);
    X.soil=block('Rock and soil',b);
  }
  const te=f.terrain;
  if(te){
    const DN={N:'North',NE:'Northeast',E:'East',SE:'Southeast',S:'South',SW:'Southwest',W:'West',NW:'Northwest'};
    const top=te.aspect?Object.entries(te.aspect).sort((a,b)=>b[1]-a[1])[0]:null;
    const rose=te.aspect?`<svg class="rose" viewBox="-50 -50 100 100" role="img" aria-label="Which way the slopes face">${['N','NE','E','SE','S','SW','W','NW'].map((d,k)=>{const r=8+te.aspect[d]/Math.max(...Object.values(te.aspect))*30, a1=(k*45-20)*Math.PI/180, a2=(k*45+20)*Math.PI/180;
        return `<path d="M0 0L${(Math.sin(a1)*r).toFixed(1)} ${(-Math.cos(a1)*r).toFixed(1)}A${r.toFixed(1)} ${r.toFixed(1)} 0 0 1 ${(Math.sin(a2)*r).toFixed(1)} ${(-Math.cos(a2)*r).toFixed(1)}Z"/>`;}).join('')}<text x="0" y="-41" text-anchor="middle">N</text><text x="0" y="48" text-anchor="middle">S</text><text x="45" y="3" text-anchor="middle">E</text><text x="-45" y="3" text-anchor="middle">W</text></svg>`:'';
    const b=`<div class="land"><div class="facts">${fact('Elevation',`${fmt(ft(te.elev[1]))} ft`,`${fmt(ft(te.elev[0]))} to ${fmt(ft(te.elev[2]))} ft`)}${te.aspect?fact('Grade',`${Math.round(Math.tan(te.slope*Math.PI/180)*100)}%`,`${te.slope}° on average`):fact('Slope',`${te.slope}°`,`${Math.round(te.steep*100)}% steeper than 10°, ${Math.round(te.flat*100)}% flat`)}${top?(top[1]<.3?fact('Slopes face','Every way','no main direction'):fact('Slopes face',DN[top[0]],`${Math.round(top[1]*100)}% of sloping ground`)):''}</div>${rose}</div>`+bigNote(f)+reading(rd.land);
    X.land=block('The land',b);
  }
  if(R&&R.claims.length){
    const by={}; for(const x of R.claims) (by[x.topic]||(by[x.topic]=[])).push(x);
    const b=Object.entries(by).map(([t,xs])=>`<p class="ts-caption sub">${esc(t[0].toUpperCase()+t.slice(1))}</p>${xs.map(x=>`<p class="ts-body claim">${esc(x.claim)}${x.strength&&x.strength!=='Strong'?` <span class="str">${esc(x.strength)}</span>`:''}</p>`).join('')}`).join('');
    X.found=`<section class="row"><details class="found"><summary class="head"><h2 class="ts-section_head">What we found</h2><span class="ts-caption">${R.claims.length} notes${R.read?', read '+esc(R.read):''}</span></summary>${b}</details></section>`;
  }
  const pa=f.parts;
  if(pa&&pa.length){
    const rows=pa.slice().sort((a,b)=>b[7]-a[7]||score(b[0])-score(a[0])), many=rows.length>12&&!M.allParts;
    const tr=r=>`<tr><th scope="row"><a href="${link(r[0])}"><i class="sw ${shade(r[0],score(r[0]),M.rng||[0,100])}"></i>${esc(PL[r[0]]?.[0]||r[0])}</a></th><td>${Array.isArray(r[1])?`${Math.round(toF(r[1][0]))} to ${Math.round(toF(r[1][1]))}°F`:r[8]?'<small>varies</small>':r[1]!=null?`${Math.round(toF(r[1]))}°F <small>${esc(r[2]||'')}</small>`:''}</td><td>${r[3]==null?'':Array.isArray(r[3])?`${fmt(ft(r[3][0]))} to ${fmt(ft(r[3][2]))} ft`:fmt(ft(r[3]))+' ft'}</td><td>${r[4]!=null?Math.round(r[4]*100)+'%':''}</td><td>${esc(r[6]||'')}</td></tr>`;
    X.parts=block('How its places compare',`<p class="ts-caption sub">${f.depth===0?'A country is too big for one reading.':'Too big and varied for one reading.'} Here is how the places inside it differ.</p><div class="tablewrap"><table class="parts ts-caption"><thead><tr><th>Place</th><th>Growing season</th><th>Elevation</th><th>Steep</th><th>Main grape</th></tr></thead><tbody>${(many?rows.slice(0,12):rows).map(tr).join('')}</tbody></table></div>`
      +(many?`<button type="button" class="link ts-caption more" id="allparts">Show all ${rows.length}</button>`:''));
  }
  if(!sm&&!ru&&!av&&!c&&!R&&!pl&&!rk) X.none=block('What we have','<p class="ts-body">No shape, rules or research for this place yet.</p>');
  const src=[...f.sources,...(R?R.sources:[])];
  X.sources=block('Sources',knownLine+(src.length?`<ul class="src ts-caption">${src.map(s=>`<li>${s.url?`<a href="${esc(s.url)}" target="_blank" rel="noopener">${esc(s.name)}</a>`:esc(s.name)}</li>`).join('')}</ul>`:''));
  // what the place is, then what grows there, then why it grows there, then the law, then the notes
  const order=['glance','short','planted','climate','soil','land','parts','rules','ava','gi','found','none','sources'];
  const JUMP={planted:'Planted',climate:'Climate',soil:'Rock and soil',land:'Land',parts:'Compare',rules:'Rules',ava:'AVA',gi:'GI',found:'Notes'};
  for(const k of order) if(X[k]) X[k]=X[k].replace('<section class="row"',`<section class="row" id="s-${k}"`);
  const jumps=order.filter(k=>X[k]&&JUMP[k]);
  h=(jumps.length>=3?`<nav class="jump" aria-label="On this page">${jumps.map(k=>`<button type="button" class="step ts-ladder_step" data-jump="s-${k}">${JUMP[k]}</button>`).join('')}</nav>`:'')+order.map(k=>X[k]||'').join('');
  $('#info').innerHTML=h;
  for(const b of document.querySelectorAll('#info [data-jump]')) b.onclick=()=>document.getElementById(b.dataset.jump)?.scrollIntoView({behavior:'smooth',block:'start'});
  const apb=$('#allparts'); if(apb) apb.onclick=()=>{M.allParts=true; renderInfo(f); M.allParts=false;};
}
const WORLD_INFO=()=>`<section class="row"><div class="prose"><p class="ts-body">Every wine country, region and appellation we have, ${fmt(Object.keys(PL).length)} places in all.</p><p class="ts-body">Benchmark regions, in gold, are the ones the WSET Diploma teaches: the classic places to learn first. Emerging regions, in grey, are the rest.</p><p class="ts-body">Darker shades are better known: more Wikipedias write about them, and more people read those pages. Each place is compared with the places beside it, so Bordeaux is set against Burgundy and Languedoc, and France against Uruguay.</p></div></section>`;
async function render(){
  readHash(); renderPlaces(); mapShow();
  if(S.p==='world'){renderTitle('world'); $('#info').innerHTML=WORLD_INFO(); return;}
  renderTitle(S.p,null);
  const id=S.p, f=await facts(id); if(S.p===id) renderInfo(f);
}
// ---------- search
function wireSearch(){
  const q=$('#q'), ul=$('#sugg'); let list=[], sel=-1;
  const all=Object.entries(PL).map(([id,x])=>({id,name:x[0],f:fold([x[0],...(x[5]||[])].join(' ')),s:x[2],k:x[3],c:x[4]}));
  const show=()=>{ul.hidden=!list.length; q.setAttribute('aria-expanded',String(!!list.length));
    ul.innerHTML=list.map((x,i)=>`<li role="option" aria-selected="${i===sel}" data-i="${i}"><span class="sl">${esc(x.name)} <small>${esc([x.k,x.c].filter(Boolean).join(', '))}</small></span></li>`).join('');};
  const choose=x=>{q.value=''; list=[]; show(); q.blur(); go(x.id);};
  q.addEventListener('input',()=>{const t=fold(q.value.trim()); sel=-1;
    list=t.length<2?[]:all.filter(x=>x.f.includes(t)).sort((a,b)=>(b.f.startsWith(t)-a.f.startsWith(t))||b.s-a.s).slice(0,10); show();});
  q.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){sel=Math.min(list.length-1,sel+1); show(); e.preventDefault();} else if(e.key==='ArrowUp'){sel=Math.max(-1,sel-1); show(); e.preventDefault();}
    else if(e.key==='Enter'&&list.length){choose(list[Math.max(0,sel)]); e.preventDefault();} else if(e.key==='Escape'){list=[]; show();}});
  ul.addEventListener('mousedown',e=>{const li=e.target.closest('li'); if(li){e.preventDefault(); choose(list[+li.dataset.i]);}});
  q.addEventListener('blur',()=>setTimeout(()=>{list=[]; show();},150));
}
async function main(){
  [GEO,WORLD,PL]=await Promise.all(['geo/index.json','geo/world.json','places.json'].map(u=>fetch(u).then(r=>r.json())));
  PL=PL.places; SCORED=Object.values(PL).some(x=>x[2]>=0); mapInit(); wireSearch();
  addEventListener('hashchange',()=>{render(); window.scrollTo({top:0,behavior:'smooth'});});
  render();
}
main();
})();
