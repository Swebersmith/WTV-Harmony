import { http } from '@kit.NetworkKit';
import { validUrl } from '../model/Models';

export interface AdRange { start: number; end: number; }
export interface AdReport { originalDuration: number; removed: AdRange[]; reason: string; }
export interface PreparedMedia { url: string; filter: AdReport; expiresAt?: number; relayMode?: string; }
interface PrepareRequest { url: string; blockAds: boolean; relayMode: string; }

// Crayon's conservative HLS classifier runs on its existing prepare service.
// Native Video still handles playback. The response supplies the exact removed time ranges.
export function originalTime(filtered: number, ranges: AdRange[]): number {
  let result = Math.max(0,filtered);
  for (const range of ranges) { if (result >= range.start) result += range.end-range.start; else break; }
  return result;
}
export function filteredTime(original: number, ranges: AdRange[]): number {
  let removed = 0;
  for (const range of ranges) {
    if (original <= range.start) break;
    removed += Math.min(original,range.end)-range.start;
  }
  return Math.max(0,original-removed);
}
export function validatePrepared(data: PreparedMedia, service: string): PreparedMedia {
  if (!data || !data.filter || !Array.isArray(data.filter.removed) || !Number.isFinite(data.filter.originalDuration) || data.filter.originalDuration < 0) throw new Error('去插播服务返回的清单无效');
  // Crayon returns absolute URLs; also accept a same-origin /api/player/media path.
  if (data.url?.startsWith('/') && !data.url.startsWith('//')) data.url = service.match(/^https:\/\/[^/]+/)?.[0] + data.url;
  if (!validUrl(data.url,true) || !['filtered','no-match','unsupported'].includes(data.filter.reason) || data.relayMode !== 'playlist') throw new Error('去插播服务返回的媒体地址或模式无效');
  let end = 0;
  for (const range of data.filter.removed) {
    if (!Number.isFinite(range.start) || !Number.isFinite(range.end) || range.start < end || range.end <= range.start || range.end > data.filter.originalDuration) throw new Error('去插播时间范围无效');
    end = range.end;
  }
  if (data.filter.reason !== 'filtered' && data.filter.removed.length) throw new Error('去插播结果与时间范围不一致');
  if (data.expiresAt !== undefined && (!Number.isFinite(data.expiresAt) || data.expiresAt < Date.now()+60000)) throw new Error('去插播清单已过期，请重试');
  return data;
}
export class AdFilter implements HlsPreparer {
  private active?: http.HttpRequest;
  cancel(): void { this.active?.destroy(); this.active = undefined; }
  async prepare(url: string, service: string): Promise<PreparedMedia> {
    if (!validUrl(url) || !validUrl(service,true)) throw new Error('请填写有效的 HTTPS 去插播服务地址');
    const request = http.createHttp(); this.active = request;
    try {
      const body: PrepareRequest = {url,blockAds:true,relayMode:'playlist'};
      const response = await request.request(service,{method:http.RequestMethod.POST,
        header:{'Content-Type':'application/json',Accept:'application/json','User-Agent':'WTV-Harmony/1.3.0'},extraData:JSON.stringify(body),
        expectDataType:http.HttpDataType.STRING,maxLimit:1_000_000,maxRedirects:0,connectTimeout:5000,readTimeout:12000,usingCache:false});
      if (response.responseCode !== 200) throw new Error(`去插播服务返回 HTTP ${response.responseCode}`);
      return validatePrepared(JSON.parse(response.result as string) as PreparedMedia,service);
    } finally { if (this.active === request) this.active = undefined; request.destroy(); }
  }
}

export interface NativeMediaPlan {
  url: string;
  originalUrl: string;
  hls: boolean;
  ranges: AdRange[];
  status: string;
}
export interface HlsPreparer { prepare(url: string, service: string): Promise<PreparedMedia>; }

// Filtering is optional. A preparation/network failure must never block direct playback.
export async function prepareNativeMedia(url: string, enabled: boolean, service: string, filter: HlsPreparer): Promise<NativeMediaPlan> {
  const hls = /\.m3u8(?:[?#]|$)/i.test(url);
  const plan: NativeMediaPlan = {url,originalUrl:url,hls,ranges:[],status:enabled ? '当前格式未启用 HLS 插播过滤' : '去插播已关闭'};
  if (!enabled || !hls) return plan;
  try {
    const prepared = await filter.prepare(url,service);
    if (prepared.filter.reason === 'filtered' && prepared.filter.removed.length > 0) {
      plan.url = prepared.url; plan.ranges = prepared.filter.removed;
      const removed = plan.ranges.reduce((sum: number,range: AdRange): number => sum+range.end-range.start,0);
      plan.status = `已过滤 ${removed.toFixed(1)} 秒插播`;
    } else {
      // No useful change: retain the source, its CDN path and native format detection.
      plan.status = prepared.filter.reason === 'unsupported' ? '当前清单保留原时间轴 · 直连播放' : '未识别到插播 · 直连播放';
    }
  } catch { plan.status = '去插播暂不可用 · 已恢复直连，本次未过滤'; }
  return plan;
}
