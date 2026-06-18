const BEIJING_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

interface BeijingDueParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  hasTime: boolean;
}

function toNumber(value: string, fallback: number = 0): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function dayIndex(year: number, month: number, day: number): number {
  return Math.floor(Date.UTC(year, month - 1, day) / DAY_MS);
}

function nowInBeijing(): BeijingDueParts {
  const shifted = new Date(Date.now() + BEIJING_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    hasTime: true
  };
}

function utcToBeijing(year: number, month: number, day: number, hour: number, minute: number, second: number): BeijingDueParts {
  const shifted = new Date(Date.UTC(year, month - 1, day, hour, minute, second) + BEIJING_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    hasTime: true
  };
}

export function parseDueAsBeijing(rawDue: string): BeijingDueParts | undefined {
  const trimmed = rawDue.trim();
  if (trimmed.length < 8) {
    return undefined;
  }

  const hasUtcMark = trimmed.endsWith('Z');
  const body = hasUtcMark ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  const parts = body.split('T');
  const datePart = parts[0];
  if (datePart.length !== 8) {
    return undefined;
  }

  const year = toNumber(datePart.substring(0, 4), -1);
  const month = toNumber(datePart.substring(4, 6), -1);
  const day = toNumber(datePart.substring(6, 8), -1);
  if (year < 0 || month < 1 || month > 12 || day < 1 || day > 31) {
    return undefined;
  }

  if (parts.length < 2 || parts[1].length === 0) {
    return { year, month, day, hour: 0, minute: 0, hasTime: false };
  }

  const timePart = parts[1];
  const hour = toNumber(timePart.substring(0, Math.min(2, timePart.length)), 0);
  const minute = timePart.length >= 4 ? toNumber(timePart.substring(2, 4), 0) : 0;
  const second = timePart.length >= 6 ? toNumber(timePart.substring(4, 6), 0) : 0;
  if (hasUtcMark) {
    return utcToBeijing(year, month, day, hour, minute, second);
  }
  return { year, month, day, hour, minute, hasTime: true };
}

export function formatDueForDisplay(rawDue: string): string {
  const due = parseDueAsBeijing(rawDue);
  if (due === undefined) {
    return rawDue;
  }

  const now = nowInBeijing();
  const delta = dayIndex(due.year, due.month, due.day) - dayIndex(now.year, now.month, now.day);
  if (delta >= -1 && delta <= 1) {
    const label = delta === -1 ? '昨天' : delta === 0 ? '今天' : '明天';
    return due.hasTime ? `${label} ${pad(due.hour)}:${pad(due.minute)}` : label;
  }

  return `${due.month}月${due.day}日`;
}
