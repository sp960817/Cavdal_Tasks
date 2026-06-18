import { CalendarSource } from '../model/TaskModels';

export interface CalendarObjectResponse {
  href: string;
  etag: string;
  calendarData: string;
}

function decodeXml(value: string): string {
  return value
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

function stripCData(value: string): string {
  return value.replace(/^<!\[CDATA\[/, '').replace(/\]\]>$/, '');
}

function tagValue(xml: string, tag: string): string {
  const regex = new RegExp(`<[^>]*:?${tag}[^>]*>([\\s\\S]*?)<\\/[^>]*:?${tag}>`, 'i');
  const match = regex.exec(xml);
  return match === null ? '' : decodeXml(stripCData(match[1].trim()));
}

function responseBlocks(xml: string): string[] {
  const regex = /<[^>]*:?response[^>]*>([\s\S]*?)<\/[^>]*:?response>/gi;
  const blocks: string[] = [];
  let match = regex.exec(xml);
  while (match !== null) {
    blocks.push(match[1]);
    match = regex.exec(xml);
  }
  return blocks;
}

export class XmlHelpers {
  static currentUserPrincipal(xml: string): string {
    return tagValue(tagValue(xml, 'current-user-principal'), 'href') || tagValue(xml, 'href');
  }

  static calendarHomeSet(xml: string): string {
    return tagValue(tagValue(xml, 'calendar-home-set'), 'href') || tagValue(xml, 'href');
  }

  static calendars(xml: string): CalendarSource[] {
    return responseBlocks(xml).map((block: string): CalendarSource => {
      const supported = /comp[^>]+name=["']VTODO["']/i.test(block);
      return {
        href: tagValue(block, 'href'),
        displayName: tagValue(block, 'displayname') || 'Tasks',
        supportsVTodo: supported,
        ctag: tagValue(block, 'getctag')
      };
    }).filter((calendar: CalendarSource) => calendar.href.length > 0 && calendar.supportsVTodo);
  }

  static calendarObjects(xml: string): CalendarObjectResponse[] {
    return responseBlocks(xml).map((block: string): CalendarObjectResponse => {
      return {
        href: tagValue(block, 'href'),
        etag: tagValue(block, 'getetag'),
        calendarData: tagValue(block, 'calendar-data')
      };
    }).filter((item: CalendarObjectResponse) => item.href.length > 0 && item.calendarData.length > 0);
  }

  static propfindCurrentUserPrincipal(): string {
    return '<?xml version="1.0" encoding="utf-8" ?>' +
      '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal /></d:prop></d:propfind>';
  }

  static propfindCalendarHomeSet(): string {
    return '<?xml version="1.0" encoding="utf-8" ?>' +
      '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' +
      '<d:prop><c:calendar-home-set /></d:prop></d:propfind>';
  }

  static propfindCalendars(): string {
    return '<?xml version="1.0" encoding="utf-8" ?>' +
      '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">' +
      '<d:prop><d:displayname /><d:resourcetype /><c:supported-calendar-component-set /><cs:getctag /></d:prop>' +
      '</d:propfind>';
  }

  static reportPendingTodos(): string {
    return '<?xml version="1.0" encoding="utf-8" ?>' +
      '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' +
      '<d:prop><d:getetag /><c:calendar-data /></d:prop>' +
      '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VTODO">' +
      '</c:comp-filter></c:comp-filter></c:filter>' +
      '</c:calendar-query>';
  }

  /**
   * PROPFIND-based alternative for servers that don't support REPORT/calendar-query.
   * Returns all resources; VTodoCodec.toTask filters non-VTODO entries.
   */
  static propfindTodos(): string {
    return '<?xml version="1.0" encoding="utf-8" ?>' +
      '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' +
      '<d:prop><d:getetag /><c:calendar-data /></d:prop>' +
      '</d:propfind>';
  }
}
