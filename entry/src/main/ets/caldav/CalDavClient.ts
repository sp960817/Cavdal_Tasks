import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import util from '@ohos.util';
import { CalendarSource, TodoTask } from '../model/TaskModels';
import { VTodoCodec } from './VTodoCodec';
import { CalendarObjectResponse, XmlHelpers } from './XmlHelpers';
import { utf8Bytes } from '../utils/TextCodec';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CavdalHTTP';

function errorText(err: Object): string {
  try {
    return JSON.stringify(err);
  } catch (_jsonErr) {
    return `${err}`;
  }
}

export interface CalDavCredentials {
  serverUrl: string;
  username: string;
  password: string;
}

export interface PutResult {
  ok: boolean;
  etag: string;
  status: number;
  message: string;
}

function ensureSlash(url: string): string {
  return url.endsWith('/') ? url : `${url}/`;
}

function joinUrl(base: string, href: string): string {
  if (href.startsWith('http://') || href.startsWith('https://')) {
    return href;
  }
  if (href.startsWith('/')) {
    const match = /^(https?:\/\/[^/]+)/i.exec(base);
    return match === null ? href : `${match[1]}${href}`;
  }
  return ensureSlash(base) + href;
}

function headerValue(headers: Object, key: string): string {
  const record = headers as Record<string, Object>;
  const wanted = key.toLowerCase();
  const keys = Object.keys(record);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === wanted) {
      const value = record[keys[i]];
      if (typeof value === 'string') {
        return value;
      }
      if (Array.isArray(value) && value.length > 0) {
        return `${value[0]}`;
      }
      return `${value}`;
    }
  }
  return '';
}

export class CalDavClient {
  private authHeader: string;

  constructor(private credentials: CalDavCredentials) {
    const helper = new util.Base64Helper();
    this.authHeader = `Basic ${helper.encodeToStringSync(utf8Bytes(`${credentials.username}:${credentials.password}`))}`;
  }

  private async request(url: string, method: string, body: string = '', extraHeaders: Record<string, string> = {}): Promise<http.HttpResponse> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Authorization': this.authHeader,
        'Content-Type': 'application/xml; charset=utf-8',
        'Accept': 'application/xml,text/calendar,*/*'
      };
      const headerKeys = Object.keys(extraHeaders);
      for (let i = 0; i < headerKeys.length; i++) {
        headers[headerKeys[i]] = extraHeaders[headerKeys[i]];
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s %{public}s', method, url);
      let response: http.HttpResponse;
      if (body.length > 0) {
        response = await request.request(url, {
          method: method as http.RequestMethod,
          header: headers,
          extraData: body,
          expectDataType: http.HttpDataType.STRING,
          readTimeout: 30000,
          connectTimeout: 30000
        });
      } else {
        response = await request.request(url, {
          method: method as http.RequestMethod,
          header: headers,
          expectDataType: http.HttpDataType.STRING,
          readTimeout: 30000,
          connectTimeout: 30000
        });
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, '-> %{public}d %{public}s', Number(response.responseCode), url);
      return response;
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Request failed %{public}s %{public}s err=%{public}s', method, url, errorText(err));
      throw new Error(`${method} ${url} failed: ${errorText(err)}`);
    } finally {
      request.destroy();
    }
  }

  async discoverCalendars(): Promise<CalendarSource[]> {
    const root = ensureSlash(this.credentials.serverUrl);
    const wellKnown = joinUrl(root, '/.well-known/caldav');
    let principalXml = '';
    try {
      const wellKnownResponse = await this.request(wellKnown, 'PROPFIND', XmlHelpers.propfindCurrentUserPrincipal(), { Depth: '0' });
      principalXml = `${wellKnownResponse.result}`;
    } catch (_err) {
      const rootResponse = await this.request(root, 'PROPFIND', XmlHelpers.propfindCurrentUserPrincipal(), { Depth: '0' });
      principalXml = `${rootResponse.result}`;
    }
    const principalHref = XmlHelpers.currentUserPrincipal(principalXml);
    const principalUrl = principalHref.length > 0 ? joinUrl(root, principalHref) : root;
    const homeResponse = await this.request(principalUrl, 'PROPFIND', XmlHelpers.propfindCalendarHomeSet(), { Depth: '0' });
    const homeHref = XmlHelpers.calendarHomeSet(`${homeResponse.result}`);
    const homeUrl = homeHref.length > 0 ? joinUrl(root, homeHref) : root;
    const calendarsResponse = await this.request(homeUrl, 'PROPFIND', XmlHelpers.propfindCalendars(), { Depth: '1' });
    return XmlHelpers.calendars(`${calendarsResponse.result}`);
  }

  async fetchTodos(calendarHref: string): Promise<TodoTask[]> {
    const calendarUrl = joinUrl(this.credentials.serverUrl, calendarHref);
    // 优先使用 REPORT (calendar-query)，若不支持则降级为 PROPFIND
    let response: http.HttpResponse;
    try {
      response = await this.request(calendarUrl, 'REPORT', XmlHelpers.reportPendingTodos(), { Depth: '1' });
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'REPORT failed fallback to PROPFIND err=%{public}s', `${err}`);
      response = await this.request(calendarUrl, 'PROPFIND', XmlHelpers.propfindTodos(), { Depth: '1' });
    }
    const objects: CalendarObjectResponse[] = XmlHelpers.calendarObjects(`${response.result}`);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'fetchTodos parsed %{public}d objects', objects.length);
    const tasks: TodoTask[] = [];
    for (let i = 0; i < objects.length; i++) {
      const task = VTodoCodec.toTask(objects[i].calendarData, objects[i].href, calendarHref, objects[i].etag);
      if (task !== undefined) {
        tasks.push(task);
      }
    }
    return tasks;
  }

  async deleteTask(task: TodoTask): Promise<PutResult> {
    const target = joinUrl(this.credentials.serverUrl, task.href);
    const headers: Record<string, string> = {};
    if (task.etag.length > 0) {
      headers['If-Match'] = task.etag;
    }
    const response = await this.request(target, 'DELETE', '', headers);
    const status = Number(response.responseCode);
    const ok = status >= 200 && status < 300;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'DELETE %{public}s -> %{public}d ok=%{public}s', target, status, `${ok}`);
    return {
      ok,
      etag: '',
      status,
      message: `${response.result}`
    };
  }

  async putTask(task: TodoTask, ignoreEtag: boolean = false): Promise<PutResult> {
    const href = task.href.length > 0 ? task.href : `${ensureSlash(task.calendarHref)}${encodeURIComponent(task.uid)}.ics`;
    const target = joinUrl(this.credentials.serverUrl, href);
    const headers: Record<string, string> = {
      'Content-Type': 'text/calendar; charset=utf-8'
    };
    if (!ignoreEtag && task.etag.length > 0) {
      headers['If-Match'] = task.etag;
    } else if (task.href.length === 0) {
      headers['If-None-Match'] = '*';
    }
    const response = await this.request(target, 'PUT', task.rawIcs, headers);
    const status = Number(response.responseCode);
    const etag = headerValue(response.header, 'etag');
    hilog.info(LOG_DOMAIN, LOG_TAG, 'PUT %{public}s uid=%{public}s -> %{public}d etag=%{public}s', target, task.uid, status, etag);
    // When successful and the task didn't have a href yet, persist the one we used
    if (status >= 200 && status < 300 && task.href.length === 0) {
      task.href = href;
    }
    return {
      ok: status >= 200 && status < 300,
      etag,
      status,
      message: `${response.result}`
    };
  }
}
