import fs from 'node:fs';

const port = fs.readFileSync('.cache/native-cdp-port', 'utf8').trim();
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const target = targets.find(entry => entry.url === 'https://bookfin-runtime.invalid/index.html');
if (!target) throw Error('No normal reader target');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(resolve => socket.addEventListener('open', resolve, {once: true}));
let requestId = 0;
const pending = new Map();
const events = [];
socket.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.id) {
    pending.get(message.id)?.(message);
    pending.delete(message.id);
  } else if (/^Network\.|^Page\.|^Log\./.test(message.method)) {
    events.push(message);
  }
});
const call = (method, params = {}) => new Promise((resolve, reject) => {
  const identifier = ++requestId;
  const timeout = setTimeout(() => reject(Error(`Timed out: ${method}`)), 15000);
  pending.set(identifier, result => { clearTimeout(timeout); resolve(result); });
  socket.send(JSON.stringify({id: identifier, method, params}));
});
const evaluate = async expression => {
  const result = await call('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true});
  if (result.error || result.result?.exceptionDetails) throw Error(JSON.stringify(result));
  return result.result.result.value;
};
const mode = process.argv[2] || 'observe';
await call('DOM.enable');
await call('CSS.enable');
await call('Network.enable');
await call('Page.enable');
await call('Log.enable');
const output = {at: new Date().toISOString(), mode, target: target.url};
if (mode === 'observe') {
  output.document = await evaluate(`Array.from(document.querySelectorAll('iframe')).map(frame => {
    const chapter = frame.contentDocument;
    const view = frame.contentWindow;
    const style = view.getComputedStyle(chapter.body);
    const registeredFonts = Array.from(chapter.fonts).map(font=>({family:font.family,status:font.status,weight:font.weight,style:font.style}));
    const visibleParagraphs = Array.from(chapter.querySelectorAll('h1,p,a')).map(element=>({text:element.textContent,rect:element.getBoundingClientRect().toJSON()})).filter(entry=>entry.rect.left+frame.getBoundingClientRect().left<innerWidth&&entry.rect.right+frame.getBoundingClientRect().left>0&&entry.rect.top+frame.getBoundingClientRect().top<innerHeight&&entry.rect.bottom+frame.getBoundingClientRect().top>0);
    const result = {registeredFonts, visibleParagraphs, color:style.color, background:style.backgroundColor, frameRect:frame.getBoundingClientRect().toJSON()};
    return {...result,url:chapter.URL, sandbox:frame.getAttribute('sandbox'), text:chapter.body.innerText, html:chapter.documentElement.outerHTML, fontStatus:chapter.fonts.status, fontSize:style.fontSize, fontFamily:style.fontFamily, viewport:{width:frame.clientWidth,height:frame.clientHeight}, images:Array.from(chapter.images).map(image=>({source:image.src,alt:image.alt,complete:image.complete,naturalWidth:image.naturalWidth,naturalHeight:image.naturalHeight,rect:image.getBoundingClientRect().toJSON()})), styles:Array.from(chapter.styleSheets).map(sheet=>({href:sheet.href}))};
  })`);
  const documentTree = await call('DOM.getDocument', {depth: -1, pierce: true});
  const paragraphs = [];
  const visit = node => {
    if (node.nodeName === 'P' || node.nodeName === 'H1') paragraphs.push(node);
    for (const child of node.children || []) visit(child);
    if (node.contentDocument) visit(node.contentDocument);
  };
  visit(documentTree.result.root);
  output.appliedFonts = [];
  for (const node of paragraphs.slice(0, 10)) {
    const fonts = await call('CSS.getPlatformFontsForNode', {nodeId: node.nodeId});
    output.appliedFonts.push({nodeId:node.nodeId, text:(node.children || []).map(child=>child.nodeValue).join(''), result:fonts.result || fonts.error});
  }
} else if (mode === 'requests') {
  output.diagnosticOnly = true;
  output.probes = await evaluate(`(async()=>{
    const image = document.querySelector('iframe').contentDocument.querySelector('img').src;
    const results = [];
    for (const [label,url,options] of [
      ['admitted-get',image,{}],
      ['missing-get',new URL('missing-native-probe.png',image).href,{}],
      ['forbidden-query',image+'?native-probe=1',{}],
      ['forbidden-post',image,{method:'POST'}],
      ['loopback-csp','http://127.0.0.1:7365/probe/diagnostic-fetch',{}]
    ]) {try{const response=await fetch(url,options);results.push({label,url,status:response.status,headers:Object.fromEntries(response.headers),bytes:(await response.arrayBuffer()).byteLength});}catch(error){results.push({label,url,error:error.name+': '+error.message});}}
    return results;
  })()`);
} else if (mode === 'network-resource') {
  output.diagnosticOnly = true;
  const frameTree = await call('Page.getFrameTree');
  output.command = {frameId: frameTree.result.frameTree.frame.id, url: 'http://127.0.0.1:7365/probe/native-resource', options: {disableCache: true, includeCredentials: false}};
  output.result = await call('Network.loadNetworkResource', output.command);
} else if (mode === 'permissions') {
  output.diagnosticOnly = true;
  output.probes = await evaluate(`(async()=>{
    const results=[];
    try{const stream=await navigator.mediaDevices.getUserMedia({audio:true,video:true});stream.getTracks().forEach(track=>track.stop());results.push({media:'UNEXPECTED_GRANTED'});}catch(error){results.push({media:error.name+': '+error.message});}
    results.push(await new Promise(resolve=>navigator.geolocation.getCurrentPosition(()=>resolve({geolocation:'UNEXPECTED_GRANTED'}),error=>resolve({geolocation:error.code,message:error.message}),{timeout:3000})));
    return results;
  })()`);
} else if (mode === 'navigation') {
  output.diagnosticOnly = true;
  output.before = await evaluate('location.href');
  output.attempt = await evaluate(`(()=>{location.assign('http://127.0.0.1:7365/probe/diagnostic-navigation');return 'location.assign invoked';})()`);
  await new Promise(resolve=>setTimeout(resolve,1000));
  output.after = await evaluate('location.href');
} else {
  throw Error('Unknown mode');
}
await new Promise(resolve=>setTimeout(resolve,500));
output.events = events;
console.log(JSON.stringify(output, null, 2));
socket.close();
