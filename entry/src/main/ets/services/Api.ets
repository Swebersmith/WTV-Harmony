import { http } from '@kit.NetworkKit';
import { Endpoint, Movie, Episode, Playlist, Detail, SearchResult, PlaybackTarget, validUrl, mediaUrl, clean, withQuery, parserRequest, officialSearch } from '../model/Models';

// Explicit wire types keep all third-party JSON outside the UI model.
interface WireMovie {
  id?: string | number; title?: string; platform?: string; year?: string | number;
  cover?: string; poster_url?: string; overview?: string; remarks?: string;
  url?: string; detail_url?: string; vod_id?: string | number; vod_name?: string;
  vod_pic?: string; vod_year?: string | number; vod_content?: string; vod_remarks?: string;
  vod_play_from?: string; vod_play_url?: string;
}
interface Payload {
  ok?: boolean; code?: string | number; message?: string; results?: WireMovie[];
  list?: WireMovie[]; data?: Payload; pagecount?: string | number; has_more?: boolean;
  partial?: boolean; series?: WireMovie; episodes?: Episode[]; playlists?: Playlist[];
  url?: string; play_url?: string; playUrl?: string;
  searches?: Endpoint[]; parsers?: Endpoint[];
}
interface RequestHeaders { Accept: string; Authorization?: string; }
export interface SiteConfig { searches: Endpoint[]; parsers: Endpoint[]; }

function root(value: string): string { return value.replace(/\/+$/,''); }
function movie(w: WireMovie, source: Endpoint): Movie {
  const id = String(w.id ?? w.vod_id ?? '');
  const collection = source.type === 'maccms';
  return {
    id,title:clean(w.title || w.vod_name || '未命名影片'),platform:w.platform || (collection ? 'resource' : ''),
    year:String(w.year ?? w.vod_year ?? ''),cover:w.cover || w.poster_url || w.vod_pic || '',
    overview:clean(w.overview || w.vod_content || ''),remarks:clean(w.remarks || w.vod_remarks || ''),
    url:w.url || '',detail_url:w.detail_url || (collection ? `/collection/${id}` : ''),sourceId:source.id
  };
}
function decodeXml(value: string): string {
  return value.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1').replace(/&amp;/g,'&')
    .replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&apos;/g,"'")
    .replace(/&#(x[a-f\d]+|\d+);/gi,(match: string,code: string): string => {
      const point = code.toLowerCase().startsWith('x') ? parseInt(code.slice(1),16) : Number(code);
      return point > 0 && point <= 0x10FFFF ? String.fromCodePoint(point) : match;
    });
}
function tag(xml: string, name: string): string {
  const result = xml.match(new RegExp(`<${name}\\b[^>]*>([\\s\\S]*?)<\\/${name}>`,'i'));
  return result ? decodeXml(result[1]).trim() : '';
}
export function collectionPayload(text: string): Payload {
  const input = text.replace(/^\uFEFF/,'').trim();
  if (!input.startsWith('<')) {
    const data = JSON.parse(input) as Payload;
    if (data.ok === false || (data.code !== undefined && ![1,200,'1','200'].includes(data.code))) throw new Error('资源站返回错误');
    const result = data.list ? data : data.data;
    if (!result || !Array.isArray(result.list)) throw new Error('不是兼容的 MacCMS JSON 列表');
    return result;
  }
  if (/<!DOCTYPE|<!ENTITY/i.test(input) || !/<list\b/i.test(input)) throw new Error('不是兼容的采集 XML');
  const items: WireMovie[] = [];
  const blocks = input.match(/<video\b[^>]*>[\s\S]*?<\/video>/gi) || [];
  for (const block of blocks.slice(0,100)) {
    const names: string[] = [], groups: string[] = [];
    const lines = block.match(/<dd\b[^>]*>[\s\S]*?<\/dd>/gi) || [];
    for (const line of lines.slice(0,30)) {
      names.push(decodeXml(line.match(/flag=["']([^"']*)["']/i)?.[1] || `线路 ${names.length+1}`));
      groups.push(decodeXml(line.replace(/^<dd\b[^>]*>/i,'').replace(/<\/dd>$/i,'')));
    }
    items.push({vod_id:tag(block,'id'),vod_name:tag(block,'name'),vod_pic:tag(block,'pic'),vod_year:tag(block,'year'),
      vod_content:tag(block,'des'),vod_remarks:tag(block,'note'),vod_play_from:names.join('$$$'),vod_play_url:groups.join('$$$')});
  }
  const count = input.match(/\bpagecount=["'](\d+)["']/i)?.[1] || '1';
  return {list:items,pagecount:count};
}
export function collectionLines(w: WireMovie): Playlist[] {
  const names = (w.vod_play_from || '').split('$$$');
  return (w.vod_play_url || '').split('$$$').slice(0,30).map((group: string, line: number): Playlist => {
    const episodes: Episode[] = [];
    for (const entry of group.split('#').slice(0,3000)) {
      const split = entry.indexOf('$');
      const url = (split < 0 ? entry : entry.slice(split+1)).trim();
      if (validUrl(url)) episodes.push({title:clean(split < 0 ? `第 ${episodes.length+1} 集` : entry.slice(0,split)),url,episode_type:'main'});
    }
    return {id:String(line),name:clean(names[line] || `线路 ${line+1}`),episodes};
  }).filter((line: Playlist): boolean => line.episodes.length > 0);
}

export class Api {
  private active: http.HttpRequest[] = [];
  cancel(): void { for (const request of this.active) request.destroy(); this.active = []; }
  async text(url: string, token: string = ''): Promise<string> {
    if (!validUrl(url)) throw new Error('接口地址必须是完整的 HTTP(S) 地址');
    const request = http.createHttp();
    this.active.push(request);
    try {
      const headers: RequestHeaders = {Accept:'application/json, application/xml, text/xml, */*'};
      if (token) headers.Authorization = `Bearer ${token}`;
      const response = await request.request(url,{
        method:http.RequestMethod.GET,header:headers,expectDataType:http.HttpDataType.STRING,
        connectTimeout:12000,readTimeout:45000,maxLimit:6_000_000,usingCache:false,maxRedirects:0
      });
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`接口返回 HTTP ${response.responseCode}`);
      return response.result as string;
    } finally {
      this.active = this.active.filter((item: http.HttpRequest): boolean => item !== request);
      request.destroy();
    }
  }
  async json(url: string, token: string = ''): Promise<Payload> {
    const text = await this.text(url,token);
    if (text.trim().startsWith('<')) throw new Error('接口返回网页，需要 JSON API');
    const result = JSON.parse(text) as Payload;
    if (result.ok === false) throw new Error(result.message || '接口返回失败');
    return result;
  }
  async siteConfig(site: string): Promise<SiteConfig> {
    const result = await this.json(`${root(site)}/api/config`);
    const searches: Endpoint[] = (result.searches || []).map((source: Endpoint): Endpoint => ({
      id:`site-${source.id}`,name:source.name,url:root(site),type:`wtv:${source.id}`,searchProtocol:source.type,apiKey:'',enabled:true
    }));
    // Preserve HTML parser identity so playback dispatches to ArkWeb rather than the native decoder.
    const parsers: Endpoint[] = (result.parsers || []).map((source: Endpoint): Endpoint => ({
      id:`site-${source.id}`,name:source.name,url:source.url,type:'web',apiKey:'',enabled:true
    }));
    return {searches,parsers};
  }
  async search(source: Endpoint, query: string, platform: string, page: number = 1): Promise<SearchResult> {
    let url = '';
    if (source.type.startsWith('wtv')) {
      url = `${root(source.url)}/api/search?q=${encodeURIComponent(query)}&page=${page}&source=${encodeURIComponent(source.type.split(':')[1] || 'default')}`;
      if (officialSearch(source)) url = withQuery(url,'platform',platform);
    } else if (source.type === 'maccms') {
      url = withQuery(withQuery(withQuery(source.url,'ac','detail'),'wd',query),'pg',String(page));
    } else {
      url = `${root(source.url)}/v1/${platform}/search?q=${encodeURIComponent(query)}&view=series&limit=12`;
    }
    const data = source.type === 'maccms' ? collectionPayload(await this.text(url,source.apiKey)) : await this.json(url,source.apiKey);
    return {results:(data.results || data.list || []).slice(0,100).map((item: WireMovie): Movie => movie(item,source)),
      hasMore:data.has_more === true || page < Number(data.pagecount || 1),partial:data.partial === true};
  }
  async detail(source: Endpoint, item: Movie): Promise<Detail> {
    let data: Payload;
    if (source.type === 'maccms') {
      data = collectionPayload(await this.text(withQuery(withQuery(source.url,'ac','detail'),'ids',item.id),source.apiKey));
      const selected = (data.list || []).find((row: WireMovie): boolean => String(row.vod_id) === item.id);
      if (!selected) throw new Error('资源站没有返回这部影片');
      const playlists = collectionLines(selected);
      if (!playlists.length) throw new Error('影片没有可用选集');
      return {series:movie(selected,source),playlists,episodes:playlists[0].episodes};
    }
    if (source.type.startsWith('wtv')) {
      data = await this.json(`${root(source.url)}/api/detail?path=${encodeURIComponent(item.detail_url)}&source=${encodeURIComponent(source.type.split(':')[1] || 'default')}`,source.apiKey);
    } else {
      // Bind detail requests to the configured host; reject protocol-relative or absolute detail paths.
      if (!/^\/v1\/(tencent|iqiyi|youku|mango|bilibili)\/series\/[a-zA-Z0-9_-]+(?:\?[^#]*)?$/.test(item.detail_url)) throw new Error('详情路径不符合 VideoSearch 协议');
      data = await this.json(root(source.url)+item.detail_url,source.apiKey);
    }
    const playlists = (data.playlists || []).map((line: Playlist): Playlist => ({
      id:line.id,name:clean(line.name),episodes:this.episodes(line.episodes)
    })).filter((line: Playlist): boolean => line.episodes.length > 0);
    const episodes = this.episodes(data.episodes || []);
    if (!playlists.length && episodes.length) {
      const main = episodes.filter((episode: Episode): boolean => !episode.episode_type || episode.episode_type === 'main');
      const extras = episodes.filter((episode: Episode): boolean => !!episode.episode_type && episode.episode_type !== 'main');
      if (main.length) playlists.push({id:'main',name:`正片 · ${main.length} 集`,episodes:main});
      if (extras.length) playlists.push({id:'extras',name:`预告与花絮 · ${extras.length}`,episodes:extras});
    }
    if (!playlists.length && validUrl(item.url)) playlists.push({id:'link',name:'影片链接',episodes:[{title:item.title,url:item.url}]});
    if (!playlists.length) throw new Error('没有可播放的选集');
    return {series:data.series ? movie(data.series,source) : item,playlists,episodes:playlists[0].episodes};
  }
  private episodes(list: Episode[]): Episode[] {
    const usable = list.filter((episode: Episode): boolean => validUrl(episode.url));
    return usable.slice(0,3000);
  }
  async playback(source: string, parser: Endpoint): Promise<PlaybackTarget> {
    if (!validUrl(source)) throw new Error('请输入完整的视频链接');
    if (parser.type === 'web' || parser.type === 'page') {
      const url = parser.type === 'page' ? source : parserRequest(parser.url,source);
      if (!validUrl(url) || (parser.type === 'web' && !validUrl(parser.url,true))) throw new Error('网页播放器地址无效');
      return {kind:'web',url};
    }
    return {kind:'native',url:await this.resolve(source,parser)};
  }
  async resolve(source: string, parser: Endpoint): Promise<string> {
    if (!validUrl(source)) throw new Error('请输入完整的视频链接');
    if (parser.type === 'direct') {
      if (!mediaUrl(source)) throw new Error('当前是影片网页链接。请选择 JSON 解析接口，或使用 MP4 / M3U8 媒体直链');
      return source;
    }
    if (parser.type === 'web') throw new Error('该线路返回网页播放器，不能由原生播放器使用。请添加返回媒体 URL 的 JSON 解析接口');
    const url = parserRequest(parser.url,source);
    const body = await this.text(url,parser.apiKey);
    if (body.trim().startsWith('<')) throw new Error('解析接口返回了 HTML 网页，请改用 JSON 直链接口');
    const data = JSON.parse(body) as Payload;
    if (data.ok === false) throw new Error(data.message || '解析失败');
    const resolved = data.url || data.play_url || data.playUrl || data.data?.url || data.data?.play_url || data.data?.playUrl || '';
    if (!validUrl(resolved)) throw new Error('解析结果没有有效媒体地址，支持 url、play_url、playUrl 及 data 下的同名字段');
    // JSON resolver is authoritative: signed media URLs need not have a file extension.
    return resolved;
  }
}
