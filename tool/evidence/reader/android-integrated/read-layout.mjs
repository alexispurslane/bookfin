const port = process.argv[2];
if (!/^\d+$/.test(port ?? '')) throw Error('Pass the owned WebView diagnostic port');
let target;
const deadline = Date.now() + 20000;
while (!target && Date.now() < deadline) {
  const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  target = targets.find(target => target.url === 'https://bookfin-runtime.invalid/index.html');
  if (!target) await new Promise(resolve => setTimeout(resolve, 100));
}
if (!target) throw Error('No reader target');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(resolve => socket.addEventListener('open', resolve, {once: true}));
let requestId = 0;
const pending = new Map();
socket.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.id) {
    pending.get(message.id)?.(message);
    pending.delete(message.id);
  }
});
const call = (method, params = {}) => new Promise(resolve => {
  const identifier = ++requestId;
  pending.set(identifier, resolve);
  socket.send(JSON.stringify({id: identifier, method, params}));
});
for (let sample = 0; sample < (process.argv.includes('--timeline') ? 40 : 1); sample++) {
const result = await call('Runtime.evaluate', {returnByValue: true, expression: `JSON.stringify({
  at: new Date().toISOString(),
  outer: {width:innerWidth,height:innerHeight,fontStatus:document.fonts.status},
  frames: Array.from(document.querySelectorAll('iframe')).map(frame => {
    const document = frame.contentDocument;
    const window = frame.contentWindow;
    const bodyStyle = window.getComputedStyle(document.body);
    const frameRect = frame.getBoundingClientRect();
    const paragraphs = Array.from(document.querySelectorAll('h1,p,a')).map(element => {
      const rectangle = element.getBoundingClientRect();
      return {text:element.textContent.slice(0,160),left:rectangle.left,top:rectangle.top,width:rectangle.width,height:rectangle.height};
    }).filter(rectangle => rectangle.left + frameRect.left < innerWidth && rectangle.left + rectangle.width + frameRect.left > 0 && rectangle.top + frameRect.top < innerHeight && rectangle.top + rectangle.height + frameRect.top > 0);
    return {source:frame.src,width:frame.clientWidth,height:frame.clientHeight,left:frameRect.left,top:frameRect.top,fontStatus:document.fonts.status,fontSize:bodyStyle.fontSize,fontFamily:bodyStyle.fontFamily,columnWidth:bodyStyle.columnWidth,background:bodyStyle.backgroundColor,scrollX:window.scrollX,paragraphs};
  })
})`});
if (result.error || result.result?.exceptionDetails) throw Error(JSON.stringify(result));
console.log(result.result.result.value);
await new Promise(resolve => setTimeout(resolve, 250));
}
socket.close();
