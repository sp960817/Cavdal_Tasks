import { common } from '@kit.AbilityKit';
import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { VTodoCodec } from '../caldav/VTodoCodec';
import { parseDueAsBeijing } from '../formatters/DueTimeFormatter';
import { TodoTask } from '../model/TaskModels';

const REMINDER_SLOT_TYPE = notificationManager.SlotType.SERVICE_INFORMATION;
const ALL_DAYS_OF_WEEK: number[] = [1, 2, 3, 4, 5, 6, 7];

export interface ReminderPublishResult {
  taskId: string;
  title: string;
  status: 'published' | 'skipped' | 'error';
  triggerAt: string;
  reminderId?: number;
  detail: string;
}

export interface ReminderSyncSummary {
  notificationsEnabled: boolean;
  activeTaskCount: number;
  reminderTaskCount: number;
  publishedCount: number;
  skippedCount: number;
  failedCount: number;
  registeredCount: number;
  beforeClearCount: number;
  afterClearCount: number;
  publishResults: ReminderPublishResult[];
  registeredResults: string[];
  errors: string[];
}

interface PreparedReminderRequest {
  request?: reminderAgentManager.ReminderRequestCalendar;
  triggerAt: string;
  skipReason?: string;
}

function errorText(err: Object): string {
  try {
    return JSON.stringify(err);
  } catch (_jsonErr) {
    return `${err}`;
  }
}

function clampDayOfMonth(year: number, month: number, day: number): number {
  return Math.min(day, new Date(year, month + 1, 0).getDate());
}

export class ReminderService {
  constructor(private context: common.Context) {
  }

  async syncTasks(tasks: TodoTask[]): Promise<ReminderSyncSummary> {
    const summary: ReminderSyncSummary = {
      notificationsEnabled: false,
      activeTaskCount: tasks.length,
      reminderTaskCount: 0,
      publishedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      registeredCount: 0,
      beforeClearCount: -1,
      afterClearCount: -1,
      publishResults: [],
      registeredResults: [],
      errors: []
    };
    try {
      summary.notificationsEnabled = await notificationManager.isNotificationEnabled();
    } catch (err) {
      summary.errors.push(`读取通知开关失败：${errorText(err)}`);
    }
    try {
      await this.ensureNotificationSlot();
      summary.beforeClearCount = await this.countValidReminders();
      await this.clearAllReminders();
      summary.afterClearCount = await this.countValidReminders();
      for (let i = 0; i < tasks.length; i++) {
        const result = await this.publishForTask(tasks[i]);
        summary.publishResults.push(result);
        if (result.status !== 'skipped') {
          summary.reminderTaskCount++;
        }
        if (result.status === 'published') {
          summary.publishedCount++;
        } else if (result.status === 'skipped') {
          summary.skippedCount++;
        } else {
          summary.failedCount++;
          summary.errors.push(`《${result.title}》${result.detail}`);
        }
      }
    } catch (err) {
      const text = errorText(err);
      summary.errors.push(`同步提醒失败：${text}`);
      console.error(`[ReminderService] syncTasks failed: ${text}`);
    }
    try {
      const registered = await reminderAgentManager.getAllValidReminders();
      summary.registeredCount = registered.length;
      summary.registeredResults = registered.map((item: reminderAgentManager.ReminderInfo) => this.describeRegisteredReminder(item));
    } catch (err) {
      summary.errors.push(`读取系统提醒失败：${errorText(err)}`);
    }
    return summary;
  }

  private async ensureNotificationSlot(): Promise<void> {
    try {
      await reminderAgentManager.addNotificationSlot({
        notificationType: REMINDER_SLOT_TYPE,
        badgeFlag: true,
        bypassDnd: false,
        vibrationEnabled: true,
        desc: 'Cavdal Tasks 待办提醒'
      });
    } catch (err) {
      console.error(`[ReminderService] ensureNotificationSlot failed: ${errorText(err)}`);
    }
  }

  private async publishForTask(task: TodoTask): Promise<ReminderPublishResult> {
    const prepared = this.buildReminderRequest(task);
    if (prepared.request === undefined) {
      return {
        taskId: task.id,
        title: task.title,
        status: 'skipped',
        triggerAt: prepared.triggerAt,
        detail: prepared.skipReason ?? '未设置提醒'
      };
    }
    try {
      const reminderId = await reminderAgentManager.publishReminder(prepared.request);
      return {
        taskId: task.id,
        title: task.title,
        status: 'published',
        triggerAt: prepared.triggerAt,
        reminderId,
        detail: `已注册 reminderId=${reminderId}`
      };
    } catch (err) {
      const text = errorText(err);
      console.error(`[ReminderService] publishForTask failed taskId=${task.id}: ${text}`);
      if (this.isQuotaError(err)) {
        try {
          await this.clearAllReminders();
          const reminderId = await reminderAgentManager.publishReminder(prepared.request);
          return {
            taskId: task.id,
            title: task.title,
            status: 'published',
            triggerAt: prepared.triggerAt,
            reminderId,
            detail: `清理后重试成功 reminderId=${reminderId}`
          };
        } catch (retryErr) {
          const retryText = errorText(retryErr);
          console.error(`[ReminderService] publishForTask retry failed taskId=${task.id}: ${retryText}`);
          return {
            taskId: task.id,
            title: task.title,
            status: 'error',
            triggerAt: prepared.triggerAt,
            detail: `配额超限，重试仍失败：${retryText}`
          };
        }
      }
      return {
        taskId: task.id,
        title: task.title,
        status: 'error',
        triggerAt: prepared.triggerAt,
        detail: text
      };
    }
  }

  private async clearAllReminders(): Promise<void> {
    try {
      const existing = await reminderAgentManager.getAllValidReminders();
      for (let i = 0; i < existing.length; i++) {
        try {
          await reminderAgentManager.cancelReminder(existing[i].reminderId);
        } catch (err) {
          console.error(`[ReminderService] cancelReminder failed: ${errorText(err)}`);
        }
      }
    } catch (err) {
      console.error(`[ReminderService] getAllValidReminders before clear failed: ${errorText(err)}`);
    }
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (err) {
      console.error(`[ReminderService] cancelAllReminders failed: ${errorText(err)}`);
    }
  }

  private async countValidReminders(): Promise<number> {
    try {
      const list = await reminderAgentManager.getAllValidReminders();
      return list.length;
    } catch (err) {
      console.error(`[ReminderService] countValidReminders failed: ${errorText(err)}`);
      return -1;
    }
  }

  private isQuotaError(err: Object): boolean {
    const code = (err as Record<string, number>)['code'];
    return code === 1700002;
  }

  private buildReminderRequest(task: TodoTask): PreparedReminderRequest {
    const due = parseDueAsBeijing(task.due);
    if (due === undefined) {
      return { triggerAt: '-', skipReason: '截止时间无效' };
    }
    const reminder = VTodoCodec.detectReminder(task.rawIcs, task.due);
    if (reminder === '无') {
      return { triggerAt: '-', skipReason: '未设置提醒' };
    }
    const repeat = VTodoCodec.detectRepeat(task.rawIcs);
    let triggerDate = this.triggerDate(due, reminder);
    if (triggerDate === undefined) {
      return { triggerAt: '-', skipReason: '无法计算提醒时间' };
    }
    triggerDate = this.normalizeTriggerDate(triggerDate, repeat);
    const triggerAt = this.formatDate(triggerDate);
    if (repeat === '无' && triggerDate.getTime() <= Date.now()) {
      return { triggerAt, skipReason: '提醒时间已过' };
    }

    const request = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      title: task.title,
      content: task.description.length > 0 ? task.description : `待办提醒：${task.title}`,
      expiredContent: task.title,
      notificationId: this.notificationId(task.id),
      slotType: REMINDER_SLOT_TYPE,
      tapDismissed: true,
      dateTime: {
        year: triggerDate.getFullYear(),
        month: triggerDate.getMonth() + 1,
        day: triggerDate.getDate(),
        hour: triggerDate.getHours(),
        minute: triggerDate.getMinutes(),
        second: triggerDate.getSeconds()
      }
    } as reminderAgentManager.ReminderRequestCalendar;

    if (repeat === '每天') {
      request.daysOfWeek = ALL_DAYS_OF_WEEK;
    } else if (repeat === '每周') {
      request.daysOfWeek = [this.dayOfWeek(triggerDate)];
    } else if (repeat === '每月') {
      request.repeatDays = [triggerDate.getDate()];
      request.repeatMonths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    }
    return { request, triggerAt };
  }

  private triggerDate(due: ReturnType<typeof parseDueAsBeijing>, reminder: string): Date | undefined {
    if (due === undefined) {
      return undefined;
    }
    const dueDate = new Date(due.year, due.month - 1, due.day, due.hour, due.minute, 0);
    if (reminder === '立刻') {
      return dueDate;
    }
    if (reminder === '当天') {
      return new Date(due.year, due.month - 1, due.day, 0, 0, 0);
    }
    if (reminder === '提前一天') {
      return new Date(due.year, due.month - 1, due.day - 1, 0, 0, 0);
    }
    if (reminder === '提前一周') {
      return new Date(due.year, due.month - 1, due.day - 7, 0, 0, 0);
    }
    return undefined;
  }

  private normalizeTriggerDate(triggerDate: Date, repeat: string): Date {
    const next = new Date(triggerDate.getTime());
    if (repeat === '无') {
      return next;
    }
    while (next.getTime() <= Date.now()) {
      if (repeat === '每天') {
        next.setDate(next.getDate() + 1);
      } else if (repeat === '每周') {
        next.setDate(next.getDate() + 7);
      } else if (repeat === '每月') {
        const year = next.getFullYear();
        const month = next.getMonth() + 1;
        const day = next.getDate();
        const nextYear = month === 12 ? year + 1 : year;
        const nextMonth = month === 12 ? 0 : month;
        next.setFullYear(nextYear, nextMonth, clampDayOfMonth(nextYear, nextMonth, day));
      } else {
        break;
      }
    }
    return next;
  }

  private dayOfWeek(date: Date): number {
    const day = date.getDay();
    return day === 0 ? 7 : day;
  }

  private notificationId(taskId: string): number {
    let hash = 0;
    for (let i = 0; i < taskId.length; i++) {
      hash = (hash * 31 + taskId.charCodeAt(i)) & 0x7fffffff;
    }
    return hash;
  }

  private formatDate(date: Date): string {
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  private formatLocalDateTime(dateTime?: reminderAgentManager.LocalDateTime): string {
    if (dateTime === undefined) {
      return '-';
    }
    const date = new Date(
      dateTime.year,
      dateTime.month - 1,
      dateTime.day,
      dateTime.hour,
      dateTime.minute,
      dateTime.second ?? 0
    );
    return this.formatDate(date);
  }

  private describeRegisteredReminder(item: reminderAgentManager.ReminderInfo): string {
    const request = item.reminderReq as reminderAgentManager.ReminderRequestCalendar;
    return `#${item.reminderId} ${request.title ?? '未命名提醒'} @ ${this.formatLocalDateTime(request.dateTime)}`;
  }
}
