import { TodoTask } from '../model/TaskModels';

export interface VTodoProperty {
  name: string;
  params: string;
  value: string;
  rawName: string;
}

export interface ParsedVTodo {
  properties: VTodoProperty[];
  raw: string;
}

function unfold(input: string): string[] {
  const normalized = input.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const physical = normalized.split('\n');
  const lines: string[] = [];
  for (let i = 0; i < physical.length; i++) {
    const line = physical[i];
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.length > 0) {
      lines[lines.length - 1] = lines[lines.length - 1] + line.substring(1);
    } else if (line.length > 0) {
      lines.push(line);
    }
  }
  return lines;
}

function splitProperty(line: string): VTodoProperty | undefined {
  const colon = line.indexOf(':');
  if (colon < 0) {
    return undefined;
  }
  const left = line.substring(0, colon);
  const semi = left.indexOf(';');
  const rawName = semi >= 0 ? left.substring(0, semi) : left;
  return {
    name: rawName.toUpperCase(),
    rawName,
    params: semi >= 0 ? left.substring(semi) : '',
    value: line.substring(colon + 1)
  };
}

function escapeText(value: string): string {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/\n/g, '\\n')
    .replace(/,/g, '\\,')
    .replace(/;/g, '\\;');
}

export function unescapeText(value: string): string {
  let result = '';
  for (let i = 0; i < value.length; i++) {
    const current = value.charAt(i);
    if (current === '\\' && i + 1 < value.length) {
      const next = value.charAt(i + 1);
      if (next === 'n' || next === 'N') {
        result += '\n';
      } else {
        result += next;
      }
      i++;
    } else {
      result += current;
    }
  }
  return result;
}

const HEX = '0123456789abcdef';

function generateUid(): string {
  // UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  let id = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      id += '-';
    } else if (i === 14) {
      id += '4';
    } else if (i === 19) {
      id += HEX[Math.floor(Math.random() * 4) + 8]; // 8,9,a,b
    } else {
      id += HEX[Math.floor(Math.random() * 16)];
    }
  }
  return id;
}

function extractUid(rawIcs: string): string {
  const parsed = VTodoCodec.parse(rawIcs);
  const uid = VTodoCodec.property(parsed, 'UID');
  return uid.length > 0 ? uid : generateUid();
}

function foldLine(line: string): string {
  const limit = 74;
  if (line.length <= limit) {
    return line;
  }
  let out = '';
  let rest = line;
  while (rest.length > limit) {
    out += rest.substring(0, limit) + '\r\n ';
    rest = rest.substring(limit);
  }
  return out + rest;
}

function toUtcStamp(date: Date): string {
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  return `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`;
}

function findComponentLines(lines: string[], name: string): string[] {
  const start = lines.findIndex((line: string) => line.toUpperCase() === `BEGIN:${name}`);
  const end = lines.findIndex((line: string, index: number) => index > start && line.toUpperCase() === `END:${name}`);
  if (start < 0 || end < 0) {
    return [];
  }
  return lines.slice(start + 1, end);
}

export class VTodoCodec {
  static parse(input: string): ParsedVTodo {
    const lines = unfold(input);
    const todoLines = findComponentLines(lines, 'VTODO');
    const props: VTodoProperty[] = [];
    for (let i = 0; i < todoLines.length; i++) {
      const prop = splitProperty(todoLines[i]);
      if (prop !== undefined) {
        props.push(prop);
      }
    }
    return { properties: props, raw: input };
  }

  static property(parsed: ParsedVTodo, name: string): string {
    const target = name.toUpperCase();
    const prop = parsed.properties.find((item: VTodoProperty) => item.name === target);
    return prop === undefined ? '' : prop.value;
  }

  static toTask(input: string, href: string, calendarHref: string, etag: string): TodoTask | undefined {
    const parsed = VTodoCodec.parse(input);
    const uid = VTodoCodec.property(parsed, 'UID');
    const summary = unescapeText(VTodoCodec.property(parsed, 'SUMMARY'));
    if (uid.length === 0 && summary.length === 0) {
      return undefined;
    }
    const percentValue = Number(VTodoCodec.property(parsed, 'PERCENT-COMPLETE'));
    const priorityValue = Number(VTodoCodec.property(parsed, 'PRIORITY'));
    return {
      id: uid.length > 0 ? uid : href,
      uid: uid.length > 0 ? uid : href,
      href,
      calendarHref,
      etag,
      title: summary.length > 0 ? summary : 'Untitled task',
      description: unescapeText(VTodoCodec.property(parsed, 'DESCRIPTION')),
      due: VTodoCodec.property(parsed, 'DUE'),
      priority: Number.isFinite(priorityValue) ? priorityValue : 0,
      status: VTodoCodec.property(parsed, 'STATUS') || 'NEEDS-ACTION',
      completedAt: VTodoCodec.property(parsed, 'COMPLETED'),
      percentComplete: Number.isFinite(percentValue) ? percentValue : 0,
      rawIcs: input,
      syncState: 'synced',
      updatedAt: Date.now()
    };
  }

  /**
   * Build a complete VTODO VCALENDAR blob from scratch.
   * This is the single source of truth for ICS generation.
   */
  private static buildRawIcs(uid: string, title: string, description: string, due: string,
    status: string, percent: number, completedAt: string, lastModified: Date,
    reminder: string, repeat: string): string {
    const stamp = toUtcStamp(lastModified);
    const alarmTrigger = VTodoCodec.reminderTrigger(reminder, due);
    const repeatRule = VTodoCodec.repeatRule(repeat);
    const lines: string[] = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Cavdal Tasks//HarmonyOS//EN',
      'BEGIN:VTODO',
      `UID:${uid}`,
      `DTSTAMP:${stamp}`,
      `LAST-MODIFIED:${stamp}`,
      `SUMMARY:${escapeText(title)}`,
    ];
    if (description.length > 0) {
      lines.push(`DESCRIPTION:${escapeText(description)}`);
    }
    if (due.length > 0) {
      lines.push(`DUE:${due}`);
    }
    if (repeatRule.length > 0) {
      lines.push(`RRULE:${repeatRule}`);
    }
    lines.push(`STATUS:${status}`);
    lines.push(`PERCENT-COMPLETE:${percent}`);
    if (completedAt.length > 0) {
      lines.push(`COMPLETED:${completedAt}`);
    }
    // VALARM sub-component
    if (due.length > 0 && alarmTrigger.length > 0) {
      lines.push('BEGIN:VALARM');
      lines.push(`TRIGGER:${alarmTrigger}`);
      lines.push('ACTION:DISPLAY');
      lines.push(`DESCRIPTION:${escapeText(title)}`);
      lines.push('END:VALARM');
    }
    lines.push('END:VTODO');
    lines.push('END:VCALENDAR');
    return lines.filter((line: string) => line.length > 0).map(foldLine).join('\r\n') + '\r\n';
  }

  static createLocal(title: string, description: string, due: string, calendarHref: string, reminder: string = '无', repeat: string = '无'): TodoTask {
    const now = Date.now();
    const uid = generateUid();
    const raw = VTodoCodec.buildRawIcs(uid, title, description, due, 'NEEDS-ACTION', 0, '', new Date(now), reminder, repeat);
    return {
      id: uid,
      uid,
      href: '',
      calendarHref,
      etag: '',
      title,
      description,
      due,
      priority: 0,
      status: 'NEEDS-ACTION',
      completedAt: '',
      percentComplete: 0,
      rawIcs: raw,
      syncState: 'pending',
      updatedAt: now
    };
  }

  private static reminderTrigger(reminder: string, due: string): string {
    if (reminder === '立刻') {
      return 'PT0S';
    }
    if (reminder === '当天' || reminder === '提前一天' || reminder === '提前一周') {
      const match = due.match(/T(\d{2})(\d{2})/);
      if (!match) {
        return '';
      }
      const utcMinTotal = parseInt(match[1]) * 60 + parseInt(match[2]);
      let offsetMin = -utcMinTotal;
      if (reminder === '提前一天') {
        offsetMin -= 1440;
      } else if (reminder === '提前一周') {
        offsetMin -= 10080;
      }
      if (offsetMin < 0) {
        const absMin = Math.abs(offsetMin);
        const h = Math.floor(absMin / 60);
        const m = absMin % 60;
        if (h >= 24) {
          const d = Math.floor(h / 24);
          const rh = h % 24;
          return m > 0 ? `-P${d}DT${rh}H${m}M` : `-P${d}DT${rh}H`;
        }
        return m > 0 ? `-PT${h}H${m}M` : `-PT${h}H`;
      }
      return 'PT0S';
    }
    return '';
  }

  private static repeatRule(repeat: string): string {
    if (repeat === '每天') {
      return 'FREQ=DAILY';
    }
    if (repeat === '每周') {
      return 'FREQ=WEEKLY';
    }
    if (repeat === '每月') {
      return 'FREQ=MONTHLY';
    }
    return '';
  }

  static setCompletion(task: TodoTask, done: boolean, date: Date = new Date()): TodoTask {
    const uid = extractUid(task.rawIcs);
    const status = done ? 'COMPLETED' : 'NEEDS-ACTION';
    const stamp = toUtcStamp(date);
    const completedAt = done ? stamp : '';
    const percent = done ? 100 : 0;
    // Rebuild from scratch so VALARM etc are consistent
    const raw = VTodoCodec.buildRawIcs(uid, task.title, task.description, task.due,
      status, percent, completedAt, date, '', '');
    return {
      id: uid,
      uid,
      href: task.href,
      calendarHref: task.calendarHref,
      etag: task.etag,
      title: task.title,
      description: task.description,
      due: task.due,
      priority: task.priority,
      status,
      completedAt,
      percentComplete: percent,
      rawIcs: raw,
      syncState: 'pending',
      updatedAt: date.getTime()
    };
  }

  static updateFields(task: TodoTask, title: string, description: string, due: string, reminder: string, repeat: string): TodoTask {
    const uid = extractUid(task.rawIcs);
    const now = new Date();
    const raw = VTodoCodec.buildRawIcs(uid, title, description, due,
      task.status, task.percentComplete, task.completedAt, now, reminder, repeat);
    return {
      id: uid,
      uid,
      href: task.href,
      calendarHref: task.calendarHref,
      etag: task.etag,
      title,
      description,
      due,
      priority: task.priority,
      status: task.status,
      completedAt: task.completedAt,
      percentComplete: task.percentComplete,
      rawIcs: raw,
      syncState: 'pending',
      updatedAt: now.getTime()
    };
  }

  /**
   * Detect reminder option from raw ICS VALARM TRIGGER.
   * Returns '无', '立刻', '当天', '提前一天', or '提前一周'.
   */
  static detectReminder(rawIcs: string, due: string): string {
    if (rawIcs.length === 0) {
      return '无';
    }
    const valarmStart = rawIcs.toUpperCase().indexOf('BEGIN:VALARM');
    if (valarmStart < 0) {
      return '无';
    }
    const valarmSection = rawIcs.substring(valarmStart);
    const valarmEnd = valarmSection.indexOf('END:VALARM');
    const block = valarmEnd >= 0 ? valarmSection.substring(0, valarmEnd) : valarmSection;
    const triggerMatch = /TRIGGER[^:]*:([^\r\n]+)/i.exec(block);
    if (!triggerMatch) {
      return '无';
    }
    const trigger = triggerMatch[1].trim();
    if (trigger === 'PT0S') {
      return '立刻';
    }
    // Try to detect relative triggers against the due time
    const negMs = VTodoCodec.parseDurationMs(trigger);
    if (negMs === undefined || due.length === 0) {
      return '无';
    }
    // Parse due time to see how far before due the trigger fires
    const dueMatch = due.match(/T(\d{2})(\d{2})/);
    if (!dueMatch) {
      return '无';
    }
    const dueTotalMin = parseInt(dueMatch[1]) * 60 + parseInt(dueMatch[2]);
    const triggerMin = Math.round(negMs / 60000);
    const offsetFromDue = dueTotalMin + triggerMin; // positive = before due start
    if (offsetFromDue <= 0) {
      return '无';
    }
    if (offsetFromDue <= 1) {
      return '当天';
    }
    // Check if it's approximately 24h before (1440 min)
    if (offsetFromDue >= 1430 && offsetFromDue <= 1450) {
      return '提前一天';
    }
    if (offsetFromDue >= 10070 && offsetFromDue <= 10090) {
      return '提前一周';
    }
    return '无';
  }

  /**
   * Detect repeat option from raw ICS RRULE.
   * Returns '无', '每天', '每周', or '每月'.
   */
  static detectRepeat(rawIcs: string): string {
    if (rawIcs.length === 0) {
      return '无';
    }
    const match = /RRULE[^:]*:FREQ=(\w+)/i.exec(rawIcs);
    if (!match) {
      return '无';
    }
    const freq = match[1].toUpperCase();
    if (freq === 'DAILY') {
      return '每天';
    }
    if (freq === 'WEEKLY') {
      return '每周';
    }
    if (freq === 'MONTHLY') {
      return '每月';
    }
    return '无';
  }

  /**
   * Parse iCalendar duration string to total milliseconds (negative = before).
   * Handles formats like PT0S, PT1H, -PT1H, P1D, -P1DT2H, etc.
   */
  private static parseDurationMs(dur: string): number | undefined {
    let total = 0;
    let sign = 1;
    let rest = dur.trim();
    if (rest.startsWith('-')) {
      sign = -1;
      rest = rest.substring(1);
    } else if (rest.startsWith('+')) {
      rest = rest.substring(1);
    }
    if (!rest.startsWith('P')) {
      return undefined;
    }
    rest = rest.substring(1);
    // Days before T
    const dMatch = rest.match(/^(\d+)D/);
    if (dMatch) {
      total += parseInt(dMatch[1]) * 86400000;
      rest = rest.substring(dMatch[0].length);
    }
    // Time after T
    if (rest.startsWith('T')) {
      rest = rest.substring(1);
      const hMatch = rest.match(/^(\d+)H/);
      if (hMatch) {
        total += parseInt(hMatch[1]) * 3600000;
        rest = rest.substring(hMatch[0].length);
      }
      const mMatch = rest.match(/^(\d+)M/);
      if (mMatch) {
        total += parseInt(mMatch[1]) * 60000;
        rest = rest.substring(mMatch[0].length);
      }
      const sMatch = rest.match(/^(\d+)S/);
      if (sMatch) {
        total += parseInt(sMatch[1]) * 1000;
      }
    }
    return sign * total;
  }

  static replaceProperties(input: string, values: Map<string, string>, remove: string[] = []): string {
    const lines = unfold(input);
    const removeSet = new Set(remove.map((item: string) => item.toUpperCase()));
    const seen = new Set<string>();
    const nextLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const prop = splitProperty(lines[i]);
      if (prop !== undefined && (values.has(prop.name) || removeSet.has(prop.name))) {
        if (values.has(prop.name)) {
          nextLines.push(foldLine(`${prop.rawName}${prop.params}:${values.get(prop.name)}`));
          seen.add(prop.name);
        }
      } else if (lines[i].toUpperCase() === 'END:VTODO') {
        values.forEach((value: string, key: string) => {
          if (!seen.has(key)) {
            nextLines.push(foldLine(`${key}:${value}`));
          }
        });
        nextLines.push(lines[i]);
      } else {
        nextLines.push(lines[i]);
      }
    }
    return nextLines.join('\r\n') + '\r\n';
  }
}
