import { parseDueAsBeijing } from './DueTimeFormatter';

function compactText(value: string, maxLength: number): string {
  const text = value.replace(/\s+/g, ' ').trim();
  const characters = Array.from(text);
  return characters.length > maxLength ? characters.slice(0, maxLength - 1).join('') + '…' : text;
}

export function formatReminderTitle(title: string): string {
  return compactText(title, 80) || '待办提醒';
}

export function formatReminderContent(title: string, description: string, rawDue: string, repeat: string): string {
  const due = parseDueAsBeijing(rawDue);
  const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
  let schedule = '待办提醒';
  if (due !== undefined) {
    const time = due.hasTime ? ` ${pad(due.hour)}:${pad(due.minute)}` : ' · 全天';
    // Repeating tasks keep their original DUE in ICS. Avoid presenting an old
    // date as the current occurrence, and never precompute "today/tomorrow".
    if (repeat === '每天') {
      schedule = `每天${time}`;
    } else if (repeat === '每周') {
      const weekday = ['日', '一', '二', '三', '四', '五', '六'][new Date(Date.UTC(due.year, due.month - 1, due.day)).getUTCDay()];
      schedule = `每周${weekday}${time}`;
    } else if (repeat === '每月') {
      schedule = `每月${due.day}日${time}`;
    } else {
      schedule = `截止 ${due.year}年${due.month}月${due.day}日${time}`;
    }
  }
  const note = compactText(description, 80);
  const normalizedTitle = compactText(title, 80);
  return note.length > 0 && note !== normalizedTitle ? `${schedule}\n${note}` : schedule;
}
