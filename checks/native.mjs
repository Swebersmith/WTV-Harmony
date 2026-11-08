// Run explicitly with the installed ArkTS compiler; website tests have no SDK dependency.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const compilerPath = process.env.ARKTS_TYPESCRIPT || require.resolve('typescript');
const ts = require(compilerPath);
globalThis.XComponentController=class {};
let requests = [], destroyed = 0, response = {responseCode:200,result:'{"ok":true}'};
const http = {
  RequestMethod:{GET:'GET',POST:'POST'},HttpDataType:{STRING:0},
  createHttp:() => ({request:async (url,options) => { requests.push({url,options}); return response; },destroy:() => {destroyed++;}})
};
const windowApi = {AvoidAreaType:{TYPE_SYSTEM:0,TYPE_CUTOUT:1,TYPE_NAVIGATION_INDICATOR:2}};
const deviceVolume = {level:6,min:0,max:20,listeners:new Set(),fail:false,
  getVolumeByStream(usage){assert.equal(usage,'music');if(this.fail) throw Error('unavailable');return this.level;},
  getMinVolumeByStream(){return this.min;},getMaxVolumeByStream(){return this.max;},
  on(event,usage,cb){assert.equal(event,'streamVolumeChange');assert.equal(usage,'music');this.listeners.add(cb);},
  off(event,cb){assert.equal(event,'streamVolumeChange');this.listeners.delete(cb);}};
const audioApi = {StreamUsage:{STREAM_USAGE_MUSIC:'music'},getAudioManager:()=>({getVolumeManager:()=>deviceVolume})};
const nativePlayers = [];
const stream=()=>{const callbacks=[];return {listen:callback=>callbacks.push(callback),emit:value=>callbacks.forEach(cb=>cb(value))};};
class FakeMpv {
  state={duration:120,eof:false};
  stream={position:stream(),duration:stream(),playing:stream(),buffering:stream(),eof:stream()};
  observers=[];properties=new Map();path='';played=0;destroyed=0;stopped=0;
  native={addEventObserver:observer=>this.observers.push(observer),removeEventObserver:observer=>{this.observers=this.observers.filter(x=>x!==observer);},
    setProperty:(key,value)=>this.properties.set(key,value),getPropertyString:()=>this.path,getProperty:()=>5};
  constructor(config){this.config=config;nativePlayers.push(this);}
  onSurfaceCreated(surface){this.surface=surface;}
  onSurfaceDestroyed(){this.surface='';}
  open(media,autoplay){this.media=media;this.path=media.uri;this.autoplay=autoplay;}
  emit(id,detail){this.observers.forEach(o=>o.onEvent(id,'',detail));}
  play(){this.played++;this.stream.playing.emit(true);}
  pause(){this.stream.playing.emit(false);}
  stop(){this.stopped++;this.path='';}
  destroy(){this.destroyed++;}
  setSpeed(value){this.speed=value;}
  setVolume(value){this.volume=value;}
  seek(value){this.currentTime=value;}
}
const mpvApi={Player:FakeMpv,PlayerConfig:class{constructor(options){Object.assign(this,options);}},Media:class{constructor(uri,options){this.uri=uri;Object.assign(this,options);}},MpvLogLevel:{Error:20},MpvEvent:{MPV_EVENT_FILE_LOADED:8,MPV_EVENT_END_FILE:7}};
const loaded = new Map();
function load(name) {
  if (loaded.has(name)) return loaded.get(name);
  let source = fs.readFileSync(path.resolve(here,'../entry/src/main/ets',name+'.ets'),'utf8');
  // Exercise the real component event handlers without pretending to render ArkUI's declarative DSL.
  if (name === 'components/NativePlayer') {
    source = source.slice(0,source.search(/^\s+@Builder\b/m))+'\n}';
    source = source.replace(/@Component\s+/g,'').replace(/@(Prop|State)\b/g,'')
      .replace(/@(Watch|StorageProp)\([^)]*\)/g,'').replace('export struct NativePlayer','export class NativePlayer');
  }
  const {outputText} = ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}});
  const module = {exports:{}};
  const localRequire = id => id === '@kit.NetworkKit' ? {http} : id === '@kit.ArkUI' ? {window:windowApi} : id === '@kit.AudioKit' ? {audio:audioApi} : id === '@mpv-ohos/mpv-arkts' ? mpvApi : load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));
  vm.runInThisContext(`(function(require,module,exports){${outputText}\n})`)(localRequire,module,module.exports);
  loaded.set(name,module.exports); return module.exports;
}
const models = load('model/Models');
const {Api,collectionPayload,collectionLines} = load('services/Api');
const {AdFilter,originalTime,filteredTime,validatePrepared,prepareNativeMedia} = load('services/AdFilter');
const {NativePlayback} = load('services/NativePlayback');
const {NativePlayer:NativePlayerHandlers} = load('components/NativePlayer');
const {SystemMediaVolume,PlayerBrightness,volumeFromSwipe,brightnessFromSwipe} = load('services/PlayerDeviceControls');
const {updateAvoidAreas,applySystemBars} = load('design/WindowStyle');
const source = (type='wtv') => ({id:'test',name:'测试源',url:'https://source.example/api.php/provide/vod/?token=keep',type,apiKey:'',enabled:true});
const fixture = name => JSON.parse(fs.readFileSync(path.join(here,'fixtures',name+'.json'),'utf8'));

test('URL validation rejects credentials, scripts, whitespace and empty hosts',() => {
  for (const value of ['javascript:alert(1)','https://user:pass@example.com/a','https:///a','https://example.com/ bad','//example.com','file:///a']) assert.equal(models.validUrl(value),false,value);
  assert.equal(models.validUrl('https://cdn.example/a.m3u8?token=a%20b'),true);
  assert.equal(models.validUrl('http://cdn.example/a',true),false);
});
test('query builder preserves credentials query and correctly replaces supplied keys',() => {
  assert.equal(models.withQuery('https://a.example/api?ac=list&token=x','ac','detail'),'https://a.example/api?ac=detail&token=x');
  assert.equal(models.withQuery('https://a.example/api#fragment','wd','三 体'),'https://a.example/api?wd=%E4%B8%89%20%E4%BD%93');
});
test('parser templates encode a complete source URL once',() => {
  const video = 'https://v.example/a?x=1&y=你好';
  for (const endpoint of ['https://p.example/?url={url}','https://p.example/?url=','https://p.example/?v=']) {
    const value = models.parserRequest(endpoint,video); assert.ok(value.endsWith(encodeURIComponent(video)));
  }
  const value = new URL(models.parserRequest('https://p.example/api?token=keep',video));
  assert.equal(value.searchParams.get('token'),'keep'); assert.equal(value.searchParams.get('url'),video);
});
test('MacCMS JSON accepts wrapped lists and rejects service errors',() => {
  assert.equal(collectionPayload('{"code":1,"data":{"list":[{"vod_id":2}]}}').list[0].vod_id,2);
  assert.throws(() => collectionPayload('{"code":0,"list":[]}'));
  assert.throws(() => collectionPayload('{"ok":true}'));
});
test('MacCMS XML preserves CDATA groups and rejects DTD or entity declarations',() => {
  const xml = '<rss><list pagecount="2"><video><id>1</id><name>甲 &amp; 乙</name><dl><dd flag="高清"><![CDATA[第1集$https://v.example/a.m3u8?x=1&y=2#第2集$https://v.example/b.mp4]]></dd></dl></video></list></rss>';
  const result = collectionPayload(xml); assert.equal(result.pagecount,'2'); assert.equal(result.list[0].vod_name,'甲 & 乙');
  const lines = collectionLines(result.list[0]); assert.equal(lines.length,1); assert.equal(lines[0].episodes.length,2);
  assert.equal(lines[0].episodes[0].url,'https://v.example/a.m3u8?x=1&y=2');
  assert.throws(() => collectionPayload('<!DOCTYPE rss SYSTEM "file:///a"><list></list>'));
});
test('collection lines preserve order and discard non-HTTP episode URLs',() => {
  const lines = collectionLines({vod_play_from:'一$$$二',vod_play_url:'1$https://v.example/a.mp4#bad$javascript:alert(1)$$$2$https://v.example/b.m3u8'});
  assert.equal(lines.length,2); assert.equal(lines[0].episodes.length,1); assert.equal(lines[1].name,'二');
});
test('WTV search and detail normalize actual production responses',async () => {
  const api = new Api(), calls = []; api.json = async url => {calls.push(url);return url.includes('/api/search') ? fixture('site-search') : fixture('site-detail');};
  const s = {...source(),url:'https://wtv.example',type:'wtv:default'};
  const results = await api.search(s,'三体','tencent'); assert.equal(results.results.length,6);
  const detail = await api.detail(s,results.results[0]); assert.equal(detail.playlists[0].episodes.length,30);
  assert.ok(detail.episodes.every(e => e.episode_type === 'main'));
  assert.equal(detail.playlists.reduce((sum,line)=>sum+line.episodes.length,0),40);
  assert.ok(detail.series.cover.startsWith('https://image.tmdb.org/'));
  assert.ok(calls[1].includes('source=default')); assert.ok(calls[1].includes('path=%2Fv1%2Ftencent'));
});
test('MacCMS search pagination and detail keep query parameters and selected ID',async () => {
  const api = new Api(),calls=[];
  api.text = async url => {calls.push(url);return JSON.stringify({code:1,list:[{vod_id:7,vod_name:'片名',vod_play_url:'1$https://v.example/a.mp4'}],pagecount:3});};
  const s = source('maccms'),result = await api.search(s,'片名','tencent',2);
  assert.equal(result.hasMore,true); assert.equal(result.results[0].id,'7');
  assert.equal(new URL(calls[0]).searchParams.get('pg'),'2'); assert.equal(new URL(calls[0]).searchParams.get('token'),'keep');
  const detail = await api.detail(s,result.results[0]); assert.equal(detail.episodes.length,1);
  assert.equal(new URL(calls[1]).searchParams.get('ids'),'7');
});
test('VideoSearch detail never follows a response-supplied different host',async () => {
  const api = new Api(); let called = false; api.json = async () => {called=true;return {};};
  await assert.rejects(api.detail(source('videosearch'),{...models.emptyMovie(),detail_url:'//evil.example/v1/a'}),/详情路径/);
  assert.equal(called,false);
});
test('site sync never labels HTML parser endpoints as JSON resolvers',async () => {
  const api = new Api(); api.json = async () => fixture('site-config');
  const config = await api.siteConfig('https://wtv.example'); assert.equal(config.searches.length,5);
  assert.ok(config.parsers.every(p => p.type === 'web'));
  assert.ok(config.searches.every(s => s.url === 'https://wtv.example' && !s.apiKey));
});
test('native direct mode accepts media links and gives actionable error for web pages',async () => {
  const api = new Api(), parser = {...source(),type:'direct'};
  assert.equal(await api.resolve('https://v.example/a.m3u8?token=1',parser),'https://v.example/a.m3u8?token=1');
  await assert.rejects(api.resolve('https://v.qq.com/x/cover/1.html',parser),/JSON/);
  await assert.rejects(api.resolve('https://v.example/a.mp4',{...parser,type:'web'}),/网页播放器/);
});
test('JSON resolution supports common response paths and signed extensionless media URLs',async () => {
  const api = new Api(),parser={...source(),type:'json',url:'https://parse.example/?url={url}'};
  for (const payload of [{url:'https://v.example/play?id=1'},{play_url:'https://v.example/a.mp4'},{playUrl:'https://v.example/a.mp4'},{data:{url:'https://v.example/a.m3u8'}}]) {
    api.text = async () => JSON.stringify(payload); const value = await api.resolve('https://v.qq.com/a.html',parser); assert.ok(value.startsWith('https://v.example/'));
  }
});
test('resolution rejects HTML, application errors and malicious media schemes',async () => {
  const api = new Api(),parser={...source(),type:'json'};
  for (const body of ['<html>please verify</html>','{"ok":false,"message":"失败"}','{"url":"javascript:alert(1)"}','{}']) {
    api.text = async () => body; await assert.rejects(api.resolve('https://v.example/page',parser));
  }
});
test('native HTTP request is bounded, disables redirects and always releases resources',async () => {
  requests = []; destroyed = 0; response={responseCode:200,result:'{"ok":true}'};
  const api = new Api(); await api.text('https://api.example/search','secret');
  assert.equal(requests[0].options.header.Authorization,'Bearer secret'); assert.equal(requests[0].options.maxRedirects,0);
  assert.equal(requests[0].options.maxLimit,6000000); assert.equal(destroyed,1);
  response={responseCode:502,result:'bad'}; await assert.rejects(api.text('https://api.example/search'),/502/); assert.equal(destroyed,2);
});

test('platform filter appears only for official sources, including old persisted settings',() => {
  for (const type of ['wtv','wtv:default','videosearch']) assert.equal(models.officialSearch(source(type)),true,type);
  for (const type of ['wtv:custom_changzhang','maccms']) assert.equal(models.officialSearch(source(type)),false,type);
  assert.equal(models.officialSearch({...source('wtv:official-2'),searchProtocol:'videosearch'}),true);
  assert.equal(models.officialSearch({...source('wtv:default'),searchProtocol:'maccms'}),false);
  assert.equal(models.officialSearch(undefined),false);
});
test('synced protocol metadata distinguishes official catalogue from resource sources',async () => {
  const api = new Api();api.json = async()=>fixture('site-config');
  const result=await api.siteConfig('https://wtv.example');
  assert.equal(models.officialSearch(result.searches[0]),true);
  assert.ok(result.searches.slice(1).every(s=>!models.officialSearch(s)));
});
test('resource search requests omit platform while official search sends chosen platform',async () => {
  const api=new Api(),calls=[]; api.json=async url=>{calls.push(url);return {results:[]};};
  await api.search(source('wtv:custom_changzhang'),'走马上任','tencent');
  await api.search(source('wtv:default'),'走马上任','youku');
  assert.equal(new URL(calls[0]).searchParams.has('platform'),false);
  assert.equal(new URL(calls[1]).searchParams.get('platform'),'youku');
});
test('episode labels preserve distinguishing full text and remove only repeated series prefixes',() => {
  assert.equal(models.episodeLabel({title:'走马上任 第01集'},'走马上任',0),'第01集');
  assert.equal(models.episodeLabel({title:'走马上任第十五集（导演加长版）'},'走马上任',14),'第十五集（导演加长版）');
  assert.equal(models.episodeLabel({title:'走马上任：幕后创作访谈完整版'},'走马上任',0),'幕后创作访谈完整版');
  assert.equal(models.episodeLabel({title:'ABC'},'A',0),'ABC');
  assert.equal(models.episodeLabel({title:''},'片名',2),'第 3 集');
});
test('HTML parser playback uses encoded URL without fetching it as JSON',async () => {
  const api=new Api();api.text=async()=>{throw new Error('should not fetch')};
  const video='https://v.example/watch?a=1&b=2';
  const result=await api.playback(video,{...source('web'),url:'https://parse.example/?url={url}'});
  assert.equal(result.kind,'web');assert.equal(new URL(result.url).searchParams.get('url'),video);
  assert.deepEqual(await api.playback(video,source('page')),{kind:'web',url:video});
  await assert.rejects(api.playback(video,{...source('web'),url:'javascript:alert(1)'}));
});
test('JSON and direct playback continue to use native video',async () => {
  const api=new Api();api.text=async()=>'{"url":"https://media.example/movie.m3u8"}';
  assert.equal((await api.playback('https://v.example/a',source('json'))).kind,'native');
  assert.deepEqual(await api.playback('https://media.example/a.mp4',source('direct')),{kind:'native',url:'https://media.example/a.mp4'});
});
test('web navigation rejects arbitrary app schemes and local file access',() => {
  for (const link of ['intent://ads','file:///private/key','javascript:alert(1)','data:text/html,test','https://u:p@host.example']) assert.equal(models.webNavigationAllowed(link),false);
  assert.equal(models.webNavigationAllowed('https://cdn.example/player'),true);
  assert.equal(models.webNavigationAllowed('about:blank',false),true);
  assert.equal(models.webNavigationAllowed('about:blank',true),false);
});
test('ad timeline conversion preserves source position when filtering changes',() => {
  const ranges=[{start:10,end:20},{start:40,end:50}];
  assert.equal(originalTime(10,ranges),20);assert.equal(originalTime(30,ranges),50);
  assert.equal(filteredTime(15,ranges),10);assert.equal(filteredTime(45,ranges),30);
  for(const original of [0,9,20,30,50,100]) assert.equal(originalTime(filteredTime(original,ranges),ranges),original);
});
test('prepared Crayon results validate ranges, expiry, mode and URL before native playback',() => {
  const value={url:'/api/player/media?token=x',relayMode:'playlist',expiresAt:Date.now()+3600000,filter:{originalDuration:100,removed:[{start:10,end:20}],reason:'filtered'}};
  assert.equal(validatePrepared(value,'https://crap.example/api/player/prepare').url,'https://crap.example/api/player/media?token=x');
  for(const bad of [
    {...value,url:'javascript:alert(1)'}, {...value,relayMode:'full'}, {...value,expiresAt:0},
    {...value,filter:{...value.filter,removed:[{start:20,end:15}]}},
    {...value,filter:{...value.filter,removed:[{start:10,end:20},{start:15,end:30}]}},
    {...value,filter:{...value.filter,reason:'no-match'}}
  ]) assert.throws(()=>validatePrepared(bad,'https://crap.example/api/player/prepare'));
});
test('ad preparation uses Crayon playlist-only POST and reports failures without pretending success',async () => {
  requests=[];destroyed=0;response={responseCode:200,result:JSON.stringify({url:'https://crap.example/api/player/media?token=x',relayMode:'playlist',filter:{originalDuration:100,removed:[],reason:'no-match'}})};
  const filter=new AdFilter();await filter.prepare('https://media.example/a.m3u8','https://crap.example/api/player/prepare');
  assert.equal(requests[0].options.method,'POST');assert.equal(requests[0].options.maxRedirects,0);
  assert.deepEqual(JSON.parse(requests[0].options.extraData),{url:'https://media.example/a.m3u8',blockAds:true,relayMode:'playlist'});
  assert.equal(destroyed,1);
  response={responseCode:503,result:'unavailable'};await assert.rejects(filter.prepare('https://media.example/a.m3u8','https://crap.example/api/player/prepare'),/HTTP 503/);
  assert.equal(destroyed,2);
});

test('immersive insets combine status, gesture and landscape cutout areas without fixed dimensions',() => {
  const oldStorage=globalThis.AppStorage,values=new Map();
  globalThis.AppStorage={setOrCreate:(k,v)=>values.set(k,v),get:k=>values.get(k)};
  const area=(top,bottom,left=0,right=0)=>({topRect:{height:top},bottomRect:{height:bottom},leftRect:{width:left},rightRect:{width:right}});
  try {
    updateAvoidAreas({getWindowAvoidArea:type=>[area(96,60),area(120,0,40,20),area(0,72)][type]});
    assert.equal(values.get('safeTopPx'),120);assert.equal(values.get('safeBottomPx'),72);
    assert.equal(values.get('safeLeftPx'),40);assert.equal(values.get('safeRightPx'),20);
    updateAvoidAreas({getWindowAvoidArea:type=>[area(0,0,0,0),area(0,0,92,0),area(0,40)][type]});
    assert.equal(values.get('safeTopPx'),0);assert.equal(values.get('safeLeftPx'),92);assert.equal(values.get('safeBottomPx'),40);
    updateAvoidAreas({getWindowAvoidArea:type=>[area(0,0),area(0,96,92),area(0,40)][type]});
    assert.equal(values.get('safeBottomPx'),96);
    updateAvoidAreas({getWindowAvoidArea:()=>{throw new Error('temporary window transition')}});
    assert.equal(values.get('safeLeftPx'),92);
  } finally {globalThis.AppStorage=oldStorage;}
});
test('transparent system bars keep contrast in light, dark and media fullscreen states',async () => {
  const oldStorage=globalThis.AppStorage,values=new Map(),calls=[];
  globalThis.AppStorage={setOrCreate:(k,v)=>values.set(k,v),get:k=>values.get(k)};
  const visibility=[];
  const win={setWindowSystemBarProperties:async data=>calls.push(data),setSpecificSystemBarEnabled:async(name,enabled)=>visibility.push({name,enabled})};
  try {
    await applySystemBars(win);assert.equal(calls.at(-1).statusBarContentColor,'#172C32');
    values.set('systemDark',true);await applySystemBars(win);assert.equal(calls.at(-1).statusBarContentColor,'#EDF5F4');
    values.set('systemDark',false);values.set('mediaFullscreen',true);await applySystemBars(win);assert.equal(calls.at(-1).statusBarContentColor,'#EDF5F4');
    values.set('mediaFullscreen',false);await applySystemBars(win,true);assert.equal(calls.at(-1).navigationBarContentColor,'#EDF5F4');
    assert.ok(calls.every(c=>c.statusBarColor==='#00000000' && c.navigationBarColor==='#00000000'));
    assert.deepEqual(visibility.slice(-2),[{name:'status',enabled:false},{name:'navigationIndicator',enabled:false}]);
    await applySystemBars(win,false);
    assert.deepEqual(visibility.slice(-2),[{name:'status',enabled:true},{name:'navigationIndicator',enabled:true}]);
  } finally {globalThis.AppStorage=oldStorage;}
});

test('HLS preparation rejection and timeouts preserve playable original URLs',async()=>{
  const original='https://cdn.example/index.m3u8?token=keep';
  for(const code of [403,503,'timeout','invalid result']){
    const plan=await prepareNativeMedia(original,true,'https://filter.example/api',{prepare:async()=>{throw new Error(String(code));}});
    assert.equal(plan.url,original);assert.equal(plan.originalUrl,original);assert.equal(plan.hls,true);assert.deepEqual(plan.ranges,[]);assert.match(plan.status,/本次未过滤/);
  }
});
test('no-match and unsupported playlists bypass the signed relay; actual cuts retain exact ranges',async()=>{
  const original='https://cdn.example/index.m3u8',removed=[{start:10,end:20}];
  for(const reason of ['no-match','unsupported','filtered']){
    const plan=await prepareNativeMedia(original,true,'https://filter.example/api',{prepare:async()=>({url:'https://filter.example/media?token=x',filter:{reason,originalDuration:100,removed:reason==='filtered'?removed:[]}})});
    assert.equal(plan.url,reason==='filtered'?'https://filter.example/media?token=x':original);
    assert.deepEqual(plan.ranges,reason==='filtered'?removed:[]);
  }
  let called=false;
  for(const [url,enabled] of [[original,false],['https://cdn.example/movie.mp4',true]]) await prepareNativeMedia(url,enabled,'bad',{prepare:async()=>{called=true;}});
  assert.equal(called,false);
});
const flush=async()=>{for(let i=0;i<12;i++) await Promise.resolve();};
const playbackEvents=()=>({prepared:()=>{},time:()=>{},playing:()=>{},buffering:()=>{},ended:()=>{},failed:()=>{}});
test('MPV waits for the requested file, carries HTTP headers and source-time resume, and controls volume/speed',async()=>{
  const player=new NativePlayback(),events=playbackEvents();let duration,time;
  events.prepared=value=>duration=value;events.time=value=>time=value;player.listen(events);
  player.load('https://filter.example/media?token=x',true,27.5,true);player.attach('surface-1');await flush();
  const p=nativePlayers.at(-1);
  assert.equal(p.volume,100,'default MPV gain leaves system media volume unattenuated');
  assert.equal(p.surface,'surface-1');assert.equal(p.media.start,27.5);assert.ok(p.media.httpHeaders.get('User-Agent').startsWith('WTV-Harmony/'));
  assert.equal(p.played,0);p.emit(8);assert.equal(p.played,1);assert.equal(duration,120);
  p.stream.position.emit(30);assert.equal(time,30);player.setCurrentTime(42.5);assert.equal(p.currentTime,42.5);
  player.setRate(1.5);assert.equal(p.speed,1.5);player.setVolume(1.8);assert.equal(p.volume,100);
  player.resize(1080,720);assert.equal(p.properties.get('ohos-surface-size'),'1080x720');
  player.clear();player.detach();assert.equal(p.destroyed,1);
});
test('MPV ignores old file events and prevents autoplay after a background pause',async()=>{
  const player=new NativePlayback();player.listen(playbackEvents());player.attach('surface-2');
  player.load('https://cdn.example/old.mp4',false);player.load('https://cdn.example/new.mp4',false,0,true);player.pause();
  const current=nativePlayers.at(-1);
  current.path='https://cdn.example/old.mp4';current.emit(8);current.emit(7);assert.equal(current.played,0);
  current.path='https://cdn.example/new.mp4';current.emit(8);assert.equal(current.played,0);
  player.start();assert.equal(current.played,1);player.detach();assert.equal(current.destroyed,1);
});
test('MPV open failures notify once and discard late time callbacks',async()=>{
  const player=new NativePlayback(),events=playbackEvents();let failures=0,ticks=0;
  events.failed=()=>failures++;events.time=()=>ticks++;player.listen(events);player.attach('surface-3');player.load('https://cdn.example/a.mp4',false);await flush();
  const p=nativePlayers.at(-1);
  p.emit(7,JSON.stringify({error:0,entryId:5}));p.emit(7,JSON.stringify({error:-13,entryId:4}));assert.equal(failures,0);
  p.emit(7,JSON.stringify({error:-13,entryId:5}));p.emit(7,JSON.stringify({error:-13,entryId:5}));p.stream.position.emit(2);await flush();
  assert.equal(failures,1);assert.equal(ticks,0);player.clear();player.detach();assert.equal(p.destroyed,1);
});

test('MPV surface callbacks discard destroyed surfaces and old core events',()=>{
  const player=new NativePlayback(),events=playbackEvents();let ticks=0;events.time=()=>ticks++;player.listen(events);
  player.load('https://cdn.example/a.m3u8',true);player.onSurfaceCreated('old-surface');const old=nativePlayers.at(-1);old.emit(8);
  player.onSurfaceCreated('new-surface');const current=nativePlayers.at(-1);
  player.onSurfaceDestroyed('old-surface');assert.equal(current.destroyed,0);assert.equal(old.destroyed,1);
  old.stream.position.emit(15);assert.equal(ticks,0);current.emit(8);current.stream.position.emit(20);assert.equal(ticks,1);
  player.onSurfaceChanged('new-surface',{surfaceWidth:1920,surfaceHeight:1080});assert.equal(current.properties.get('ohos-surface-size'),'1920x1080');
  player.onSurfaceDestroyed('new-surface');assert.equal(current.destroyed,1);
});
test('MPV playback completion reports once per play, including an explicit replay',()=>{
  const player=new NativePlayback(),events=playbackEvents();let endings=0;events.ended=()=>endings++;player.listen(events);
  player.load('https://cdn.example/a.mp4',false);player.onSurfaceCreated('surface-eof');const p=nativePlayers.at(-1);p.emit(8);
  p.stream.eof.emit(true);p.stream.eof.emit(true);assert.equal(endings,1);
  player.start();p.stream.eof.emit(true);assert.equal(endings,2);player.clear();player.detach();
});

test('volume gesture end and prompt timeout preserve the last numeric system volume command',t=>{
  t.mock.timers.enable({apis:['setTimeout']});
  const ui=new NativePlayerHandlers();ui.volumeReady=true;ui.volumeMin=0;ui.volumeMax=20;ui.volumeLevel=6;
  assert.equal(ui.volumeCommandIssued,false,'no volume command on mounting');
  ui.requestSystemVolume(12);assert.equal(ui.requestedVolume,12);assert.equal(ui.volumePanelVisible,true);
  ui.panEnd(true);t.mock.timers.tick(1300);
  assert.equal(ui.volumePanelVisible,false);assert.equal(ui.requestedVolume,12);
  assert.equal(ui.volumeCommandIssued,true,'prompt hiding must not remount or reset the command');
  t.mock.timers.tick(10000);assert.equal(ui.requestedVolume,12);
  ui.closeDeviceControls();assert.equal(ui.volumeCommandIssued,false);assert.equal(ui.requestedVolume,12);
});
test('repeated volume swipes replace prompt timers without injecting a zero or undefined command',t=>{
  t.mock.timers.enable({apis:['setTimeout']});
  const ui=new NativePlayerHandlers();ui.volumeReady=true;ui.volumeMin=0;ui.volumeMax=20;ui.volumeLevel=6;
  ui.requestSystemVolume(12);t.mock.timers.tick(1000);ui.requestSystemVolume(15);
  t.mock.timers.tick(300);assert.equal(ui.volumePanelVisible,true);assert.equal(ui.requestedVolume,15);
  t.mock.timers.tick(1000);assert.equal(ui.volumePanelVisible,false);assert.equal(ui.requestedVolume,15);
  ui.requestSystemVolume(99);assert.equal(ui.requestedVolume,20);
  ui.foreground=false;ui.closeDeviceControls();ui.requestSystemVolume(5);assert.equal(ui.requestedVolume,20);
});
test('play/pause button handlers update state even when the native stream callback is delayed',()=>{
  const ui=new NativePlayerHandlers(),events=playbackEvents();events.playing=value=>{ui.playing=value;ui.playbackChanged();};
  const player=ui.controller;player.listen(events);player.load('https://cdn.example/toggle.mp4',false);player.attach('surface-toggle');
  const core=nativePlayers.at(-1);let pauses=0;
  core.play=()=>core.played++;core.pause=()=>pauses++; // native commands do not synchronously emit stream events
  core.emit(8);assert.equal(ui.playing,true);
  ui.toggle();assert.equal(pauses,1);assert.equal(ui.playing,false);assert.equal(ui.visible,true);
  ui.toggle();assert.equal(ui.playing,true);assert.equal(core.played,2);
  core.stream.playing.emit(false);assert.equal(ui.playing,false,'native changes still reconcile button state');
  clearTimeout(ui.hideTimer);player.clear();player.detach();
});

test('vertical gestures use device volume range and clamp brightness without dim overlays',()=>{
  assert.equal(volumeFromSwipe(6,0,20,-80,200),16);
  assert.equal(volumeFromSwipe(6,0,20,999,200),0);
  assert.equal(volumeFromSwipe(6,0,20,-999,200),20);
  assert.equal(volumeFromSwipe(5,2,10,24,100),3);
  assert.equal(brightnessFromSwipe(0.5,-40,200),0.75);
  assert.equal(brightnessFromSwipe(0.5,999,200),0.05);
  assert.equal(brightnessFromSwipe(0.5,-999,0),1);
});
test('system media volume reads actual hardware changes and releases the exact listener',()=>{
  const control=new SystemMediaVolume(),changes=[];
  assert.equal(control.open(value=>changes.push(value)),true);
  assert.deepEqual(changes.at(-1),{level:6,min:0,max:20});
  deviceVolume.level=9;deviceVolume.max=30;deviceVolume.listeners.forEach(cb=>cb({volume:9}));
  assert.deepEqual(changes.at(-1),{level:9,min:0,max:30});
  control.open(value=>changes.push(value));assert.equal(deviceVolume.listeners.size,1);
  control.close();assert.equal(deviceVolume.listeners.size,0);assert.equal(control.refresh(),false);
  deviceVolume.level=6;deviceVolume.max=20;
});
test('unavailable system volume does not leave a listener or invent a volume range',()=>{
  const control=new SystemMediaVolume();deviceVolume.fail=true;
  assert.equal(control.open(()=>assert.fail('invalid snapshot')),false);assert.equal(deviceVolume.listeners.size,0);
  deviceVolume.fail=false;deviceVolume.max=0;
  assert.equal(control.open(()=>assert.fail('invalid range')),false);assert.equal(deviceVolume.listeners.size,0);
  deviceVolume.max=20;
});
const fakeWindow=(initial=-1)=>({value:initial,writes:[],getWindowProperties(){return {brightness:this.value};},async setWindowBrightness(value){this.value=value;this.writes.push(value);}});
test('window brightness coalesces changes, follows system, and restores the original on leaving',async()=>{
  const win=fakeWindow(),control=new PlayerBrightness();
  assert.equal(await control.open(win,()=>assert.fail('window failure')),-1);
  control.set(.6);control.set(.75);control.flush();await flush();assert.deepEqual(win.writes,[.75]);
  assert.equal(control.followSystem(),true);await flush();assert.equal(win.value,-1);
  control.set(.8);control.flush();await flush();control.close();await flush();
  assert.deepEqual(win.writes,[.75,-1,.8,-1]);assert.equal(control.set(.9),false);
});
test('leaving cancels pending brightness requests before another player reads its baseline',async()=>{
  const win=fakeWindow(.35),first=new PlayerBrightness(),second=new PlayerBrightness();
  await first.open(win,()=>assert.fail());first.set(.9);first.flush();first.close();
  assert.equal(await second.open(win,()=>assert.fail()),.35);assert.deepEqual(win.writes,[.35]);
  second.set(.8);second.close();await flush();assert.equal(win.value,.35);
});
test('window brightness failures report unavailable and do not restore an unread baseline',async()=>{
  let failures=0;const control=new PlayerBrightness();
  assert.equal(await control.open({getWindowProperties(){throw Error('window gone');},setWindowBrightness(){assert.fail();}},()=>failures++),undefined);
  assert.equal(control.set(.7),false);control.close();await flush();assert.equal(failures,1);
  const win=fakeWindow(.3);win.setWindowBrightness=async()=>{throw Error('background');};
  await control.open(win,()=>failures++);control.set(.8);control.flush();await flush();assert.equal(failures,2);
  control.close();await flush();
});
