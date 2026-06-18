import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CalDavClient } from '../caldav/CalDavClient';
import { VTodoCodec } from '../caldav/VTodoCodec';
import { AccountSettings, CalendarSource, SyncOperation, TodoTask, WidgetBlurStyle } from '../model/TaskModels';
import { CredentialStore, SettingsStore, TaskRepository } from '../data/TaskRepository';
import { ReminderService, ReminderSyncSummary } from '../reminder/ReminderService';
import { WidgetUpdater } from '../widget/WidgetUpdater';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CavdalSync';

export interface SyncResultSummary {
  ok: boolean;
  message: string;
  imported: number;
}

export class SyncService {
  private repository: TaskRepository;
  private settings: SettingsStore;
  private reminderService: ReminderService;

  constructor(private context: common.Context) {
    this.repository = new TaskRepository(context);
    this.settings = new SettingsStore(context);
    this.reminderService = new ReminderService(context);
  }

  private async refreshWidgets(): Promise<void> {
    try {
      await WidgetUpdater.updateAllForms(this.context);
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'refreshWidgets failed %{public}s', `${err}`);
    }
  }

  private async refreshReminders(): Promise<void> {
    try {
      const tasks = await this.repository.activeTasks();
      await this.reminderService.syncTasks(tasks);
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'refreshReminders failed %{public}s', `${err}`);
    }
  }

  async syncLocalReminders(): Promise<void> {
    await this.refreshReminders();
  }

  async runReminderDiagnostics(): Promise<string> {
    const tasks = await this.repository.activeTasks();
    const summary = await this.reminderService.syncTasks(tasks);
    return this.formatReminderDiagnostics(summary);
  }

  private async getClient(): Promise<{ client: CalDavClient; settings: AccountSettings; ok: boolean }> {
    let settings: AccountSettings;
    try {
      settings = await this.settings.load();
    } catch (err) {
      return { client: undefined as unknown as CalDavClient, settings: {
        serverUrl: '', username: '', calendarHref: '', calendarName: '', lastSyncAt: 0, widgetBlurStyle: 'thin'
      } as AccountSettings, ok: false };
    }
    let password = '';
    try {
      password = await CredentialStore.loadPassword();
    } catch (_err) {
      password = '';
    }
    if (settings.serverUrl.length === 0 || settings.calendarHref.length === 0 || password.length === 0) {
      return { client: undefined as unknown as CalDavClient, settings, ok: false };
    }
    let client: CalDavClient;
    try {
      client = new CalDavClient({
        serverUrl: settings.serverUrl,
        username: settings.username,
        password
      });
    } catch (err) {
      return { client: undefined as unknown as CalDavClient, settings, ok: false };
    }
    return { client, settings, ok: true };
  }

  async loadSettings(): Promise<AccountSettings> {
    return this.settings.load();
  }

  async saveAccount(serverUrl: string, username: string, password: string, calendar: CalendarSource): Promise<void> {
    const previous = await this.settings.load();
    await CredentialStore.savePassword(password);
    await this.settings.save({
      serverUrl,
      username,
      calendarHref: calendar.href,
      calendarName: calendar.displayName,
      lastSyncAt: 0,
      widgetBlurStyle: previous.widgetBlurStyle
    });
  }

  async saveWidgetBlurStyle(style: WidgetBlurStyle): Promise<void> {
    const settings = await this.settings.load();
    settings.widgetBlurStyle = style;
    await this.settings.save(settings);
    await this.refreshWidgets();
  }

  async discover(serverUrl: string, username: string, password: string): Promise<CalendarSource[]> {
    const client = new CalDavClient({ serverUrl, username, password });
    const calendars = await client.discoverCalendars();
    await this.repository.saveCalendars(calendars);
    return calendars;
  }

  async syncNow(): Promise<SyncResultSummary> {
    let client: CalDavClient;
    let settings: AccountSettings;
    try {
      const loaded = await this.getClient();
      if (!loaded.ok) {
        return { ok: false, message: '请先配置 CalDAV 账号', imported: 0 };
      }
      client = loaded.client;
      settings = loaded.settings;
    } catch (err) {
      const errMsg = `${err}`;
      const errCode = (err as Record<string, number>)['code'];
      hilog.error(LOG_DOMAIN, LOG_TAG, 'getClient failed code=%{public}d msg=%{public}s', errCode ?? -1, errMsg);
      return { ok: false, message: `加载账号信息失败：${errCode !== undefined ? `[${errCode}] ` : ''}${errMsg}`, imported: 0 };
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, 'syncNow start calendarHref=%{public}s', settings.calendarHref);
    // 1️⃣ 先推送本地离线变更（增/删/改）
    let flushErrors = 0;
    try {
      flushErrors = await this.flushQueue(client);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'flushQueue done errors=%{public}d', flushErrors);
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'flushQueue threw %{public}s', `${err}`);
      flushErrors = -1;
    }
    // 2️⃣ 再拉取服务器最新数据
    let tasks: TodoTask[] = [];
    try {
      tasks = await client.fetchTodos(settings.calendarHref);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'fetchTodos returned %{public}d tasks', tasks.length);
    } catch (err) {
      const errMsg = `${err}`;
      const errCode = (err as Record<string, number>)['code'];
      const text = errCode !== undefined ? `[${errCode}] ${errMsg}` : errMsg;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'fetchTodos failed %{public}s', text);
      await this.refreshWidgets();
      if (flushErrors === 0) {
        return { ok: false, message: `服务器连接失败：${text}`, imported: 0 };
      }
      return { ok: false, message: `${flushErrors} 个离线操作待重试，拉取失败：${text}`, imported: 0 };
    }
    await this.repository.saveTasks(tasks);
    settings.lastSyncAt = Date.now();
    await this.settings.save(settings);
    await this.refreshReminders();
    await this.refreshWidgets();
    const summary = `已同步 ${tasks.length} 个待办`;
    const pending = flushErrors > 0 ? `，${flushErrors} 个离线操作待重试` : '';
    return { ok: true, message: `${summary}${pending}`, imported: tasks.length };
  }

  async addTask(title: string, description: string, due: string, reminder: string = '无', repeat: string = '无'): Promise<void> {
    const { client, settings, ok } = await this.getClient();
    const task = VTodoCodec.createLocal(title, description, due, settings.calendarHref, reminder, repeat);
    if (ok) {
      try {
        const result = await client.putTask(task);
        if (result.ok) {
          task.etag = result.etag;
          task.syncState = 'synced';
        } else {
          task.syncState = 'pending';
        }
      } catch (_err) {
        task.syncState = 'pending';
      }
    } else {
      task.syncState = 'pending';
    }
    await this.repository.saveTask(task);
    if (task.syncState === 'pending') {
      await this.repository.enqueue(this.operationFor(task));
    }
    await this.refreshReminders();
  }

  async setTaskCompleted(taskId: string, done: boolean): Promise<void> {
    const task = await this.repository.getTask(taskId);
    if (task === undefined) {
      return;
    }
    const updated = VTodoCodec.setCompletion(task, done);
    updated.syncState = 'pending';
    await this.repository.saveTask(updated);
    await this.repository.enqueue(this.operationFor(updated));
    await this.refreshReminders();
    await this.refreshWidgets();
    const { client, ok } = await this.getClient();
    if (ok) {
      try {
        let result = await client.putTask(updated);
        if (!result.ok && (result.status === 409 || result.status === 412) && updated.href.length > 0) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'completion stale etag, retry latest taskId=%{public}s', updated.id);
          result = await client.putTask(updated, true);
        }
        if (result.ok) {
          updated.href = updated.href.length > 0 ? updated.href : `${updated.uid}.ics`;
          updated.etag = result.etag;
          updated.syncState = 'synced';
          await this.repository.removePutOperations(updated.id);
        } else {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'completion PUT failed taskId=%{public}s status=%{public}d', updated.id, result.status);
        }
      } catch (err) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'completion PUT threw taskId=%{public}s err=%{public}s', updated.id, `${err}`);
        // Will remain pending and enqueued
      }
    }
    await this.repository.saveTask(updated);
    await this.refreshReminders();
    await this.refreshWidgets();
  }

  async setTaskCompletedLocally(taskId: string, done: boolean): Promise<boolean> {
    const task = await this.repository.getTask(taskId);
    if (task === undefined) {
      return false;
    }
    const updated = VTodoCodec.setCompletion(task, done);
    updated.syncState = 'pending';
    await this.repository.saveTask(updated);
    await this.repository.enqueue(this.operationFor(updated));
    await this.refreshReminders();
    return true;
  }

  async clearLocal(): Promise<void> {
    await this.repository.clearTasks();
    await this.refreshReminders();
  }

  private operationFor(task: TodoTask): SyncOperation {
    return {
      id: `${task.id}-${Date.now()}`,
      taskId: task.id,
      type: 'put',
      payload: task.rawIcs,
      createdAt: Date.now(),
      attempts: 0,
      lastError: ''
    };
  }

  async deleteTask(taskId: string): Promise<void> {
    const task = await this.repository.getTask(taskId);
    if (task === undefined) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'deleteTask not found id=%{public}s', taskId);
      return;
    }
    // 保存远程删除所需 href/etag 再执行本地删除
    const href = task.href;
    const etag = task.etag;
    await this.repository.deleteTask(taskId);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'deleteTask local done id=%{public}s href=%{public}s', taskId, href);
    if (href.length > 0) {
      const { client, ok } = await this.getClient();
      if (ok) {
        try {
          const result = await client.deleteTask(task);
          if (result.ok || result.status === 404) {
            hilog.info(LOG_DOMAIN, LOG_TAG, 'deleteTask remote ok id=%{public}s', taskId);
          } else {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'deleteTask remote fail status=%{public}d, enqueuing', result.status);
            await this.repository.enqueue(this.makeDeleteOp(taskId, href, etag));
          }
        } catch (err) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'deleteTask remote threw, enqueuing err=%{public}s', `${err}`);
          await this.repository.enqueue(this.makeDeleteOp(taskId, href, etag));
        }
      } else {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'deleteTask offline, enqueuing');
        await this.repository.enqueue(this.makeDeleteOp(taskId, href, etag));
      }
    }
    await this.refreshReminders();
  }

  private makeDeleteOp(taskId: string, href: string, etag: string): SyncOperation {
    return {
      id: `del-${taskId}-${Date.now()}`,
      taskId,
      type: 'delete',
      payload: JSON.stringify({ href, etag }),
      createdAt: Date.now(),
      attempts: 0,
      lastError: ''
    };
  }

  async updateTask(taskId: string, title: string, description: string, due: string, reminder: string, repeat: string): Promise<void> {
    const task = await this.repository.getTask(taskId);
    if (task === undefined) {
      return;
    }
    const updated = VTodoCodec.updateFields(task, title, description, due, reminder, repeat);
    updated.syncState = 'pending';
    // Persist first so the UI and offline state do not wait for the network request.
    await this.repository.saveTask(updated);
    const { client, ok } = await this.getClient();
    if (ok) {
      try {
        const result = await client.putTask(updated);
        if (result.ok) {
          updated.etag = result.etag;
          updated.syncState = 'synced';
        }
      } catch (_err) {
        // Will remain pending
      }
    }
    if (updated.syncState === 'synced') {
      await this.repository.saveTask(updated);
    }
    if (updated.syncState === 'pending') {
      await this.repository.enqueue(this.operationFor(updated));
    }
    await this.refreshReminders();
  }

  private async flushQueue(client: CalDavClient): Promise<number> {
    const operations = await this.repository.pendingOperations();
    hilog.info(LOG_DOMAIN, LOG_TAG, 'flushQueue %{public}d operations', operations.length);
    let failures = 0;
    for (let i = 0; i < operations.length; i++) {
      const operation = operations[i];
      if (operation.type === 'delete') {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'flush delete taskId=%{public}s', operation.taskId);
        let task = await this.repository.getTask(operation.taskId);
        if (task === undefined || task.href.length === 0) {
          try {
            const info = JSON.parse(operation.payload) as Record<string, string>;
            const pHref = info['href'] || '';
            if (pHref.length === 0) {
              hilog.warn(LOG_DOMAIN, LOG_TAG, 'flush delete skip no href taskId=%{public}s', operation.taskId);
              await this.repository.removeOperation(operation.id);
              continue;
            }
            task = { href: pHref, etag: '' } as TodoTask;
            hilog.info(LOG_DOMAIN, LOG_TAG, 'flush delete recovered href=%{public}s', pHref);
          } catch (_) {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'flush delete skip bad payload taskId=%{public}s', operation.taskId);
            await this.repository.removeOperation(operation.id);
            continue;
          }
        }
        try {
          const result = await client.deleteTask(task);
          hilog.info(LOG_DOMAIN, LOG_TAG, 'flush delete result ok=%{public}s status=%{public}d', `${result.ok}`, result.status);
          if (result.ok || result.status === 404) {
            await this.repository.deleteTask(operation.taskId);
            await this.repository.removeOperation(operation.id);
          } else {
            await this.repository.updateOperationFailure(operation, `HTTP ${result.status}`);
            failures++;
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'flush delete failed status=%{public}d', result.status);
          }
        } catch (err) {
          await this.repository.updateOperationFailure(operation, 'delete error');
          failures++;
          hilog.error(LOG_DOMAIN, LOG_TAG, 'flush delete threw %{public}s', `${err}`);
        }
        continue;
      }
      const task = await this.repository.getTask(operation.taskId);
      if (task === undefined) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'flush put skip not found taskId=%{public}s', operation.taskId);
        await this.repository.removeOperation(operation.id);
        continue;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'flush put taskId=%{public}s title=%{public}s', task.id, task.title);
      try {
        let result = await client.putTask(task);
        if (!result.ok && (result.status === 409 || result.status === 412) && task.href.length > 0) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'flush stale etag, retry latest taskId=%{public}s', task.id);
          result = await client.putTask(task, true);
        }
        if (result.ok) {
          await this.repository.markTaskSyncState(task.id, 'synced', result.etag);
          await this.repository.removePutOperations(task.id);
        } else if (result.status === 409 || result.status === 412) {
          await this.repository.markTaskSyncState(task.id, 'conflict');
          await this.repository.updateOperationFailure(operation, `HTTP ${result.status}`);
          failures++;
        } else {
          await this.repository.markTaskSyncState(task.id, 'error');
          await this.repository.updateOperationFailure(operation, `HTTP ${result.status}`);
          failures++;
        }
      } catch (err) {
        await this.repository.updateOperationFailure(operation, JSON.stringify(err));
        failures++;
      }
    }
    return failures;
  }

  private formatReminderDiagnostics(summary: ReminderSyncSummary): string {
    const lines: string[] = [
      `通知开关：${summary.notificationsEnabled ? '已开启' : '未开启'}`,
      `进行中待办：${summary.activeTaskCount}`,
      `带提醒待办：${summary.reminderTaskCount}`,
      `发布结果：成功 ${summary.publishedCount} / 跳过 ${summary.skippedCount} / 失败 ${summary.failedCount}`,
      `清理前系统提醒：${summary.beforeClearCount < 0 ? '读取失败' : summary.beforeClearCount}`,
      `清理后系统提醒：${summary.afterClearCount < 0 ? '读取失败' : summary.afterClearCount}`,
      `系统已注册提醒：${summary.registeredCount}`
    ];
    const published = summary.publishResults.filter((item) => item.status !== 'skipped').slice(0, 5);
    if (published.length > 0) {
      lines.push('待办提醒：');
      for (let i = 0; i < published.length; i++) {
        const item = published[i];
        lines.push(`- 《${item.title}》 ${item.triggerAt} ${item.detail}`);
      }
    }
    if (summary.registeredResults.length > 0) {
      lines.push('系统提醒：');
      for (let i = 0; i < Math.min(summary.registeredResults.length, 5); i++) {
        lines.push(`- ${summary.registeredResults[i]}`);
      }
    }
    if (summary.errors.length > 0) {
      lines.push('异常：');
      for (let i = 0; i < Math.min(summary.errors.length, 3); i++) {
        lines.push(`- ${summary.errors[i]}`);
      }
    }
    if (summary.reminderTaskCount > 0 && summary.registeredCount === 0) {
      lines.push('结论：应用有提醒任务，但系统里没有注册成功。');
    }
    return lines.join('\n');
  }
}
