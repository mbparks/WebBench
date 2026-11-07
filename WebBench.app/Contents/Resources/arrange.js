// Input and output are CSS pixels. The canvas supplies measured border boxes
// and CSS width/height separately so content-box padding survives resizing.
'use strict';
const Arrange = (() => {
  const grid = 8;
  function snapAxis(start, size, proposed, features, enabled) {
    if (!enabled) return {value:Math.round(proposed)};
    const change = proposed-start;
    let best = null;
    for (const edge of [start, start+size/2, start+size]) {
      for (const target of features) {
        const offset = target-(edge+change);
        if (Math.abs(offset)<=4 && (!best || Math.abs(offset)<Math.abs(best.offset))) {
          best = {offset,target};
        }
      }
    }
    if (best) return {value:Math.round(proposed+best.offset),guide:best.target};
    return {value:Math.round(proposed/grid)*grid};
  }
  function gesture(g,dx,dy,options) {
    const {snap,shift}=options;
    const values={}, guides={};
    if (g.handle==='move') {
      if (shift) {if (Math.abs(dx)>=Math.abs(dy)) dy=0; else dx=0;}
      for (const [axis,offset,size,delta,prop] of [['x',g.x,g.w,dx,'left'],['y',g.y,g.h,dy,'top']]) {
        if (!delta) continue;
        const p=snapAxis(offset,size,offset+delta,g.targets[axis],snap);
        if (p.value!==offset) values[prop]=p.value;
        if (p.guide!=null) guides[axis]=p.guide;
      }
    } else {
      const west=g.handle.includes('w'), north=g.handle.includes('n');
      const usesX=west||g.handle.includes('e'), usesY=north||g.handle.includes('s');
      const round=v=>snap ? Math.round(v/grid)*grid : Math.round(v);
      const rx=west?-dx:dx, ry=north?-dy:dy;
      if (usesX && dx) values.width=Math.max(1,round(g.width+rx));
      if (usesY && dy) values.height=Math.max(1,round(g.height+ry));
      if (shift && usesX && usesY && g.w>0 && g.h>0) {
        const ratio=g.w/g.h;
        if (Math.abs(rx/g.w)>=Math.abs(ry/g.h)) {
          values.width=Math.max(1,round(g.width+rx));
          values.height=Math.max(1,Math.round((g.w+values.width-g.width)/ratio-g.h+g.height));
        } else {
          values.height=Math.max(1,round(g.height+ry));
          values.width=Math.max(1,Math.round((g.h+values.height-g.height)*ratio-g.w+g.width));
        }
      }
      if(west && values.width!=null && values.width!==g.width)values.left=Math.round(g.x+g.width-values.width);
      if(north && values.height!=null && values.height!==g.height)values.top=Math.round(g.y+g.height-values.height);
      if (values.width===g.width) delete values.width;
      if (values.height===g.height) delete values.height;
    }
    return {values,guides};
  }
  function bounds(frames) {
    const left=Math.min(...frames.map(f=>f.rect.x)), top=Math.min(...frames.map(f=>f.rect.y));
    const right=Math.max(...frames.map(f=>f.rect.x+f.rect.width));
    const bottom=Math.max(...frames.map(f=>f.rect.y+f.rect.height));
    return {x:left,y:top,width:right-left,height:bottom-top};
  }
  // Align rendered border boxes. Apply their deltas to each member's authored CSS origin.
  function selection(frames,command,dx=0,dy=0) {
    if(frames.length<2)throw new Error('Select at least two layers.');
    const round=v=>Math.round(v*1000)/1000;
    const moves=frames.map(f=>({id:f.id,values:{}}));
    function shift(i,axis,delta) {
      if(Math.abs(delta)<0.0005)return;
      const value=round(frames[i][axis]+delta);
      if(!Number.isFinite(value)||Math.abs(value)>1000000)throw new Error('The requested position exceeds the canvas range.');
      moves[i].values[axis==='x'?'left':'top']=value;
    }
    if(command==='move') {
      for(let i=0;i<frames.length;i++){shift(i,'x',dx);shift(i,'y',dy);}
    } else if(command==='spaceX'||command==='spaceY') {
      if(frames.length<3)throw new Error('Select three or more layers for equal spacing.');
      const axis=command==='spaceX'?'x':'y',size=axis==='x'?'width':'height';
      const sorted=frames.map((f,i)=>({i,start:f.rect[axis],size:f.rect[size]}))
        .sort((a,b)=>a.start-b.start || a.i-b.i);
      const first=sorted[0],last=sorted.at(-1);
      const gap=(last.start+last.size-first.start-sorted.reduce((sum,b)=>sum+b.size,0))/(frames.length-1);
      if(gap<0)throw new Error('Move the outer layers farther apart to fit equal gaps.');
      let cursor=first.start+first.size+gap;
      for(const b of sorted.slice(1,-1)){shift(b.i,axis,cursor-b.start);cursor+=b.size+gap;}
    } else {
      const edges={left:['x','width',0],centerX:['x','width',0.5],right:['x','width',1],
        top:['y','height',0],centerY:['y','height',0.5],bottom:['y','height',1]};
      if(!Object.hasOwn(edges,command))throw new Error('Unknown alignment.');
      const [axis,size,fraction]=edges[command];
      const edge=f=>f.rect[axis]+f.rect[size]*fraction;
      for(let i=1;i<frames.length;i++)shift(i,axis,edge(frames[0])-edge(frames[i]));
    }
    return moves;
  }
  return {gesture,grid,bounds,selection};
})();
if (typeof module!=='undefined') module.exports=Arrange;
