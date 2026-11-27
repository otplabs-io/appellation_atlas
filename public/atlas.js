/* Appellation Atlas. A globe of every wine place there is.
   Places are shaded by the study list: darkest gold for the essential benchmarks, then the benchmarks, light gold for the
   places inside one, grey for the rest. Tap or pinch into a place to go in; under the map is what is known
   about the place you are in: the rules, the grapes, the climate and the soil, more exact the deeper you go.
   Data: places.json and facts/<id>.json (src/atlas.py facts), geo/world.json, geo/index.json and geo/views/*.json
   (src/atlas.py geo). The place lives in the URL (#/france/burgundy), so the back button and shared links keep it.
   The globe code follows app/app.js; keep the two in step. */
(()=>{
'use strict';
const $=s=>document.querySelector(s), esc=s=>unitText(String(s??'')).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const fold=s=>String(s??'').normalize('NFD').replace(/[̀-ͯ]/g,'').toLowerCase();
const NS='http://www.w3.org/2000/svg';
const BACK='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" style="color:var(--teal)" aria-hidden="true"><path d="m15 5-7 7 7 7"/></svg>';
const CMP_ICON='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 4v16M16 4v16M4 8h4M16 16h4"/></svg>';
let GEO,WORLD,PL,VIEWS={},FACTS={},SCORED=false;   // SCORED: notoriety has been fetched
const START={lon:-33.56,lat:18.13,ex:.83775,ey:.9314};   // where the globe opens, and how much of it to fit
const S={p:'world'};
const fmt=n=>n==null?'':Math.round(n).toLocaleString('en-US');
// ---------- the place in the URL
function readHash(){const h=decodeURIComponent(location.hash.replace(/^#\/?/,''));
  S.view='place'; S.ca=S.cb=null;
  if(h==='pairs'){S.view='pairs'; S.p='world';}
  else if(h==='compare'){S.view='compare'; S.p='world';}
  else if(h.startsWith('compare/')){const [a,b]=h.slice(8).split('/vs/'); S.view='compare'; S.ca=PL[a]?a:null; S.cb=b&&PL[b]?b:null; S.p='world';}
  else S.p=h&&PL[h]?h:'world';
  const cl=document.body.classList; cl.toggle('cmpmode',S.view==='compare'); cl.toggle('pairsmode',S.view==='pairs'); cl.toggle('home',S.view==='place'&&S.p==='world');
  appBanner(); relayout();}
// the map's size follows the page's mode (the globe at home is taller than a place's map on a phone)
function relayout(){if(!M.svg) return; const w=M.box.clientWidth, h=M.box.clientHeight; if(!w||!h||(w===M.W&&h===M.H)) return; mapSize(); if(M.view&&!M.busy){M.cam=camOf(M.cam.lon,M.cam.lat,M.cam.R); draw(); labels();}}
const WIDE=()=>matchMedia('(min-width:1024px)').matches;
// Safari's App Store banner: Open takes the app straight to the place on screen (the app reads atlas://place/<id>)
function appBanner(){const m=document.querySelector('meta[name="apple-itunes-app"]'); if(!m) return;
  const arg=S.view==='compare'&&S.ca&&S.cb?'atlas://compare/'+S.ca+'/vs/'+S.cb:S.view==='pairs'?'atlas://pairs':S.p!=='world'?'atlas://place/'+S.p:'';
  m.content='app-id=6839710428'+(arg?', app-argument='+arg:'');}
const link=id=>id&&id!=='world'?'#/'+id:'#/';
function go(id){if((id||'world')===S.p) return; location.hash=link(id);}
// ---------- notoriety: a place's shade, against the others on the same view
const score=id=>PL[id]?PL[id][2]:-1;
// Shade by where a place sits between the least and best known places on the same view, so one star (Napa) does not wash
// out the rest. The span is at least 20 points, so places that are nearly equal stay nearly the same shade.
// Four fixed shades, the same in every view, all from the study list: the darkest gold for the essential benchmarks, the places the
// Level 2 specification names and the regions above them; dark gold for the other benchmarks, the places only the Level 3 specification
// names and the regions above them; light gold for every place inside a named place, by where it is alone; grey for the rest.
// Every essential is a benchmark too. Grey says only that a place is off the study list, never how well known it is.
const TONES={e:{one:'Essential benchmark',many:'Essential benchmarks',cls:'a4'},b:{one:'Benchmark',many:'Benchmarks',cls:'a3'},i:{one:'Inside a benchmark',many:'Inside a benchmark',cls:'a2'},o:{one:'Other',many:'',cls:'a2 o'}};
const tone=id=>{const x=PL[id]; return !x?'o':x[7]&5?'e':x[7]&10?'b':x[8]?'i':'o';};
const moreIn=vid=>vid==='world'?'Other countries':'More in '+(PL[vid]?.[0]||'');
const shade=id=>TONES[tone(id)].cls;
// "Show on the map": all places, the benchmarks, or the essential benchmarks only; the rest stay plain land (mapShade in the app)
let FILTER=(()=>{try{return localStorage.getItem('atlas-filter')||'all';}catch(e){return 'all';}})();
const mapShade=id=>{const t=tone(id); return FILTER==='bench'&&(t==='i'||t==='o')||FILTER==='essential'&&t!=='e'?'a0':shade(id);};

// ---------- the map: an orthographic globe that flies from the world down to the appellation
const RAD=Math.PI/180, TAU=2*Math.PI;
async function view(id){
  if(!VIEWS[id]){const r=await fetch('geo/views/'+id.replace(/\//g,'__')+'.json'); if(!r.ok) return null; const v=await r.json();
    for(const it of v.items) if(it.p) it.g=prep(it.p); if(v.ctx) for(const c of v.ctx) c.g=prep(c.p); v.og=prep(v.outline);
    if(v.water) for(const w of v.water) w.g=w.k==='l'?prep(w.p.map(r=>[r])):prepLines(w.p);
    VIEWS[id]=v;}
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
function prepLines(L){   // a river's lines, as the polygons are kept: angles ready, and a cap around each to skip the ones out of sight
  return L.map(r=>{const n=r.length/2, lam=new Float64Array(n), cp=new Float64Array(n), sp=new Float64Array(n); let X=0,Y=0,Z=0;
    for(let i=0;i<n;i++){const l=r[2*i]*RAD,p=r[2*i+1]*RAD; lam[i]=l; cp[i]=Math.cos(p); sp[i]=Math.sin(p); X+=cp[i]*Math.cos(l); Y+=cp[i]*Math.sin(l); Z+=sp[i];}
    const Ln=Math.hypot(X,Y,Z)||1; X/=Ln;Y/=Ln;Z/=Ln; let m=1;
    for(let i=0;i<n;i++){const d=cp[i]*Math.cos(lam[i])*X+cp[i]*Math.sin(lam[i])*Y+sp[i]*Z; if(d<m) m=d;}
    return {n,lam,cp,sp,c:[X,Y,Z],rad:Math.acos(Math.max(-1,Math.min(1,m)))};});
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
function clip(rings,reach=Math.PI){   // cut a polygon at the horizon and close it along the globe's edge (outer rings run counterclockwise)
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
      let best=null,bd=9; for(const t of sg) if(!t.used||t===s0){let d=(t.a0-s.a1)%TAU; if(d<0) d+=TAU; if(d>TAU-.1&&reach<1.4) d=0; if(d<bd){bd=d;best=t;}}
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
  let rings=poly.rs.map(r=>projRing(r,cam)); if(dist+poly.rad>Math.PI/2-1e-4) rings=clip(rings,poly.rad);
  const cx=M.W/2,cy=M.H/2,R=cam.R; let d='';
  for(const r of rings) if(r.length>2){d+='M'; for(let i=0;i<r.length;i++) d+=(i?'L':'')+r1(cx+R*r[i][0])+','+r1(cy-R*r[i][1]); d+='Z';}
  return d;
}
function lineD(ls,cam){   // open lines, broken at the horizon, with points under a pixel apart dropped
  const cx=M.W/2,cy=M.H/2,R=cam.R; let d='';
  for(const l of ls){const dot=l.c[0]*cam.v[0]+l.c[1]*cam.v[1]+l.c[2]*cam.v[2]; if(Math.acos(Math.max(-1,Math.min(1,dot)))-l.rad>M.va) continue;
    let on=false,px=0,py=0;
    for(let i=0;i<l.n;i++){const dd=l.lam[i]-cam.l0,cd=Math.cos(dd),cp=l.cp[i],sp=l.sp[i];
      if(cam.s0*sp+cam.c0*cp*cd<0){on=false; continue;}
      const x=cx+R*cp*Math.sin(dd), y=cy-R*(cam.c0*sp-cam.s0*cp*cd);
      if(on&&i<l.n-1&&Math.abs(x-px)+Math.abs(y-py)<1) continue;
      d+=(on?'L':'M')+r1(x)+','+r1(y); px=x; py=y; on=true;}}
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
  const cam=M.cam, hd=WIDE()?Math.hypot(innerWidth,innerHeight):Math.hypot(M.W,M.H)/2; M.va=hd>=cam.R?Math.PI/2:Math.asin(hd/cam.R)+.01;
  M.ocean.setAttribute('r',r1(cam.R)); M.rim.setAttribute('r',r1(cam.R));
  M.grat.setAttribute('d',cam.R<Math.min(M.W,M.H)*2.5?gratD(cam):'');
  for(const f of M.feats) if(f.on()){const d=f.line?lineD(f.g,cam):f.g.map(p=>polyD(p,cam)).join(''); f.el.setAttribute('d',d); if(f.edge) f.edge.setAttribute('d',d);}
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
  if(v.water){const wg=el('g',{class:'water'},g);   // the rivers and lakes the pages name (src/water.py), over the places so they show
    for(const w of v.water.filter(w=>w.k==='l')) addFeat(wg,'lake',w.g);
    const cg=el('g',{},wg);   // every river's pale edge under every river, so crossings stay clean
    for(const w of v.water.filter(w=>w.k!=='l')){const f=addFeat(wg,'river',w.g); f.line=true; f.edge=el('path',{class:'river-case'},cg);}}
  g.view=v; return g;
}
function dropView(g){M.feats=M.feats.filter(f=>!g.contains(f.el)); g.remove();}
const kindOf=id=>PL[id]?.[3]||'';
function restyle(){
  const v=M.view; if(!v) return;   for(const f of M.feats) if(f.it){
    f.el.setAttribute('class',`rg${f.sib?' sib a0':' '+mapShade(f.it.id)}${M.leaf===f.it.id?' sel':''}`);
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
    if(it.dot){const c=el('circle',{cx:r1(s[0]),cy:r1(s[1]),r:6,class:`dot-m ${mapShade(it.id)}${M.leaf===it.id?' sel':''}`,'data-id':it.id},g); el('title',{},c).textContent=it.name; placed.push([s[0]-5,s[1]-5,s[0]+5,s[1]+5]);}}
  for(const it of live){if(!it.s) continue; const t=it.name, w=t.length*fs*.56, h=fs*1.2, [x,y]=it.s;
    const tries=it.dot?[[x+10,y+4,'start'],[x-10,y+4,'end'],[x,y-11,'middle'],[x,y+h+8,'middle']]
      :[[x,y+fs*.35,'middle'],[x,y-8,'middle'],[x,y+h+4,'middle'],[x+12,y+fs*.35,'start'],[x-12,y+fs*.35,'end'],[x+8,y-8,'start'],[x-8,y-8,'end'],[x+8,y+h+4,'start'],[x-8,y+h+4,'end']];
    if(it===live[0]) tries.push([x,y+fs*.35,'middle','force']);
    for(const [X,Y,a,force] of tries){const x0=a==='middle'?X-w/2:a==='end'?X-w:X; if(!force&&!free([x0,Y-h,x0+w,Y+h*.25])) continue;
      const e=el('text',{x:r1(X),y:r1(Y),'font-size':fs,'text-anchor':a,'data-id':it.id},g); e.textContent=t;   // then its measured box, as the estimate runs short on wide names
      const r=e.getBBox(), bx=[r.x-4,r.y,r.x+r.width+4,r.y+r.height]; if(!force&&!free(bx)){e.remove(); continue;}   // 4px apart at least
      placed.push(bx); break;}}
  for(const w of v.water||[]){   // river and lake names, after the places': along the stretch nearest the middle of the map, or across the lake
    const tries=[];
    if(w.k==='l'){const s=scr([w.a[0],w.a[1]]); if(s) tries.push([s,0]);}
    else for(const l of w.g){const P=[];
      for(let i=0;i<l.n;i++){const d=l.lam[i]-cam.l0,cd=Math.cos(d),cp=l.cp[i],sp=l.sp[i]; P.push(cam.s0*sp+cam.c0*cp*cd<0?null:[cx+R*cp*Math.sin(d),cy-R*(cam.c0*sp-cam.s0*cp*cd)]);}
      let last=null;
      for(let i=0;i<P.length;i++){const p=P[i]; if(!p||p[0]<30||p[0]>M.W-30||p[1]<16||p[1]>M.H-16||(last&&Math.hypot(p[0]-last[0],p[1]-last[1])<24)) continue;
        let a=i,b=i; const near=q=>q&&Math.hypot(q[0]-p[0],q[1]-p[1])<22;   // the river's heading over about 40px
        while(a>0&&near(P[a-1])) a--; while(b<P.length-1&&near(P[b+1])) b++;
        if(a===i&&i>0&&P[i-1]) a=i-1; if(b===i&&i<P.length-1&&P[i+1]) b=i+1; if(a===b) continue;
        let ang=Math.atan2(P[b][1]-P[a][1],P[b][0]-P[a][0])*180/Math.PI; if(ang>90) ang-=180; if(ang<-90) ang+=180;
        tries.push([p,ang]); last=p;}}
    tries.sort((x,y)=>Math.hypot(x[0][0]-cx,x[0][1]-cy)-Math.hypot(y[0][0]-cx,y[0][1]-cy));
    const wd=w.n.length*11*.52, h=13;
    for(const [s,ang] of tries.slice(0,60)){const a=ang*Math.PI/180, hw=(Math.abs(Math.cos(a))*wd+Math.abs(Math.sin(a))*h)/2, hh=(Math.abs(Math.sin(a))*wd+Math.abs(Math.cos(a))*h)/2;
      const bx=[s[0]-hw,s[1]-hh,s[0]+hw,s[1]+hh]; if(!free(bx)) continue; placed.push(bx);
      el('text',{x:r1(s[0]),y:r1(s[1]+4),class:'wl','text-anchor':'middle',transform:`rotate(${r1(ang)} ${r1(s[0])} ${r1(s[1])})`},g).textContent=w.n; break;}}
  for(const t of v.cities||[]){   // a few towns, for bearings: a dot and the name beside it, wherever there is room
    const s=scr(t.c); if(!s||s[0]<8||s[0]>M.W-8||s[1]<8||s[1]>M.H-8) continue; const w=t.n.length*11*.55, h=12;
    const spot=[[s[0]+6,s[1]+4,'start'],[s[0]-6,s[1]+4,'end'],[s[0],s[1]-7,'middle'],[s[0],s[1]+15,'middle']].find(([X,Y,a])=>{const x0=a==='middle'?X-w/2:a==='end'?X-w:X; return free([x0-2,Y-h+2,x0+w+2,Y+3])&&free([s[0]-3,s[1]-3,s[0]+3,s[1]+3]);});
    if(!spot) continue; const [X,Y,a]=spot, x0=a==='middle'?X-w/2:a==='end'?X-w:X;
    placed.push([x0-2,Y-h+2,x0+w+2,Y+3],[s[0]-3,s[1]-3,s[0]+3,s[1]+3]);
    el('circle',{cx:r1(s[0]),cy:r1(s[1]),r:2.6,class:'cd'},g); el('text',{x:r1(X),y:r1(Y),class:'ctl','text-anchor':a},g).textContent=t.n;}
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
  // turn and zoom together, on one easing; between two places far apart and both close up, rise toward the whole globe in the middle of the flight
  const rad=Math.PI/180, R0=Math.min(M.W,M.H)/2*.9, lo=Math.min(a.R,b.R),
    ang=Math.acos(Math.min(1,Math.sin(a.lat*rad)*Math.sin(b.lat*rad)+Math.cos(a.lat*rad)*Math.cos(b.lat*rad)*Math.cos(dl*rad)))/rad,
    dip=lo>R0*1.5&&ang>15?Math.log(lo/R0)*Math.min(1,ang/60):0;
  await new Promise(res=>{const t0=performance.now(); const step=t=>{const k=Math.min(1,(t-t0)/ms), e=ease(k), p=e, z=e;
    M.cam=camOf(a.lon+dl*p,a.lat+(b.lat-a.lat)*p,Math.exp(Math.log(a.R)+(Math.log(b.R)-Math.log(a.R))*z-dip*Math.sin(Math.PI*k)));
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
function mapSize(){const w=M.box.clientWidth||360, h=Math.max(200,M.box.clientHeight||320); M.W=w; M.H=h;   // the stylesheet sizes the map: the top of a phone, or the space between the panels (drawn on under them)
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
  const out=document.createElement('button'); out.type='button'; out.className='zout'; out.onclick=zoomOut; out.hidden=true; M.box.appendChild(out); M.out=out;
  M.svg.addEventListener('click',e=>{if(M.dragged||M.busy) return; const t=e.target.closest('[data-id]');
    if(t){if(t.classList.contains('sib')) pick(t.dataset.id); else cycle(stack(t,e)); return;}
    const b=M.svg.getBoundingClientRect(), x=(e.clientX-b.left)*M.W/b.width, y=(e.clientY-b.top)*M.H/b.height;   // a near miss: the closest place within a fingertip
    let best=null,bd=24; for(const it of M.view.items) if(it.s){const d=Math.hypot(it.s[0]-x,it.s[1]-y); if(d<bd){bd=d;best=it;}} if(best) pick(best.id);});
  M.svg.addEventListener('dblclick',e=>{if(!e.target.closest('[data-id]')) zoomOut();});
  const P=new Map(); let g0=null, wt;
  const loc=(x,y)=>{const b=M.svg.getBoundingClientRect(); return [(x-b.left)*M.W/b.width,(y-b.top)*M.H/b.height];};
  const geoAt=(cam,s)=>unpt(cam,(s[0]-M.W/2)/cam.R,(M.H/2-s[1])/cam.R);
  const mid=()=>{const v=[...P.values()], x=v.reduce((t,p)=>t+p[0],0)/v.length, y=v.reduce((t,p)=>t+p[1],0)/v.length;
    return [loc(x,y),v.length>1?Math.hypot(v[0][0]-v[1][0],v[0][1]-v[1][1]):0];};
  const begin=()=>{const [s,d]=mid(); g0={cam:M.cam,s,d,last:s,flat:P.size===1&&M.view.id==='world'&&!zoomed()};};
  M.svg.addEventListener('pointerdown',e=>{if(M.busy) return; P.set(e.pointerId,[e.clientX,e.clientY]); if(P.size===1){M.dragged=false; M.push=null;} begin();});
  M.svg.addEventListener('pointermove',e=>{if(!P.has(e.pointerId)||M.busy||!g0) return; P.set(e.pointerId,[e.clientX,e.clientY]);
    let [s,d]=mid();
    if(P.size===1){if(!M.dragged&&Math.hypot(s[0]-g0.s[0],s[1]-g0.s[1])<6) return; if(g0.flat&&e.pointerType==='touch') s=[s[0],g0.s[1]];}
    if(!M.dragged){M.dragged=true; M.lab.replaceChildren(); try{M.svg.setPointerCapture(e.pointerId);}catch(_){}}
    const R=P.size>1&&g0.d?g0.cam.R*d/g0.d:g0.cam.R; push(R,s); step(g0.last,s,clampR(R)); g0.last=s;});
  const up=e=>{if(!P.delete(e.pointerId)) return; if(P.size) begin(); else {g0=null; if(M.dragged) settle();}};
  M.svg.addEventListener('pointerup',up); M.svg.addEventListener('pointercancel',up);
  M.svg.addEventListener('wheel',e=>{if(!e.ctrlKey) return; e.preventDefault(); if(M.busy) return;
    const s=loc(e.clientX,e.clientY), R=M.cam.R*Math.exp(-Math.max(-50,Math.min(50,e.deltaY))*.01); M.lab.replaceChildren(); push(R,s); look(geoAt(M.cam,s),s,clampR(R),M.cam);
    clearTimeout(wt); wt=setTimeout(settle,250);},{passive:false});
  M.svg.addEventListener('touchmove',e=>{if(e.touches.length>1) e.preventDefault();},{passive:false});
  for(const t of ['gesturestart','gesturechange']) M.svg.addEventListener(t,e=>e.preventDefault());
  addEventListener('resize',()=>{if(!M.view) return; mapSize(); M.cam=camFor(M.view); draw(); labels();});
}
const baseR=()=>camFor(M.view).R, zoomed=()=>M.cam.R>baseR()*1.03;
function clampR(R){const b=baseR(), w=M.view.id==='world'; return Math.min(b*(w?14:8),Math.max(b*(w?.8:.5),R));}
// The world globe only has rough country outlines, so it stops at 14 times. Pinching on past that marks the spot, and
// letting go there opens the country under the fingers. Backing off below the limit forgets it.
function push(R,s){if(M.view.id!=='world') return; const c=baseR()*14; if(R>c*1.1) M.push=s; else if(R<c) M.push=null;}
function countryAt(s){const b=M.svg.getBoundingClientRect();
  const t=document.elementsFromPoint(b.left+s[0]*b.width/M.W,b.top+s[1]*b.height/M.H).find(x=>x.matches('path.rg[data-id]:not(.sib)'));
  return t?.dataset.id;}
// The camera that puts a place at a screen point at size R. The quick guess is exact only at the middle of the screen, so a
// few corrections follow: without them a pinch over the whole globe slides it tens of points each frame.
function aim(g,s,R){
  let c=unpt(camOf(g[0],g[1],R),(M.W/2-s[0])/R,(s[1]-M.H/2)/R); if(!c) return null; const k=1/RAD/R; let best=c,be=Infinity;
  for(let i=0;i<20;i++){const q=pt(camOf(c[0],c[1],R),g[0],g[1]); if(q[2]<0) break;
    const ex=s[0]-(M.W/2+R*q[0]), ey=s[1]-(M.H/2-R*q[1]), e=Math.abs(ex)+Math.abs(ey); if(e<be){be=e; best=c;} if(e<.1) break;
    c=[c[0]-ex*k/Math.max(.25,Math.cos(c[1]*RAD)),Math.max(-89,Math.min(89,c[1]+ey*k))];}
  return best;
}
function look(geo,s,R,cam0){
  let c=geo&&aim(geo,s,R); if(!c) c=[cam0.lon,cam0.lat];
  M.cam=camOf(c[0],Math.max(-80,Math.min(80,c[1])),R); if(M.view.id!=='world') setWorld(needWorld(M.cam,M.view)?1:0); draw();
}
// Moves the globe as the finger goes from one point to the next. A drag turns it at a steady rate, the same over land, sea
// or open space, so it never jumps. A pinch keeps the spot under the fingers where it is, when it can.
function step(p,s,R){
  const a=M.cam, k=1/RAD/R; let lon=a.lon-(s[0]-p[0])*k/Math.max(.25,Math.cos(a.lat*RAD)), lat=a.lat+(s[1]-p[1])*k;
  const g=R!==a.R&&unpt(a,(p[0]-M.W/2)/a.R,(M.H/2-p[1])/a.R), c=g&&aim(g,s,R);
  if(c){lon=c[0]; lat=c[1];}
  M.cam=camOf(((lon+180)%360+360)%360-180,Math.max(-80,Math.min(80,lat)),R); if(M.view.id!=='world') setWorld(needWorld(M.cam,M.view)?1:0); draw();
}
function touchMode(){M.svg.style.touchAction=M.view.id==='world'&&!zoomed()?'pan-y':'none';}
async function settle(){
  if(M.busy||!M.view) return; const v=M.view, b=camFor(v);
  if(v.id!=='world'&&M.cam.R<b.R*.75){zoomOut(); return;}
  if(v.id==='world'&&M.push){const id=countryAt(M.push); M.push=null; if(id){go(id); return;}}
  labels(); touchMode();   // the globe stays where the finger left it, at every level: a place opens only when tapped
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
    M.out.innerHTML=BACK+esc(M.leaf?v.name:v.parent==='world'?'The world':PL[v.parent]?.[0]||'Back');
    touchMode();
  } finally {M.going=false;}
}
// Every place under a tap, the one it lands on first, then the rest from smallest to largest. A label goes first unless it
// sits on a smaller place, as Prosecco DOC's name sits on Conegliano Valdobbiadene. Places are drawn largest first.
function stack(t,e){
  const ix=k=>M.view.items.findIndex(i=>i.id===k), id=t.dataset.id;
  const under=document.elementsFromPoint(e.clientX,e.clientY).filter(x=>x.matches('path.rg[data-id]:not(.sib)')).map(x=>x.dataset.id);
  if(!t.closest('.lab')||(under.length&&ix(id)>=0&&ix(under[0])>ix(id))) return under.length?under:[id];
  return [id,...under.filter(k=>k!==id)];
}
// Each tap on the same spot moves to the next place there, so places that share a shape, such as Valpolicella and
// Amarone della Valpolicella, can all be reached. After the last, back out to the map's own place.
function cycle(ids){
  if(M.busy) return;
  const i=ids.indexOf(S.p); go(i<0?ids[0]:ids[i+1]??M.view.id);
}
function pick(id){
  if(M.busy) return;
  if(S.p===id){go(M.view.id); return;}   // tap the chosen place again to step back out
  go(id);
}
// ---------- under the map: the places here, and what is known about the place you are in
function renderPlaces(){   // the trail above the name, and the places inside, for their own section (renderInfo)
  const vid=viewFor(S.p), here=Object.keys(GEO.places).filter(i=>GEO.places[i].parent===vid);
  const sorted=here.sort((a,b)=>score(b)-score(a)||PL[a][0].localeCompare(PL[b][0]));
  const chain=[]; let id=vid; while(id&&id!=='world'){chain.unshift(id); id=GEO.places[id]?.parent;}
  const leaf=S.p!==vid?S.p:null;
  const crumbs=[['world','The world'],...chain.map(i=>[i,PL[i][0]]),...(leaf?[[leaf,PL[leaf][0]]]:[])];
  $('#crumbs').innerHTML=crumbs.map(([i,n],k)=>k===crumbs.length-1?`<b>${esc(n)}</b>`:`<a href="${link(i)}">${esc(n)}</a>`).join(' › ');
  if(M.allFor!==vid){M.all=false; M.allFor=vid;}
  const ess=sorted.filter(i=>tone(i)==='e'), bench=sorted.filter(i=>tone(i)==='b'), inner=sorted.filter(i=>tone(i)==='i'), emerg=sorted.filter(i=>tone(i)==='o'), gold=ess.length+bench.length+inner.length, cap=gold?12:30, shown=M.all?emerg:emerg.slice(0,cap);
  const step=i=>`<a class="step" href="${link(i)}" aria-pressed="${S.p===i}"><i class="sw ${shade(i)}"></i>${esc(PL[i][0])}${GEO.places[i].source?'':'<small> no map</small>'}</a>`;
  const grp=(head,list,n)=>list.length?`<p class="grp">${head} ${n}</p><div class="steps">${list.map(step).join('')}</div>`:'';
  const body=grp(TONES.e.many,ess,ess.length)+grp(ess.length?'Other benchmarks':TONES.b.many,bench,bench.length)+grp(TONES.i.many,inner,inner.length)+(gold?grp(esc(moreIn(vid)),shown,emerg.length):shown.length?`<div class="steps">${shown.map(step).join('')}</div>`:'')
    +(emerg.length>shown.length?`<button type="button" class="link ts-caption more" id="allp">Show all ${emerg.length}</button>`:'');
  const pn=esc(PL[vid]?.[0]||'');
  M.places=!sorted.length?null:{head:leaf&&leaf!=='world'?`Other places in ${pn}`:vid==='world'?'Countries':`Places in ${pn}`,body,n:sorted.length,leaf:!!leaf,parent:pn};
}
async function facts(id){
  if(!FACTS[id]){const r=await fetch('facts/'+id.replace(/\//g,'__')+'.json'); FACTS[id]=r.ok?await r.json():null;}
  return FACTS[id];
}
const SKINS=[['red','Red grapes'],['white','White grapes'],['pink','Pink and grey grapes']];
const fact=(label,value,note)=>value==null||value===''?'':`<div class="fact"><span class="ts-fact_label">${label}</span><span class="ts-fact_value">${value}</span>${note?`<span class="ts-fact_note">${note}</span>`:''}</div>`;
const chips=list=>`<div class="chips">${list.map(([g,sk,n])=>`<span class="chip ${sk||''}">${esc(g)}${n!=null?`<b>${n}</b>`:''}</span>`).join('')}</div>`;
const block=(head,body,note)=>body?`<section class="row"><div class="head"><h2 class="ts-section_head">${head}</h2>${note?`<span class="ts-caption">${note}</span>`:''}</div>${body}</section>`:'';
const toF=c=>c*9/5+32, ft=m=>Math.round(m*3.281/10)*10;
// Units, one choice per kind: 'us' or 'm'. Saved on this device. At first they follow the browser's region (Units in the app).
const UNIT_KINDS=['temp','heat','rain','elev','dist','area'];
const unitDefault=()=>{const l=navigator.language||'en-US', r=(l.split('-')[1]||'').toUpperCase(); return r?(['US','LR','MM'].includes(r)?'us':'m'):(l.startsWith('en')?'us':'m');};
const UNITS=(()=>{let s={}; try{s=JSON.parse(localStorage.getItem('atlas-units')||'{}')||{};}catch(e){} const d=unitDefault(); return Object.fromEntries(UNIT_KINDS.map(k=>[k,s[k]==='us'||s[k]==='m'?s[k]:d]));})();
const usU=k=>UNITS[k]==='us';
// figures inside place text arrive marked with both wordings, ⟦kind|US|metric⟧ (src/units.py); this keeps one (Units.text in the app)
function unitText(t){return t.indexOf('\u27e6')<0?t:t.replace(/\u27e6(\w+)\|([^|\u27e7]*)\|([^\u27e7]*)\u27e7/g,(_,k,a,b)=>usU(k)?a:b);}
const tN=c=>Math.round(usU('temp')?toF(c):c), tU=()=>usU('temp')?'°F':'°C';
const deg=c=>`${tN(c)}${tU()}`, degRange=(a,b)=>tN(a)===tN(b)?deg(a):`${tN(a)} to ${tN(b)}${tU()}`;
const heat=g=>`${fmt(Math.round((usU('heat')?g*1.8:g)/10)*10)} degree days`, heatNote=()=>usU('heat')?'°F, above 50°F':'°C, above 10°C';
const elN=m=>usU('elev')?fmt(ft(m)):fmt(Math.round(m/5)*5), elU=()=>usU('elev')?'ft':'m';
const elev=m=>`${elN(m)} ${elU()}`, elevRange=(a,b)=>`${elN(a)} to ${elN(b)} ${elU()}`;
const soilDepth=()=>usU('elev')?'1 to 2 feet':'30 to 60 cm';
const area=ha=>usU('area')?`${fmt(ha*2.471)} acres`:`${fmt(ha)} hectares`, areaShort=ha=>usU('area')?`${fmt(ha*2.471)} acres`:`${fmt(ha)} ha`;
const land=km2=>usU('area')?`${fmt(km2*0.3861)} square miles`:`${fmt(km2)} km²`;
// the grapes left out of what is planted because they are not wine grapes (Copy.leftOut in the app)
const andList=xs=>xs.length>1?xs.slice(0,-1).join(', ')+' and '+xs[xs.length-1]:(xs[0]||'');
// notes on the rules facts (Copy.rules in the app)
const COPY={baseYield:'the yield its rules set; some years a little more is allowed',yieldCeiling:'the most its rules allow in any year; the usual limit is lower',
  yieldLimit:'the most the 2022 EU record allows; some of its wines may have lower limits, and rules change',recognised:'the year its rules say it was first recognised, sometimes under an older name',noShares:'The 2022 EU record lists the grapes allowed, not their shares. Later changes to the rules may not be in it.',noRoles:'The cahier gives these grapes different roles in different wines, so they are listed here by colour.',anyName:' That is every vineyard there, whatever name its wine is sold under.',limitsHead:'Planting rules: shares of each grower\u2019s vineyard, not of the blend',blendHead:'Blend rules: shares of the wine itself',
  forWine:w=>`Main grapes, for ${w}`,whitesOlder:y=>`red grapes as of ${y}, white grapes from an earlier survey, so the shares are approximate.`};
const rockShare=v=>v>=.5?'mostly':v>=.25?'much':'some';   // a rock family's share in words: it comes from a few map points (Copy.share in the app)
const leftOut=l=>l?(l.juice?` Juice grapes are left out: ${esc(andList(l.juice))}.`:'')+(l.table?` Table grapes are left out: ${esc(andList(l.table))}.`:''):'';
const reading=(xs,head)=>xs&&xs.length?`<div class="why"><p class="why-head ts-fact_label">${head}</p><dl>${xs.map(([k,v])=>`<dt class="ts-fact_label">${esc(k)}</dt><dd class="ts-body">${esc(v)}</dd>`).join('')}</dl></div>`:'';
const para=t=>t?`<p class="ts-body soil-text">${esc(t)}</p>`:'';
const bigNote=f=>f.large?`<p class="ts-caption big-note">${f.parts?'Too big and varied for one reading. These figures average all of it; the table further down compares the places inside.':'Too big and varied for one reading. These figures average all of it, hills and valleys alike.'}</p>`:'';
function scale(segs,i,pos,label){   // a row of categories, the place's one lit and marked
  const w=100/segs.length;
  return `<div class="scale" role="img" aria-label="${esc(label)}">${segs.map(([n,r],k)=>`<div class="seg${k===i?' on':''}" style="width:${w}%"><span class="n">${esc(n)}</span><span class="r">${esc(r)}</span></div>`).join('')}`
    +(i>=0?`<i class="mark" style="left:${(i+Math.max(.04,Math.min(.96,pos)))*w}%"></i>`:'')+`</div>`;
}
const GST_F=[['Too cool',-99,13,'under 55°F','under 13°C'],['Cool',13,15,'55 to 59°F','13 to 15°C'],['Intermediate',15,17,'59 to 63°F','15 to 17°C'],['Warm',17,19,'63 to 66°F','17 to 19°C'],['Hot',19,24,'66 to 75°F','19 to 24°C'],['Too hot',24,99,'over 75°F','over 24°C']];
const WK_F=[['Below Ia',0,850,'under 1,500','under 850'],['Ia',850,1111,'1,500 to 2,000','850 to 1,110'],['Ib',1111,1389,'2,000 to 2,500','1,110 to 1,390'],['II',1389,1667,'2,500 to 3,000','1,390 to 1,670'],['III',1667,1944,'3,000 to 3,500','1,670 to 1,940'],['IV',1944,2222,'3,500 to 4,000','1,940 to 2,220'],['V',2222,2700,'4,000 to 4,900','2,220 to 2,700'],['Above V',2700,9999,'over 4,900','over 2,700']];
function seg(t,v){const i=t.findIndex(([,lo,hi])=>lo<=v&&v<hi); if(i<0) return [-1,0]; const [,lo,hi]=t[i], a=lo<-50?hi-2:lo, b=hi>5000?lo+400:hi>90&&hi<1000?lo+2:hi; return [i,(v-a)/(b-a)];}
function months(vals,unit,cls,south,labels,shown){   // twelve bars, the growing season marked, with each bar's value on top when labels is set
  if(!vals) return ''; const top=labels?11:0, max=Math.max(...vals.map(Math.abs),1), w=22, h=56+top, gs=south?[9,10,11,0,1,2,3]:[3,4,5,6,7,8,9];
  const bars=vals.map((v,i)=>{const bh=Math.max(1,Math.abs(v)/max*(h-14-top)); return `<rect x="${i*w+3}" y="${h-bh-12}" width="${w-6}" height="${bh}" class="${cls}${gs.includes(i)?' gs':''}"/>${labels?`<text class="val" x="${i*w+w/2}" y="${h-bh-15}" text-anchor="middle">${Math.round(shown?shown[i]:v)}</text>`:''}<text x="${i*w+w/2}" y="${h-1}" text-anchor="middle">${'JFMAMJJASOND'[i]}</text>`;}).join('');
  return `<svg class="months" viewBox="0 0 ${12*w} ${h}" role="img" aria-label="Monthly ${unit}">${bars}</svg>`;
}
const SHAPE_NOTE={'Eurostat NUTS, the area it is named for':'The map draws the department, province or region it is named for. The PGI\u2019s own area can differ a little.',
  'Eurostat LAU, the commune it is named for':'The map draws the commune it is named for.',
  'Eurostat LAU, the municipalities its rules name':'The map draws the municipalities its rules name.',
  'Chile Decreto 464, drawn from its comunas and provinces':'The boundary follows the comunas and provinces that Chile\u2019s Decreto 464 names.',
  'geoBoundaries, the department it is named for':'The map draws the department it is named for. The IG\u2019s own area can be smaller.',
  'geoBoundaries, the province it is named for':'The map draws the province.',
  'IPONZ GI register':'The boundary is the one on New Zealand\u2019s GI register.','Wine Australia GI boundaries':'The boundary is Wine Australia\u2019s. The legal one is the written description in the register.',
  'union of its children':'There is no single boundary for it, so the map joins the places inside it.'};
function renderTitle(id,f){   // what the place is and which group it is in, its name and what it is known for (PlaceSheet in the app)
  const cap=x=>x?x[0].toUpperCase()+x.slice(1):x;
  if(id==='world'){$('#ptitle').innerHTML=''; $('#shapeNote').hidden=true; return;}
  const kind=f?(f.kind.length?f.kind.map(cap).join(' and '):(f.depth===0?'Country':f.shape==='Eurostat LAU, the commune it is named for'?'Commune':'Region')):'';
  $('#ptitle').innerHTML=`<p class="eyebrow">${esc(kind)}${tone(id)!=='o'?`${kind?' · ':''}<span class="badge ${tone(id)}">${TONES[tone(id)].one}</span>`:''}</p><h2 class="name" style="--n:${Math.max(...String(PL[id]?.[0]||id).split(/\s+/).map(w=>w.length))}">${esc(PL[id]?.[0]||id)}</h2>`
    +(f&&f.also.length?`<p class="also">Also ${f.also.map(esc).join(', ')}</p>`:'')
    +(f&&f.blurb?`<p class="blurb">${esc(f.blurb.text)}</p>`:'');
  const sn=f&&SHAPE_NOTE[f.shape]; M.shapeNote=sn||'';
}
// the place's figures as cards: what is planted most, its growing season and its heat (GlanceStrip in the app).
// A phone swipes through them in a row; a wide screen sets them in a grid.
function glanceStrip(f){
  const c=f.climate, l=lead(f), cards=[];
  const bar=(g,p)=>`<span class="glr"><span>${esc(g)}</span><i><b style="width:${p}%"></b></i><span>${p}%</span></span>`;
  if(l){const pl=f.planted, gr=pl.grapes.filter(([g])=>g!=='Other').slice(0,4);
    cards.push(`<div class="gl gl-wide"><span class="gk">Planted, ${l.y}${l.about?' (approximate)':''}</span>${gr.map(([g,ha])=>bar(g,Math.round(ha/pl.ha*100))).join('')}</div>`);}
  else if(f.planted_wider){const w=f.planted_wider;   // no figures of its own: the nearest wider area's, named as such (wider_planted in src/atlas.py)
    cards.push(`<div class="gl gl-wide"><span class="gk">Planted in ${esc(w.name)}, ${w.year}${w.about?' (approximate)':''}</span>${w.grapes.map(([g,p])=>bar(g,p)).join('')}</div>`);}
  if(c&&c.gst!=null){const [gi]=seg(GST_F,c.gst);
    cards.push(`<div class="gl"><span class="gk">Growing season</span><span class="gv">${deg(c.gst)}</span><span class="gn">${gi>=0?esc(GST_F[gi][0])+', ':''}${c.lat<0?'October to April':'April to October'}</span><span class="gseg" aria-hidden="true">${GST_F.map((x,k)=>`<i${k===gi?' class="on"':''}></i>`).join('')}</span></div>`);}
  if(c&&c.gdd!=null) cards.push(`<div class="gl"><span class="gk">Heat</span><span class="gv">${heat(c.gdd).replace(' degree days','')}</span><span class="gn">degree days${f.winkler&&f.winkler[0]?', Winkler '+esc(f.winkler[0]):''}</span></div>`);
  return cards;
}
function renderInfo(f){
  if(!f){$('#info').innerHTML=''; return;}
  renderTitle(f.id,f);
  const kn=f.known, X={}; let h='';
  const knownLine=(SCORED?`<p class="ts-caption known">${!kn?'No Wikipedia article of its own.'
      :`${kn.articles
        ?`Scored from ${fmt(kn.articles)} Wikipedia article${kn.articles===1?'':'s'} on it and its places, ${fmt(kn.total)} page views in the last ${kn.days} days in all${kn.best?`. Best known: ${esc(PL[kn.best]?.[0]||kn.best)}`:''}.${kn.langs==null?' No article of its own.':''}`
        :`Known: in ${kn.langs} Wikipedia${kn.langs===1?'':'s'}, ${fmt(kn.views)} page views in the last ${kn.days} days.`}${kn.url?` <a href="${esc(kn.url)}" target="_blank" rel="noopener">Read about it on Wikipedia</a>`:''}`}</p>`:'');
  const sm=f.summary, cards=glanceStrip(f), P=M.places;
  // under the name: the cards, then the places inside and Compare (the sheet's first screen on a phone)
  const placesBtn=P?`<button type="button" class="btn ghost" data-jump="s-places">${sm&&!P.leaf?`${fmt(sm.places)} places inside`:P.leaf?`More in ${P.parent}`:`${P.n} places inside`}</button>`:'';
  const lead=`<div class="lead">${cards.length?`<div class="lead-h"><b>At a glance</b>${cards.length>1?'<span>Swipe for more</span>':''}</div><div class="glance">${cards.join('')}</div>`:''}`
    +`<div class="acts">${placesBtn}<a class="btn teal" href="${cmpLink(f.id)}">${CMP_ICON}Compare</a></div></div>`;
  if(P){const k=sm?sm.kinds.map(([k,n])=>`${n} ${k}${n===1?'':'s'}`).join(', '):'';
    X.places=block(P.head,`<div class="pgrp">${sm&&!P.leaf?`<p class="sub-n">${fmt(sm.places)} places in all${k?': '+esc(k):''}.</p>`:''}${P.body}</div>`);}
  if(sm&&sm.grapes.length&&!f.planted) X.allowed=block('Grapes most often allowed',`<p class="ts-caption sub">In how many of its ${sm.with_rules} appellation${sm.with_rules===1?'':'s'} with rules:</p>${chips(sm.grapes)}`);
  const R=f.research;
  if(f.keyfacts&&f.keyfacts.length) X.keyfacts=block('Key facts',`<ul class="keyfacts">${f.keyfacts.map(t=>`<li class="ts-body">${esc(t)}</li>`).join('')}</ul>`);   // from the full article (src/keyfacts.py)
  if(f.style&&f.style.notes.length) X.style=block('Wine style',`${f.style.of?`<p class="ts-caption sub">Written for ${esc(f.style.of)} as a whole.</p>`:''}<ul class="keyfacts">${f.style.notes.map(t=>`<li class="ts-body">${esc(t)}</li>`).join('')}</ul>`);   // what the wines taste like (src/style.py)
  if(f.terms&&f.terms.length) X.terms=block('On the label',`<dl class="terms">${f.terms.map(([t,d])=>`<div><dt class="ts-fact_label">${esc(t)}</dt><dd class="ts-body">${esc(d)}</dd></div>`).join('')}</dl>`);   // the label terms its region uses (src/terms.py)
  if(R&&R.sheet){X.short=block('In short',`<div class="prose">${Object.values(R.sheet).filter(Boolean).map(t=>`<p class="ts-body">${esc(t)}</p>`).join('')}</div>`,'From our research');}
  const pl=f.planted;
  if(pl&&pl.grapes.length){
    const wide=pl.scope==='around'||pl.scope==='parent';   // no figures for the place itself, only for the district around it
    const where=pl.scope==='country'?'':pl.scope==='own'?`in ${pl.names.join(' and ')}`:pl.scope==='within'?`across ${pl.names.slice(0,4).join(', ')}${pl.names.length>4?` and ${pl.names.length-4} more`:''}`
      :`${pl.names.slice(0,3).join(', ')}${pl.names.length>3?` and ${pl.names.length-3} more`:''}`;
    const top=pl.grapes[0][1]||1;
    const other=pl.grapes.find(([g])=>g==='Other'), rows=pl.grapes.filter(([g,ha])=>g!=='Other'&&ha/pl.ha>=.01).map(([g,ha,c],k)=>`<div class="gr ${pl.legal?pl.legal[pl.grapes.findIndex(x=>x[0]===g)]||'':''}"><span class="g ts-body"><i class="dot ${c==='W'?'w':c==='R'?'r':'o'}"></i>${esc(g)}</span><span class="bar"><i style="width:${Math.min(100,Math.max(1,ha/top*100))}%"></i></span><span class="pc ts-caption">${Math.round(ha/pl.ha*100)||'<1'}%</span>${pl.legal&&pl.legal[pl.grapes.findIndex(x=>x[0]===g)]==='minor'?'<span class="tag ts-caption">minor role</span>':''}</div>`).join('');
    const amt=pl.whites_older?COPY.whitesOlder(pl.year):`${area(pl.ha)} of wine grapes, ${pl.year}.`;
    const cap=wide?`No figures exist for ${esc(f.name)} alone. These are for ${esc(where)}, the wider area it sits in: ${amt}`+leftOut(pl.left):(pl.whites_older?`Wine grapes${where?' '+esc(where):''}: `+amt:`${area(pl.ha)} of wine grapes${where?' '+esc(where):''}, ${pl.year}.`)+(pl.any_name?COPY.anyName:'')+leftOut(pl.left);
    const key=wide?[`Allowed in ${esc(f.name)}`,`Not allowed in ${esc(f.name)}`]:[`Can carry the ${esc(f.name)} name`,'Grown here, but sold under another name'];
    X.planted=block(wide?'Planted in the wider area':'What is planted',`<p class="ts-caption sub">${cap}</p>${pl.legal?`<p class="ts-caption sub legal-key"><span><i class="lk main"></i>${key[0]}</span><span><i class="lk no"></i>${key[1]}</span></p>`:''}<div class="planted">${rows}</div>${other?`<p class="ts-caption sub">Other grapes: ${Math.round(other[1]/pl.ha*100)}%</p>`:''}`,'Share of vineyard area');
  }
  const ru=f.rules;
  if(ru){
    ru.grapes=ru.grapes||[]; ru.grapes_other=ru.grapes_other||[]; ru.types=ru.types||[]; ru.communes=ru.communes||[];   // a record may leave a list out (Austria's DACs)
    let b='';
    if(ru.province_list) b+=`<p class="ts-caption sub">The EU record lists every grape approved in the province or region, not this wine\u2019s own blend rules.</p><details class="more-d"><summary class="ts-caption">All ${ru.grapes.length} grapes</summary>${chips(ru.grapes)}</details>`;
    else if(ru.long_list) b+=`<details class="more-d"><summary class="ts-caption">The 2022 EU record allows ${ru.grapes.length} grapes</summary>${chips(ru.grapes)}</details>`;
    else if(ru.by_wine&&ru.by_wine.length){   // the cahier gives each wine its own roles (Malepère: Merlot leads the red, Cabernet Franc the rosé)
      for(const [w,main,other] of ru.by_wine){
        b+=`<p class="ts-caption sub">${esc(COPY.forWine(w))}</p>${chips(main)}`;
        if(other.length) b+=`<p class="ts-caption">Also allowed, in smaller roles</p>${chips(other)}`;
      }
    }
    else{
      for(const [sk,head] of SKINS){const g=ru.grapes.filter(x=>x[1]===sk); if(g.length) b+=`<p class="ts-caption sub">${head}</p>${chips(g)}`;}
      const un=ru.grapes.filter(x=>!x[1]); if(un.length) b+=`<p class="ts-caption sub">Grapes</p>${chips(un)}`;
      if((!ru.cahier||ru.roles_unread)&&ru.grapes.length>1) b+=`<p class="ts-caption">${esc(ru.cahier?COPY.noRoles:COPY.noShares)}</p>`;
    }
    if(ru.grapes_other.length&&!(ru.by_wine&&ru.by_wine.length)) b+=`<p class="ts-caption sub">Also allowed, in smaller roles</p>${chips(ru.grapes_other)}`;
    if(ru.grapes_trial&&ru.grapes_trial.length) b+=`<p class="ts-caption sub">On trial, to adapt to a changing climate</p>${chips(ru.grapes_trial)}`;
    if(ru.limits&&ru.limits.length) b+=`<p class="ts-caption sub">${esc(COPY.limitsHead)}</p><ul class="limits">${ru.limits.map(l=>`<li class="ts-body">${esc(l)}</li>`).join('')}</ul>`;
    if(ru.blend&&ru.blend.length) b+=`<p class="ts-caption sub">${esc(COPY.blendHead)}</p><ul class="limits">${ru.blend.map(l=>`<li class="ts-body">${esc(l)}</li>`).join('')}</ul>`;
    b+=`<div class="facts">${fact('Wine types',ru.types.join(', '))}${ru.yield_base?fact('Base yield',esc(ru.yield_base),COPY.baseYield):fact(ru.yield_ceiling?'Yield ceiling':'Yield limit',ru.yield_hl?`${fmt(ru.yield_hl)} hl/ha`:ru.yield_kg?`${fmt(ru.yield_kg)} kg/ha`:null,ru.yield_ceiling?COPY.yieldCeiling:COPY.yieldLimit)}${fact('Recognised',ru.recognised?String(ru.recognised):null,COPY.recognised)}`
      +`${fact('Fewest vines',ru.density?`${fmt(ru.density)} per ha`:null)}${fact('Irrigation',ru.irrigation)}${fact('Communes',ru.communes.length?fmt(ru.communes.length):null,'in the 2022 EU record')}</div>`;
    if(ru.communes.length) b+=`<details class="more-d"><summary class="ts-caption">The communes</summary><p class="ts-caption">${ru.communes.map(esc).join(', ')}</p></details>`;
    X.rules=block('Grape and vineyard rules',b,'Allowed grapes, not plantings');
  }
  const av=f.ava;
  if(av){
    const b=`<div class="facts">${fact('In effect from',av.created?av.created.slice(0,4):null)}${fact('State',av.states.join(', '))}${fact('Counties',av.counties.length?fmt(av.counties.length):null,av.counties.slice(0,6).join(', ')+(av.counties.length>6?'…':''))}</div>`
      +(av.within.length?`<p class="ts-caption sub">Inside</p><div class="chips">${av.within.map(n=>`<span class="chip">${esc(n)}</span>`).join('')}</div>`:'')
      +(av.overlaps&&av.overlaps.length?`<p class="ts-caption sub">Partly inside</p><div class="chips">${av.overlaps.map(n=>`<span class="chip">${esc(n)}</span>`).join('')}</div>`:'')
      +(av.contains.length?`<p class="ts-caption sub">Holds</p><div class="chips">${av.contains.map(n=>`<span class="chip">${esc(n)}</span>`).join('')}</div>`:'')
      +`<p class="ts-caption sub"><a href="${esc(av.cfr_url)}" target="_blank" rel="noopener">Its boundary in the CFR, § ${esc(av.cfr)}</a></p>`;
    X.ava=block('The AVA',b,'US rules name no grapes');
  }
  const gi=f.gi;
  if(gi){
    const b=`<div class="facts">${fact('Type',esc((gi.type||'GI')[0].toUpperCase()+(gi.type||'GI').slice(1)),gi.year?`Registered ${gi.year}`:'')}${gi.vines_ha?fact('Vineyards',areaShort(gi.vines_ha),`in ${land(gi.area_km2)} in all`):fact('Area',land(gi.area_km2),'')}</div>`
      +(gi.url?`<p class="ts-caption sub"><a href="${esc(gi.url)}" target="_blank" rel="noopener">Its entry at Wine Australia</a></p>`:'');
    X.gi=block('The GI',b,'Australian GIs name no grapes');
  }
  const c=f.climate, rd=f.reading||{};
  if(c){
    const south=c.lat<0, [gi,gp]=seg(GST_F,c.gst), [wi,wp]=seg(WK_F,c.gdd), wk=f.winkler;
    const b=`<div class="facts">${fact('Growing season',deg(c.gst),'average, April to October'.replace('April to October',south?'October to April':'April to October'))}${fact('Heat',heat(c.gdd),heatNote())}`
      +`${fact('Climate type',esc(c.koppen_name||c.koppen),c.koppen?'Köppen '+c.koppen+', from a 1991 to 2020 map':'')}</div>`
      +`<p class="ts-caption sub">Growing season: ${esc((GST_F[gi]||['?'])[0].toLowerCase())}</p>${scale(GST_F.map(x=>[x[0],x[usU('temp')?3:4]]),gi,gp,'Growing season temperature class')}`
      +`<p class="ts-caption sub">Winkler region ${esc(wk?wk[0]:'')}</p>${scale(WK_F.map(x=>[x[0],x[usU('heat')?3:4]]),wi,wp,'Winkler region')}${wk&&wk[1]?`<p class="ts-body wk">${esc(wk[1])}</p>`:''}`
      +bigNote(f)+reading(rd.climate,'What the climate means for the vines')
      +`<div class="mrow"><div><p class="ts-caption sub">Average temperature by month, ${tU()}</p>${months(c.tavg.map(toF),'temperature','t',south,true,c.tavg.map(tN))}</div></div>`;
    X.climate=block('Climate',b,'Averages, 1970 to 2000');
  }
  const so=f.soil, rk=f.rocks;
  if(so||rk){
    const rb=rk&&rk.families.length?`<p class="ts-caption sub">The rock beneath, from a geologic map: the main rock units, not each vineyard's soil</p><div class="rocks">${rk.families.map(([i,v])=>`<span class="rk r-${i}" style="flex:${v}"><b class="ts-caption">${esc(rk.names[i]||i)}</b><small class="ts-caption">${rockShare(v)}</small></span>`).join('')}</div>`+para(rd.soil&&rd.soil.rock):'';
    const b=rb+(so?`<p class="ts-caption sub">The soil, ${soilDepth()} down</p><div class="facts">${fact('Texture',so.texture)}${fact('Clay, silt, sand',`${so.clay}, ${so.silt}, ${so.sand}%`)}${fact('pH',so.ph,so.ph_class)}${fact('Stones',so.stones!=null?`${so.stones}%`:null,'of the soil by volume')}</div>`+para(rd.soil&&rd.soil.top):'')+bigNote(f);
    X.soil=block('Rock and soil',b);
  }
  const te=f.terrain;
  if(te){
    const DN={N:'North',NE:'Northeast',E:'East',SE:'Southeast',S:'South',SW:'Southwest',W:'West',NW:'Northwest'};
    const top=te.aspect?Object.entries(te.aspect).sort((a,b)=>b[1]-a[1])[0]:null;
    const rose=te.aspect?`<svg class="rose" viewBox="-50 -50 100 100" role="img" aria-label="Which way the slopes face">${['N','NE','E','SE','S','SW','W','NW'].map((d,k)=>{const r=8+te.aspect[d]/Math.max(...Object.values(te.aspect))*30, a1=(k*45-20)*Math.PI/180, a2=(k*45+20)*Math.PI/180;
        return `<path d="M0 0L${(Math.sin(a1)*r).toFixed(1)} ${(-Math.cos(a1)*r).toFixed(1)}A${r.toFixed(1)} ${r.toFixed(1)} 0 0 1 ${(Math.sin(a2)*r).toFixed(1)} ${(-Math.cos(a2)*r).toFixed(1)}Z"/>`;}).join('')}<text x="0" y="-41" text-anchor="middle">N</text><text x="0" y="48" text-anchor="middle">S</text><text x="45" y="3" text-anchor="middle">E</text><text x="-45" y="3" text-anchor="middle">W</text></svg>`:'';
    const b=`<div class="land"><div class="facts">${fact('Elevation',elev(te.elev[1]),`most of it ${elevRange(te.elev[0],te.elev[2])}`)}${te.aspect?fact('Grade',`${Math.round(Math.tan(te.slope*Math.PI/180)*100)}%`,`${te.slope}° on average`):fact('Slope',`${te.slope}°`,`${Math.round(te.steep*100)}% steeper than 10°, ${Math.round(te.flat*100)}% flat`)}${top?(top[1]<.3?fact('Slopes face','Every way','no main direction'):fact('Slopes face',DN[top[0]],`${Math.round(top[1]*100)}% of sloping ground`)):''}</div>${rose}</div>`+bigNote(f)+reading(rd.land,'What the land means for the vines');
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
    const tr=r=>`<tr><th scope="row"><a href="${link(r[0])}"><i class="sw ${shade(r[0])}"></i>${esc(PL[r[0]]?.[0]||r[0])}</a></th><td>${Array.isArray(r[1])?`${tN(r[1][0])} to ${deg(r[1][1])}`:r[8]?'<small>varies</small>':r[1]!=null?`${deg(r[1])} <small>${esc(r[2]||'')}</small>`:''}</td><td>${r[3]==null?'':Array.isArray(r[3])?elevRange(r[3][0],r[3][2]):elev(r[3])}</td><td>${r[4]!=null?Math.round(r[4]*100)+'%':''}</td><td>${esc(r[6]||'')}</td></tr>`;
    X.parts=block('How its places compare',`<p class="ts-caption sub">${f.depth===0?'A country is too big for one reading.':'Too big and varied for one reading.'} Here is how the places inside it differ.</p><div class="tablewrap"><table class="parts ts-caption"><thead><tr><th>Place</th><th>Growing season</th><th>Elevation</th><th>Steep</th><th>Main grape</th></tr></thead><tbody>${(many?rows.slice(0,12):rows).map(tr).join('')}</tbody></table></div>`
      +(many?`<button type="button" class="link ts-caption more" id="allparts">Show all ${rows.length}</button>`:''));
  }
  if(!sm&&!ru&&!av&&!c&&!R&&!pl&&!rk) X.none=block('What we have','<p class="ts-body">No shape, rules or research for this place yet.</p>');
  const src=[...f.sources,...(R?R.sources:[])];
  X.sources=block('Sources',(M.shapeNote?`<p class="ts-caption sub">${esc(M.shapeNote)}</p>`:'')+knownLine+(src.length?`<ul class="src ts-caption">${src.map(s=>`<li>${s.url?`<a href="${esc(s.url)}" target="_blank" rel="noopener">${esc(s.name)}</a>`:esc(s.name)}</li>`).join('')}</ul>`:''));
  // what the place is, then what grows there, then why it grows there, then the law, then the notes
  const order=['keyfacts','style','terms','short','planted','allowed','climate','soil','land','places','parts','rules','ava','gi','found','none','sources'];
  const JUMP={keyfacts:'Key facts',style:'Style',terms:'Label',planted:'Planted',climate:'Climate',soil:'Rock and soil',land:'Land',places:'Places',allowed:'Grapes',parts:'Differences',rules:'Vineyard',ava:'AVA',gi:'GI',found:'Notes'};
  for(const k of order) if(X[k]) X[k]=X[k].replace('<section class="row"',`<section class="row" id="s-${k}"`);
  const jumps=order.filter(k=>X[k]&&JUMP[k]);
  h=lead+(jumps.length>=2?`<nav class="jump" aria-label="On this page">${jumps.map((k,i)=>`<button type="button" class="step${i?'':' on'}" data-jump="s-${k}">${JUMP[k]}</button>`).join('')}</nav>`:'')+order.map(k=>X[k]||'').join('')+FEEDBACK(f.name,f.id);
  $('#info').innerHTML=h;
  for(const b of document.querySelectorAll('#info [data-jump]')) b.onclick=()=>{const t=document.getElementById(b.dataset.jump); if(t) t.scrollIntoView({behavior:'smooth',block:'start'});};
  const ap=$('#allp'); if(ap) ap.onclick=()=>{M.all=true; renderPlaces(); renderInfo(f);};
  spy();
  const apb=$('#allparts'); if(apb) apb.onclick=()=>{M.allParts=true; renderInfo(f); M.allParts=false;};
}
// the chip for the section in view stays lit (the chip bar in the app)
let SPY=null;
function spy(){
  if(SPY) SPY.disconnect(); const nav=$('#info .jump'); if(!nav||!('IntersectionObserver' in window)) return;
  const set=id=>{for(const b of nav.querySelectorAll('[data-jump]')){const on=b.dataset.jump===id; b.classList.toggle('on',on); if(on&&nav.scrollWidth>nav.clientWidth) nav.scrollTo({left:b.offsetLeft-20,behavior:'smooth'});}};
  const seen=new Map();
  SPY=new IntersectionObserver(es=>{for(const e of es) seen.set(e.target.id,e.isIntersecting?e.boundingClientRect.top:null);
    const ids=[...nav.querySelectorAll('[data-jump]')].map(b=>b.dataset.jump), first=ids.find(i=>seen.get(i)!=null); if(first) set(first);},
    {root:WIDE()?$('main'):null,rootMargin:'-60px 0px -55% 0px'});
  for(const b of nav.querySelectorAll('[data-jump]')){const t=document.getElementById(b.dataset.jump); if(t) SPY.observe(t);}
}
// the feedback form (Google Forms): the place and its page link are filled in, the reader writes the rest
const FEEDBACK=(name,id)=>`<section class="row" id="s-feedback"><p class="ts-caption">See something wrong or missing?</p><a class="feedback ts-caption" href="${FORM_URL}?usp=pp_url&entry.673545042=${encodeURIComponent(name)}&entry.612336214=${encodeURIComponent(location.origin+location.pathname+link(id))}" target="_blank" rel="noopener">Send feedback</a><p class="ts-caption about-link"><button type="button" class="link ts-caption" data-units>Units</button> · <button type="button" class="link ts-caption" data-about>About the Atlas</button></p></section>`;
// About: where the data comes from and the terms each source sets (About.swift in the app)
const ABOUT_SOURCES=[
  ['Candiago et al. 2022, EU wine PDO inventory','European boundaries and rules','https://doi.org/10.1038/s41597-022-01513-0'],
  ['UC Davis AVA Project','US boundaries','https://github.com/UCDavisLibrary/ava'],
  ['Eurostat GISCO','Countries and regions','https://ec.europa.eu/eurostat/web/gisco'],
  ['Wine Australia and IPONZ','Australian and New Zealand boundaries','https://www.wineaustralia.com/'],
  ['INAO via OpenDataWine','French grand cru plots','https://github.com/24eme/opendatawine'],
  ['Anderson, Nelgen and Puga','What is planted (CC BY 4.0)','https://doi.org/10.25909/32870405.v1'],
  ['WorldClim 2.1','Monthly temperatures, used with the author\'s permission','https://www.worldclim.org/'],
  ['Beck et al. 2023','Climate type','https://doi.org/10.1038/s41597-023-02549-6'],
  ['ISRIC SoilGrids 2.0','Soil (CC BY 4.0)','https://www.isric.org/explore/soilgrids'],
  ['Macrostrat','Rock (CC BY 4.0)','https://macrostrat.org/'],
  ['AWS Terrain Tiles','Elevation and slope','https://registry.opendata.aws/terrain-tiles/'],
  ['Wikidata and Wikimedia','How well known each place is','https://www.wikidata.org/'],
];
const REPO='https://github.com/otplabs-io/appellation_atlas';
function openAbout(){
  let d=$('#about');
  if(!d){d=document.createElement('dialog'); d.id='about'; d.className='about'; d.setAttribute('aria-labelledby','about-title'); document.body.appendChild(d);
    d.addEventListener('click',e=>{if(e.target===d||e.target.closest('[data-close]')) d.close();});}
  const a=(u,t)=>`<a href="${esc(u)}" target="_blank" rel="noopener">${esc(t)}</a>`;
  d.innerHTML=`<div class="about-in"><div class="about-head"><h2 id="about-title" class="ts-section_head">About the Atlas</h2><button type="button" class="link ts-body" data-close>Done</button></div>
    <p class="ts-body">Every wine place in the world on one globe, with what is planted there, its climate, its rock and its land. There is no account and nothing to sign in to.</p>
    <p class="ts-body">The Atlas is free to use. It is updated from time to time based on feedback from the people who use it.</p>
    <p class="ts-caption about-n">${fmt(Object.keys(PL).length)} places</p>
    <h3 class="ts-caption about-h">Open source</h3>
    <p class="ts-caption">The code is on GitHub under the MIT License. Anyone can read it, copy it, change it and run it on their own computer. ${a(REPO,'github.com/otplabs-io/appellation_atlas')}</p>
    <h3 class="ts-caption about-h">Where the data comes from</h3>
    <ul class="about-src">${ABOUT_SOURCES.map(([n,w,u])=>`<li>${a(u,n)}<span class="ts-caption">${esc(w)}</span></li>`).join('')}</ul>
    <p class="ts-caption about-n"><a href="privacy.html">Privacy</a> · <a href="support.html">Support</a></p>
    <p class="ts-caption about-note">The notes on how soil, slope and climate affect vines are general viticulture. They describe what usually happens, not findings about each place.</p></div>`;
  d.showModal();
}
document.addEventListener('click',e=>{if(e.target.closest('[data-about]')) openAbout();});
// Units: the whole system at once, or each kind on its own (UnitsView in the app)
const UNIT_ROWS=[['temp','Temperature','°F','°C',()=>`Burgundy's growing season: ${deg(14.8)}`],['heat','Heat','°F days','°C days',()=>`Burgundy: ${heat(1064)}`],
  ['rain','Rainfall','in','mm',()=>`Shown in ${usU('rain')?'inches':'millimeters'}`],['elev','Elevation','ft','m',()=>`Heights and lengths in ${usU('elev')?'feet':'meters'}`],
  ['dist','Distance','mi','km',()=>`Shown in ${usU('dist')?'miles':'kilometers'}`],['area','Area','acres','ha',()=>`Shown in ${usU('area')?'acres':'hectares'}`]];
function setUnits(k,v){
  for(const x of k?[k]:UNIT_KINDS) UNITS[x]=v;
  try{localStorage.setItem('atlas-units',JSON.stringify(UNITS));}catch(e){}
  openUnits(); render();
}
function openUnits(){
  let d=$('#units');
  if(!d){d=document.createElement('dialog'); d.id='units'; d.className='about'; d.setAttribute('aria-labelledby','units-title'); document.body.appendChild(d);
    d.addEventListener('click',e=>{const b=e.target.closest('[data-unit]'); if(b){const [k,v]=b.dataset.unit.split(':'); setUnits(k==='all'?null:k,v); return;}
      if(e.target===d||e.target.closest('[data-close]')) d.close();});}
  const vals=UNIT_KINDS.map(k=>UNITS[k]), sys=vals.every(v=>v==='us')?'us':vals.every(v=>v==='m')?'m':'custom';
  const btn=(on,key,label)=>`<button type="button" class="ts-body" aria-pressed="${on}" ${key?`data-unit="${key}"`:'disabled'}>${label}</button>`;
  const focus=document.activeElement&&d.contains(document.activeElement)?document.activeElement.dataset.unit:null;
  d.innerHTML=`<div class="about-in"><div class="about-head"><h2 id="units-title" class="ts-section_head">Units</h2><button type="button" class="link ts-body" data-close>Done</button></div>
    <div class="useg sys" role="group" aria-label="Measurement system">${btn(sys==='us','all:us','US')}${btn(sys==='m','all:m','Metric')}${btn(sys==='custom','','Custom')}</div>
    <ul class="urows">${UNIT_ROWS.map(([k,n,a,b,ex])=>`<li><span><span class="ts-body un">${n}</span><span class="ts-caption">${esc(ex())}</span></span><span class="useg" role="group" aria-label="${n}">${btn(UNITS[k]==='us',k+':us',a)}${btn(UNITS[k]==='m',k+':m',b)}</span></li>`).join('')}</ul>
    <p class="ts-caption about-note">At first the Atlas follows your browser's region. Figures set by law stay as the rules state them, like yields in hectoliters per hectare.</p></div>`;
  if(focus){const f=d.querySelector(`[data-unit="${focus}"]`); if(f) f.focus();}
  if(!d.open) d.showModal();
}
document.addEventListener('click',e=>{if(e.target.closest('[data-units]')) openUnits();});
const FORM_URL='https://docs.google.com/forms/d/e/1FAIpQLSc7CmB3DsylFI0kt6tZncSwq53i8jsEuxdrv4deyIuWJHq8oA/viewform';
async function render(){
  readHash();
  if(S.view==='compare') return renderCompare();
  if(S.view==='pairs') return renderPairs();
  renderPlaces(); mapShow();
  if(S.p==='world'){renderTitle('world'); $('#info').innerHTML=''; return;}
  renderTitle(S.p,null);
  const id=S.p, f=await facts(id); if(S.p===id) renderInfo(f);
}
// ---------- compare: two places side by side (CompareView in the app)
let PAIRS=null;
async function pairs(){if(!PAIRS){const r=await fetch('compare.json'); PAIRS=r.ok?(await r.json()).pairs:[];} return PAIRS;}
const pairOf=(a,b)=>(PAIRS||[]).find(p=>(p.a===a&&p.b===b)||(p.a===b&&p.b===a));
const cmpLink=(a,b)=>'#/compare/'+a+(b?'/vs/'+b:'');
// two outlines in their tones, to one scale when their sizes allow it; box is the larger side in pixels
function shapes(a,oa,b,ob,box,inset,looseAt=10){   // looseAt: under 1/looseAt of the box, the smaller shape is drawn to its own scale
  if(!oa||!ob) return null;
  const sa=Math.max(oa.w,oa.h), sb=Math.max(ob.w,ob.h), s=box/Math.max(sa,sb), loose=Math.min(sa,sb)*s<box/looseAt;
  const svg=(id,o,k)=>`<svg class="cshape ${shade(id)}" viewBox="0 0 ${o.w} ${o.h}" width="${Math.max(2,o.w*k).toFixed(1)}" height="${Math.max(2,o.h*k).toFixed(1)}" aria-hidden="true"><path d="${o.d}"/></svg>`;
  if(loose&&!inset) return {a:svg(a,oa,box/sa),b:svg(b,ob,box/sb),loose:true,times:Math.round(Math.max(sa,sb)/Math.min(sa,sb))};
  const r={a:svg(a,oa,s),b:svg(b,ob,s),loose:false,pxkm:s};
  if(inset&&Math.min(sa,sb)*s<box/4){   // the smaller one is hard to read at true scale: it stays there, small, with an enlarged copy above it
    const small=sa<sb?'a':'b', o=sa<sb?oa:ob, id=sa<sb?a:b, W=WIDE()?196:110, H=WIDE()?132:76, z=Math.min(W/o.w,H/o.h)/s;
    r[small]+=`<span class="czoom">${svg(id,o,s*z)}</span><span class="czoom-n">enlarged ${fmt(Math.round(z))} times</span>`; r.zoom=small;}
  return r;
}
// a scale bar about a third of the box wide, in round miles or kilometers
function scaleBar(pxkm,box){
  const u=usU('dist')?1.609344:1, want=box/3/pxkm/u, p=10**Math.floor(Math.log10(want)), n=[1,2,5,10].map(x=>x*p).filter(x=>x<=want).pop()||p;
  return `<span class="cbar"><i style="width:${(n*u*pxkm).toFixed(1)}px"></i></span>${fmt(n)} ${usU('dist')?(n===1?'mile':'miles'):'km'}`;
}
const dryOf=k=>!k?null:k[0]==='B'?'an arid climate':{f:'no dry season',s:'dry summers',w:'dry winters',m:'a short dry season'}[k[1]]||null;
const summerOf=k=>!k||k[0]==='B'||k[0]==='E'?null:{a:'hot',b:'warm',c:'cool',d:'cold'}[k[2]]||null;
const latOf=c=>c&&c.lat!=null?`${Math.abs(Math.round(c.lat))}°${c.lat<0?'S':'N'}`:'';
// the leading grape and its share, when the figures are for the place itself
function lead(f){const pl=f.planted; if(!pl||!pl.grapes||!pl.grapes.length||!['own','within','country'].includes(pl.scope)) return null;
  const gs=pl.grapes.filter(([n])=>n!=='Other'), g=gs[0]; return g?{g:g[0],p:Math.round(g[1]/pl.ha*100),y:pl.year,about:!!pl.whites_older,names:gs.map(x=>x[0]),c:g[2],two:gs.slice(0,2).map(([n,ha])=>`${n} ${Math.round(ha/pl.ha*100)}%`).join(', ')}:null;}
const only=f=>f.rules&&f.rules.grapes&&f.rules.grapes.length===1&&!(f.rules.grapes_other||[]).length?f.rules.grapes[0]:null;   // the one grape its rules allow
const andJoin=t=>{const x=String(t||'').split(/,\s*|\s+and\s+/).filter(Boolean); return andList(x);};
// how the places compare, in sentences built only from the Atlas's own figures: the season first, then the rain, then what
// is planted, then how big each is (Compare.placesText in the app)
function placesText(fa,fb,p){
  const A=fa.name,B=fb.name,ca=fa.climate,cb=fb.climate,s=[];
  const wa=fa.winkler&&fa.winkler[0],wb=fb.winkler&&fb.winkler[0]; let same=false;
  if(ca&&cb&&ca.gst!=null&&cb.gst!=null){const ta=tN(ca.gst),tb=tN(cb.gst),d=Math.abs(ta-tb);
    if(d<=1){same=true; const both=PL[fa.id]&&PL[fb.id]&&tone(fa.id)!=='o'&&tone(fb.id)!=='o'&&tone(fa.id)!=='i'&&tone(fb.id)!=='i';
      s.push(`${both&&p&&p.link&&!p.tag?`Two benchmarks for ${andJoin(p.link)} with almost the same growing season`:'Almost the same growing season'}: ${d===0?`both average ${deg(ca.gst)}`:`${deg(ca.gst)} in ${A} and ${deg(cb.gst)} in ${B}`}${wa&&wb?(wa===wb?` and both are Winkler region ${wa}`:`, Winkler region ${wa} against ${wb}`):''}.`);}
    else{const [W,C,cw,cc,ww,wc]=ta>tb?[A,B,ca,cb,wa,wb]:[B,A,cb,ca,wb,wa];
      s.push(`${W}'s growing season is ${d}${tU()} warmer: ${deg(cw.gst)} against ${deg(cc.gst)}${ww&&wc?(ww===wc?`, though both are Winkler region ${ww}`:`, Winkler region ${ww} against ${wc}`):''}.`);}}
  else if(wa&&wb) s.push(wa===wb?`Both are Winkler region ${wa}.`:`${A} is Winkler region ${wa}; ${B} is ${wb}.`);
  const da=dryOf(ca&&ca.koppen),db=dryOf(cb&&cb.koppen),ha=summerOf(ca&&ca.koppen),hb=summerOf(cb&&cb.koppen);
  const dry=(X,d)=>d==='no dry season'?`${X} has no dry season`:d==='dry summers'?`${X}'s summers are dry`:d==='dry winters'?`${X}'s winters are dry`:d==='an arid climate'?`${X} is arid`:`${X} has ${d}`;
  if(da&&db&&da!==db) s.push(`${same?'The difference is rain. ':''}${dry(A,da)}, while ${dry(B,db)}.`);
  else if(da&&db){const af=!(ca&&cb&&ca.gst!=null&&cb.gst!=null)||ca.gst>=cb.gst, [P,Q,hp,hq]=af?[A,B,ha,hb]:[B,A,hb,ha];   // the warmer place first
    s.push(`${da==='no dry season'?'Neither has a dry season':`Both have ${da}`}${ha&&hb&&ha!==hb?`, but ${P}'s summers are ${hp} and ${Q}'s ${hq}`:''}.`);}
  const la=lead(fa),lb=lead(fb);
  if(la&&lb){
    if(la.g===lb.g) s.push(`${la.g} leads in both: ${la.p}% of the vines in ${A} and ${lb.p}% in ${B}.`);
    else if(la.names[1]===lb.g) s.push(`${A} plants more ${la.g} than ${lb.g}; in ${B}, ${lb.g} is ${lb.p}% of the vines.`);
    else if(lb.names[1]===la.g) s.push(`${B} plants more ${lb.g} than ${la.g}; in ${A}, ${la.g} is ${la.p}% of the vines.`);
    else s.push(`${la.g} leads in ${A}, at ${la.p}% of the vines; in ${B} it is ${lb.g}, at ${lb.p}%.`);}
  else{const oa=only(fa),ob=only(fb);
    if(la&&ob) s.push(`${B} is made only from ${ob[0]}; in ${A}, ${la.g} leads at ${la.p}% of the vines.`);
    else if(lb&&oa) s.push(`${A} is made only from ${oa[0]}; in ${B}, ${lb.g} leads at ${lb.p}% of the vines.`);}
  const sz=f=>{const n=f.rules&&f.rules.communes&&f.rules.communes.length, k=f.kind&&f.kind[0], m=f.summary&&f.summary.places;
    return n&&k?{t:`one ${k} of ${fmt(n)} commune${n===1?'':'s'}`,n:0}:m?{t:`a whole ${f.depth===0?'country':'region'} of ${fmt(m)} places`,n:m}:null;};
  const za=sz(fa),zb=sz(fb);
  if(za&&zb&&(!za.n||!zb.n)&&za.n!==zb.n){const [x,y,X,Y]=za.n<zb.n?[za,zb,A,B]:[zb,za,B,A]; s.push(`${X} is ${x.t}; ${Y} is ${y.t}.`);}
  const ea=fa.terrain&&fa.terrain.elev,eb=fb.terrain&&fb.terrain.elev;
  if(ea&&eb&&Math.abs(ea[1]-eb[1])>=250) s.push(`The vineyards sit higher in ${ea[1]>eb[1]?A:B}, at about ${elev(Math.max(ea[1],eb[1]))} against ${elev(Math.min(ea[1],eb[1]))}.`);
  return s.join(' ');
}
// a source's short name, for the line at the foot of Compare
const SHORT=[[/^Fick and Hijmans 2017/,'WorldClim 2.1'],[/^Beck et al\. 2023/,'Beck et al. 2023 Köppen maps'],[/^Winkler, Cook/,'Winkler 1974'],[/^Jones 2010/,'Jones 2010'],[/^Anderson, Nelgen and Puga/,'University of Adelaide grape-area database'],[/^Candiago et al\. 2022/,'Candiago et al. 2022']];
function shortName(n,wine){for(const [re,t] of SHORT) if(re.test(n)) return t;
  n=n.replace(/\s*\((what the wines taste like|key facts|what the label terms mean)\)$/,'');
  const i=n.indexOf(', '); return i<0?n:wine?n.slice(0,i)+' on '+n.slice(i+2):n.slice(0,i);}
function cmpSources(fa,fb,p,rulesFor){
  const line=(head,list,wine)=>{const seen=new Set(), xs=list.filter(Boolean).filter(x=>{const k=shortName(x.name,wine); return !seen.has(k)&&seen.add(k);});
    return xs.length?`<span>${head}: ${xs.map(x=>x.url?`<a href="${esc(x.url)}" target="_blank" rel="noopener">${esc(shortName(x.name,wine))}</a>`:esc(shortName(x.name,wine))).join(wine?'; ':', ')}.</span>`:'';};
  const of=(f,k)=>f?((f.src_for||{})[k]||[]).map(i=>f.sources[i]):[];
  const style=f=>f?f.sources.filter(x=>/\(what the wines taste like\)$/.test(x.name)):[];
  const wines=p&&p.wines.length?p.sources:[...style(fa),...style(fb)];
  return `<div class="csrc o7"><b>SOURCES</b>${line('Climate',[...of(fa,'climate'),...of(fb,'climate')])}${rulesFor.length?line('Rules',rulesFor.flatMap(f=>of(f,'map'))):''}${line('Plantings',[...of(fa,'planted'),...of(fb,'planted')])}${line('Wines',wines,true)}</div>`;
}
// the twelve months as bars to one scale for both places, 30°F to 74°F, the growing season in coral (the month charts in the app)
function monChart(f,c,h){
  if(!c||!c.tavg) return '';
  const south=c.lat<0, gs=south?[9,10,11,0,1,2,3]:[3,4,5,6,7,8,9];
  const bars=c.tavg.map((v,i)=>`<span><em>${tN(v)}</em><i class="${gs.includes(i)?'gs':''}" style="height:${Math.max(2,Math.round((toF(v)-30)*h/44))}px"></i></span>`).join('');
  return `<div class="cm" role="img" aria-label="${esc(f.name)} by month: ${c.tavg.map(tN).join(', ')}"><div class="cm-bars">${bars}</div><div class="cm-m">${[...'JFMAMJJASOND'].map(m=>`<span>${m}</span>`).join('')}</div><b>${esc(shortPlace(f.name))} · ${deg(c.gst)} season</b></div>`;
}
const shortPlace=n=>n.replace(/ (Valley|County|AVA|DOC|DOCG|DOCa|DO)$/,'');
const US_STATES={AL:'Alabama',AK:'Alaska',AZ:'Arizona',AR:'Arkansas',CA:'California',CO:'Colorado',CT:'Connecticut',DE:'Delaware',FL:'Florida',GA:'Georgia',HI:'Hawaii',ID:'Idaho',IL:'Illinois',IN:'Indiana',IA:'Iowa',KS:'Kansas',KY:'Kentucky',LA:'Louisiana',ME:'Maine',MD:'Maryland',MA:'Massachusetts',MI:'Michigan',MN:'Minnesota',MS:'Mississippi',MO:'Missouri',MT:'Montana',NE:'Nebraska',NV:'Nevada',NH:'New Hampshire',NJ:'New Jersey',NM:'New Mexico',NY:'New York',NC:'North Carolina',ND:'North Dakota',OH:'Ohio',OK:'Oklahoma',OR:'Oregon',PA:'Pennsylvania',RI:'Rhode Island',SC:'South Carolina',SD:'South Dakota',TN:'Tennessee',TX:'Texas',UT:'Utah',VT:'Vermont',VA:'Virginia',WA:'Washington',WV:'West Virginia',WI:'Wisconsin',WY:'Wyoming'};
const subOf=(f,id)=>[f.ava&&f.ava.states&&f.ava.states.length===1&&(US_STATES[f.ava.states[0]]||f.ava.states[0])||(PL[id]?.[4]&&PL[id][4]!==f.name?PL[id][4]:''),latOf(f.climate)].filter(Boolean).join(' · ');
const skinOf=f=>{const l=lead(f); if(l&&l.c) return l.c==='R'?'r':l.c==='W'?'w':'p'; const o=only(f); return o?(o[1]==='red'?'r':o[1]==='white'?'w':'p'):'w';};
async function renderCompare(){
  const a=S.ca,b=S.cb; await pairs();
  const [fa,fb]=await Promise.all([a?facts(a):null,b?facts(b):null]); if(S.ca!==a||S.cb!==b||S.view!=='compare') return;
  const nm=id=>esc(PL[id]?.[0]||id);
  const chip=(id,k)=>id?`<span class="cchip"><i class="sw ${shade(id)}"></i>${nm(id)}<a class="x" href="${cmpLink(k?a:b||'')}" aria-label="Choose another place instead of ${nm(id)}">✕</a></span>`:`<span class="cchip empty">${k?'A second place':'A first place'}</span>`;
  const chips=`<div class="cchips">${chip(a,0)}<span class="cand">and</span>${chip(b,1)}</div>`;
  const back=a?link(a):'#/';
  const top=`<div class="cbar-top"><a class="cback" href="${back}" data-back aria-label="Back">${BACK}</a><h1>Compare</h1>${chips}<a class="cpill other" href="#/pairs">Other pairs</a></div>`;
  if(!a||!b||!fa||!fb){
    const near=(PAIRS||[]).filter(p=>p.a===a||p.b===a).map(p=>p.a===a?p.b:p.a);
    $('#info').innerHTML=`<div class="cmp-pick">${top}${chips.replace('cchips','cchips below')}<div class="cmp-near"><div class="cmp-search"><label><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></svg><span class="sr">Search</span><input id="cq" type="search" placeholder="${a?`Search a place to compare with ${nm(a)}`:'Search the first place'}" autocomplete="off" autocapitalize="off" spellcheck="false" aria-autocomplete="list" aria-controls="csugg"></label><ul id="csugg" class="sugg" role="listbox" hidden></ul></div>`
      +(near.length?`<p class="ck">Often compared with ${nm(a)}</p><div class="chips">${near.map(id=>`<a class="chip" href="${cmpLink(a,id)}"><i class="sw ${shade(id)}"></i>${nm(id)}</a>`).join('')}</div>`:'')
      +`<p class="ts-caption"><a href="#/pairs">See all often compared pairs</a></p></div></div>`;
    wireSearch($('#cq'),$('#csugg'),x=>{if(x.id===S.ca) return; location.hash=cmpLink(S.ca||x.id,S.ca?x.id:null);}); if(!matchMedia('(hover:none)').matches) $('#cq').focus();
    return;
  }
  const p=pairOf(a,b), wide=WIDE(), box=wide?293:154, sh=shapes(a,fa.outline,b,fb.outline,box,true);
  const col=(id,f,svg)=>`<div class="ccol"><div class="cart">${svg||'<span class="csub">No outline</span>'}</div><div class="cnm"><a class="cname" href="${link(id)}"><i class="sw ${shade(id)}"></i>${nm(id)}</a><span class="csub">${esc(subOf(f,id))}</span>${f.outline&&f.outline.far?'<span class="csub">Far-off islands and territories not drawn</span>':''}</div></div>`;
  const card=`<div class="ccard o1"><div class="cgrid">${col(a,fa,sh&&sh.a)}${col(b,fb,sh&&sh.b)}</div>`
    +(sh?`<p class="cnote">${sh.loose?`Too different in size to draw to one scale. ${nm(Math.max(fa.outline.w,fa.outline.h)>Math.max(fb.outline.w,fb.outline.h)?a:b)} is about ${fmt(sh.times)} times as long.`:`${scaleBar(sh.pxkm,box)} · both drawn to the same scale`}</p>`:'')+`</div>`;
  const INFO='<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16.5v.5"/></svg>';
  const diff=p&&p.tag==='different-grapes'?`<div class="cdiff o2" role="note">${INFO}<p><b>Different grapes.</b> ${esc(p.note||`${PL[a][0]} and ${PL[b][0]} are made from different grapes, so this page compares the typical wine of each.`)}</p></div>`:'';
  const pt=placesText(fa,fb,p);
  const ca=fa.climate,cb=fb.climate, mh=wide?96:57;
  const charts=ca&&ca.tavg||cb&&cb.tavg?`<div class="cblk o4"><span class="ck">Average by month, ${tU()}</span><div class="cmon">${monChart(fa,ca,mh)}${monChart(fb,cb,mh)}</div></div>`:'';
  const rulesFor=[];
  const grapesOf=(f,both)=>{const l=lead(f); if(l) return `${esc(l.two)}${both?'':' planted'} (${l.y}${l.about?', approximate':''})`; const o=only(f); if(o){rulesFor.push(f); return `${esc(o[0])}, the only grape its rules allow`;} return '';};
  const la=lead(fa),lb=lead(fb), both=!!(la&&lb), ga=grapesOf(fa,both), gb=grapesOf(fb,both);
  const row=(k,x,y)=>x||y?`<div class="crow"><b>${k}</b><span>${x||'No figures'}</span><span>${y||'No figures'}</span></div>`:'';
  const rows=`<div class="crows o5">${row('Heat',ca&&ca.gdd!=null&&heat(ca.gdd),cb&&cb.gdd!=null&&heat(cb.gdd))}${row(both||!(ga||gb)?'Planted':'Grapes',ga,gb)}</div>`;
  const paras=t=>String(t).split(/\n\n+/).map(x=>`<p>${esc(x)}</p>`).join('');
  let wines='';
  if(p&&p.wines.length) wines=`<div class="cwines o6"><span class="ck red">How the wines compare</span>${p.wines.map(w=>`<div class="cw"><h3><i class="${w.c||'w'}"></i>${esc(w.head)}</h3>${paras(w.text)}</div>`).join('')}</div>`;
  else{const own=[[a,fa],[b,fb]].filter(([,f])=>f.style&&f.style.notes.length);
    if(own.length) wines=`<div class="cwines own o6"><span class="ck red">The wines</span>${own.map(([id,f])=>`<div class="cw"><h3><i class="${skinOf(f)}"></i>${nm(id)}</h3>${f.style.notes.slice(0,2).map(t=>`<p>${esc(t)}</p>`).join('')}</div>`).join('')}</div>`;}
  $('#info').innerHTML=`<div class="cmp">${top}<div class="cmp-body"><div class="ccol-l">${card}${charts}${rows}</div><div class="ccol-r">${diff}${pt?`<div class="cblk o3"><span class="ck red">How the places compare</span><p>${esc(pt)}</p></div>`:''}${wines}${cmpSources(fa,fb,p,rulesFor)}</div></div></div>`;
}
async function renderPairs(){
  await pairs(); if(S.view!=='pairs') return;
  const tag={'different-grapes':'Different grapes','sounds-alike':'More different than they sound'};
  const li=(p,i)=>{const sh=shapes(p.a,p.oa,p.b,p.ob,46,false,5);
    return `<li><a href="${cmpLink(p.a,p.b)}"><span class="pn">${i+1}</span><span class="pa">${sh?sh.a+sh.b:''}</span><span class="pt"><b>${esc(PL[p.a]?.[0]||p.a)} · ${esc(PL[p.b]?.[0]||p.b)}</b><span class="pl">${esc(p.link)}</span>`
      +`<span class="ptags">${p.tag?`<i class="ptag ${p.tag}">${tag[p.tag]}</i>`:''}${sh&&sh.loose?'<i class="ptag loose">Not to scale</i>':''}</span></span></a></li>`;};
  const any='<a class="cpill teal" href="#/compare">Compare any two</a>';
  $('#info').innerHTML=`<div class="ptop"><a class="cback" href="#/" data-back aria-label="Back">${BACK}</a>${any}</div>`
    +`<div class="phead"><div><h1>Often compared</h1><p>The pairs people set side by side most, among benchmark regions.${WIDE()?' Each pair is drawn to one scale unless marked.':''}</p></div>${WIDE()?any:''}</div>`
    +`<ol class="pairs">${PAIRS.map(li).join('')}</ol>${WIDE()?'':'<p class="pfoot">Each pair is drawn to one scale, so you can see how their sizes compare, unless marked not to scale.</p>'}`;
}
// ---------- search
let ALL=null;
function wireSearch(q,ul,choose){   // a search box and its list; choose gets the place picked
  let list=[], sel=-1;
  ALL=ALL||Object.entries(PL).map(([id,x])=>({id,name:x[0],f:fold([x[0],...(x[5]||[])].join(' ')),s:x[2],k:x[3],c:x[4]}));
  const show=()=>{ul.hidden=!list.length; q.setAttribute('aria-expanded',String(!!list.length));
    ul.innerHTML=list.map((x,i)=>`<li role="option" aria-selected="${i===sel}" data-i="${i}"><span class="sl">${esc(x.name)} <small>${esc([x.k,x.c].filter(Boolean).join(', '))}</small></span></li>`).join('');};
  const pickIt=x=>{q.value=''; list=[]; show(); q.blur(); choose(x);};
  q.addEventListener('input',()=>{const t=fold(q.value.trim()); sel=-1;
    list=t.length<2?[]:ALL.filter(x=>x.f.includes(t)).sort((a,b)=>(b.f.startsWith(t)-a.f.startsWith(t))||b.s-a.s).slice(0,10); show();});
  q.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){sel=Math.min(list.length-1,sel+1); show(); e.preventDefault();} else if(e.key==='ArrowUp'){sel=Math.max(-1,sel-1); show(); e.preventDefault();}
    else if(e.key==='Enter'&&list.length){pickIt(list[Math.max(0,sel)]); e.preventDefault();} else if(e.key==='Escape'){list=[]; show();}});
  ul.addEventListener('mousedown',e=>{const li=e.target.closest('li'); if(li){e.preventDefault(); pickIt(list[+li.dataset.i]);}});
  q.addEventListener('blur',()=>setTimeout(()=>{list=[]; show();},150));
}
async function main(){
  [GEO,WORLD,PL]=await Promise.all(['geo/index.json','geo/world.json','places.json'].map(u=>fetch(u).then(r=>r.json())));
  PL=PL.places; SCORED=Object.values(PL).some(x=>x[2]>=0); mapInit(); wireSearch($('#q'),$('#sugg'),x=>go(x.id));

  addEventListener('hashchange',()=>{M.came=true; render(); window.scrollTo({top:0,behavior:'smooth'}); const m=$('main'); if(m) m.scrollTop=0;});
  const fb=()=>document.querySelectorAll('[data-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.filter===FILTER)));
  fb(); document.addEventListener('click',e=>{const b=e.target.closest('[data-filter]'); if(!b) return; FILTER=b.dataset.filter; try{localStorage.setItem('atlas-filter',FILTER);}catch(e){} fb(); if(M.view){restyle(); labels();}});
  pairs().then(ps=>{const el=$('#sidePairs'); if(el) el.innerHTML=`<div class="sp-head"><span>Often compared</span><a href="#/pairs">All ${ps.length}</a></div>`
    +ps.slice(0,3).map((p,i)=>`<a class="sp" href="${cmpLink(p.a,p.b)}"><b>${i+1}</b><span><span class="sp-n">${esc(PL[p.a]?.[0]||p.a)} · ${esc(PL[p.b]?.[0]||p.b)}</span><span class="sp-l">${esc(p.link)}</span></span></a>`).join('');});
  document.addEventListener('click',e=>{const b=e.target.closest('[data-back]'); if(b&&M.came){e.preventDefault(); history.back();}});
  render();
}
main();
})();
