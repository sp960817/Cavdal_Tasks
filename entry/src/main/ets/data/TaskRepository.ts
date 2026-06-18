import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import asset from '@ohos.security.asset';
import { AccountSettings, CalendarSource, SyncOperation, TodoTask, WidgetBlurStyle, WidgetPayload, WidgetTask } from '../model/TaskModels';

const DB_NAME = 'cavdal_tasks.db';
const PREF_NAME = 'cavdal_settings';
const PASSWORD_ALIAS = 'cavdal-password';

function str(value: relationalStore.ValueType): string {
  return value === null || value === undefined ? '' : `${value}`;
}

function num(value: relationalStore.ValueType): number {
  if (typeof value === 'number') {
    return value;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function widgetBlurStyle(value: string): WidgetBlurStyle {
  if (value === 'none' || value === 'thin' || value === 'thick') {
    return value;
  }
  return 'regular';
}

function encode(value: string): Uint8Array {
  const result = new Uint8Array(value.length);
  for (let i = 0; i < value.length; i++) {
    result[i] = value.charCodeAt(i) & 0xff;
  }
  return result;
}

function decode(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

export class CredentialStore {
  private static aliasQuery(): asset.AssetMap {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, encode(PASSWORD_ALIAS));
    return query;
  }

  static async savePassword(password: string): Promise<void> {
    try {
      await asset.remove(CredentialStore.aliasQuery());
    } catch (_err) {
    }
    const data = CredentialStore.aliasQuery();
    data.set(asset.Tag.SECRET, encode(password));
    await asset.add(data);
  }

  static async loadPassword(): Promise<string> {
    try {
      const query = CredentialStore.aliasQuery();
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result = await asset.query(query);
      if (result.length === 0) {
        return '';
      }
      const secret = result[0].get(asset.Tag.SECRET) as Uint8Array;
      return secret === undefined ? '' : decode(secret);
    } catch (_err) {
      return '';
    }
  }

  static async clearPassword(): Promise<void> {
    try {
      await asset.remove(CredentialStore.aliasQuery());
    } catch (_err) {
    }
  }
}

export class SettingsStore {
  private pref?: preferences.Preferences;

  constructor(private context: common.Context) {
  }

  private async prefs(): Promise<preferences.Preferences> {
    if (this.pref === undefined) {
      this.pref = await preferences.getPreferences(this.context, PREF_NAME);
    }
    return this.pref;
  }

  async load(): Promise<AccountSettings> {
    const pref = await this.prefs();
    return {
      serverUrl: `${await pref.get('serverUrl', '')}`,
      username: `${await pref.get('username', '')}`,
      calendarHref: `${await pref.get('calendarHref', '')}`,
      calendarName: `${await pref.get('calendarName', '')}`,
      lastSyncAt: Number(await pref.get('lastSyncAt', 0)),
      widgetBlurStyle: widgetBlurStyle(`${await pref.get('widgetBlurStyle', 'regular')}`)
    };
  }

  async save(settings: AccountSettings): Promise<void> {
    const pref = await this.prefs();
    await pref.put('serverUrl', settings.serverUrl);
    await pref.put('username', settings.username);
    await pref.put('calendarHref', settings.calendarHref);
    await pref.put('calendarName', settings.calendarName);
    await pref.put('lastSyncAt', settings.lastSyncAt);
    await pref.put('widgetBlurStyle', settings.widgetBlurStyle);
    await pref.flush();
  }

  async clear(): Promise<void> {
    const pref = await this.prefs();
    await pref.clear();
    await pref.flush();
    await CredentialStore.clearPassword();
  }
}

export class TaskRepository {
  private store?: relationalStore.RdbStore;

  constructor(private context: common.Context) {
  }

  private async db(): Promise<relationalStore.RdbStore> {
    if (this.store === undefined) {
      this.store = await relationalStore.getRdbStore(this.context, {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      });
      await this.migrate(this.store);
    }
    return this.store;
  }

  private async migrate(store: relationalStore.RdbStore): Promise<void> {
    // All statements use IF NOT EXISTS — safe to run every time
    await store.executeSql('CREATE TABLE IF NOT EXISTS tasks (' +
      'id TEXT PRIMARY KEY, uid TEXT, href TEXT, calendar_href TEXT, etag TEXT, title TEXT, description TEXT, due TEXT, ' +
      'priority INTEGER, status TEXT, completed_at TEXT, percent_complete INTEGER, raw_ics TEXT, sync_state TEXT, updated_at INTEGER)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS calendars (' +
      'href TEXT PRIMARY KEY, display_name TEXT, supports_vtodo INTEGER, ctag TEXT)');
    await store.executeSql('CREATE TABLE IF NOT EXISTS sync_queue (' +
      'id TEXT PRIMARY KEY, task_id TEXT, type TEXT, payload TEXT, created_at INTEGER, attempts INTEGER, last_error TEXT)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_tasks_sync_state ON tasks(sync_state)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_sync_queue_task_id ON sync_queue(task_id)');
  }

  async saveTask(task: TodoTask): Promise<void> {
    const store = await this.db();
    await store.executeSql('INSERT OR REPLACE INTO tasks ' +
      '(id,uid,href,calendar_href,etag,title,description,due,priority,status,completed_at,percent_complete,raw_ics,sync_state,updated_at) ' +
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
      task.id, task.uid, task.href, task.calendarHref, task.etag, task.title, task.description, task.due,
      task.priority, task.status, task.completedAt, task.percentComplete, task.rawIcs, task.syncState, task.updatedAt
    ]);
  }

  async saveTasks(tasks: TodoTask[]): Promise<void> {
    if (tasks.length === 0) {
      return;
    }
    const store = await this.db();
    await store.beginTransaction();
    try {
      for (let i = 0; i < tasks.length; i++) {
        await this.saveTaskInternal(store, tasks[i]);
      }
      await store.commit();
    } catch (err) {
      await store.rollback(0);
      throw err;
    }
  }

  private async saveTaskInternal(store: relationalStore.RdbStore, task: TodoTask): Promise<void> {
    await store.executeSql('INSERT OR REPLACE INTO tasks ' +
      '(id,uid,href,calendar_href,etag,title,description,due,priority,status,completed_at,percent_complete,raw_ics,sync_state,updated_at) ' +
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
      task.id, task.uid, task.href, task.calendarHref, task.etag, task.title, task.description, task.due,
      task.priority, task.status, task.completedAt, task.percentComplete, task.rawIcs, task.syncState, task.updatedAt
    ]);
  }

  async getTask(id: string): Promise<TodoTask | undefined> {
    const rows = await this.queryTasks('SELECT * FROM tasks WHERE id = ?', [id]);
    return rows.length === 0 ? undefined : rows[0];
  }

  async activeTasks(): Promise<TodoTask[]> {
    return this.queryTasks("SELECT * FROM tasks WHERE status <> 'COMPLETED' ORDER BY due = '', due ASC, priority DESC, updated_at DESC", []);
  }

  async completedTasks(limit: number = 20): Promise<TodoTask[]> {
    return this.queryTasks('SELECT * FROM tasks WHERE status = ? ORDER BY updated_at DESC LIMIT ?', ['COMPLETED', limit]);
  }

  async pendingCount(): Promise<number> {
    const store = await this.db();
    const result = await store.querySql("SELECT COUNT(*) AS cnt FROM tasks WHERE sync_state = 'pending'", []);
    let count = 0;
    if (result.goToFirstRow()) {
      count = result.getLong(result.getColumnIndex('cnt'));
    }
    result.close();
    return count;
  }

  async clearTasks(): Promise<void> {
    const store = await this.db();
    await store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM tasks');
      await store.executeSql('DELETE FROM sync_queue');
      await store.commit();
    } catch (err) {
      await store.rollback(0);
      throw err;
    }
  }

  async getTaskCount(): Promise<number> {
    const store = await this.db();
    const result = await store.querySql('SELECT COUNT(*) AS cnt FROM tasks', []);
    let count = 0;
    if (result.goToFirstRow()) {
      count = result.getLong(result.getColumnIndex('cnt'));
    }
    result.close();
    return count;
  }

  async deleteTask(id: string): Promise<void> {
    const store = await this.db();
    await store.executeSql('DELETE FROM tasks WHERE id = ?', [id]);
    await store.executeSql('DELETE FROM sync_queue WHERE task_id = ?', [id]);
  }

  private async queryTasks(sql: string, args: relationalStore.ValueType[]): Promise<TodoTask[]> {
    const store = await this.db();
    const result = await store.querySql(sql, args);
    const out: TodoTask[] = [];
    while (result.goToNextRow()) {
      out.push({
        id: result.getString(result.getColumnIndex('id')),
        uid: result.getString(result.getColumnIndex('uid')),
        href: result.getString(result.getColumnIndex('href')),
        calendarHref: result.getString(result.getColumnIndex('calendar_href')),
        etag: result.getString(result.getColumnIndex('etag')),
        title: result.getString(result.getColumnIndex('title')),
        description: result.getString(result.getColumnIndex('description')),
        due: result.getString(result.getColumnIndex('due')),
        priority: result.getLong(result.getColumnIndex('priority')),
        status: result.getString(result.getColumnIndex('status')),
        completedAt: result.getString(result.getColumnIndex('completed_at')),
        percentComplete: result.getLong(result.getColumnIndex('percent_complete')),
        rawIcs: result.getString(result.getColumnIndex('raw_ics')),
        syncState: result.getString(result.getColumnIndex('sync_state')) as 'synced' | 'pending' | 'conflict' | 'error',
        updatedAt: result.getLong(result.getColumnIndex('updated_at'))
      });
    }
    result.close();
    return out;
  }

  async saveCalendars(calendars: CalendarSource[]): Promise<void> {
    const store = await this.db();
    await store.executeSql('DELETE FROM calendars');
    for (let i = 0; i < calendars.length; i++) {
      const calendar = calendars[i];
      await store.executeSql('INSERT OR REPLACE INTO calendars (href,display_name,supports_vtodo,ctag) VALUES (?,?,?,?)',
        [calendar.href, calendar.displayName, calendar.supportsVTodo ? 1 : 0, calendar.ctag]);
    }
  }

  async calendars(): Promise<CalendarSource[]> {
    const store = await this.db();
    const result = await store.querySql('SELECT * FROM calendars ORDER BY display_name', []);
    const out: CalendarSource[] = [];
    while (result.goToNextRow()) {
      out.push({
        href: result.getString(result.getColumnIndex('href')),
        displayName: result.getString(result.getColumnIndex('display_name')),
        supportsVTodo: result.getLong(result.getColumnIndex('supports_vtodo')) === 1,
        ctag: result.getString(result.getColumnIndex('ctag'))
      });
    }
    result.close();
    return out;
  }

  async enqueue(operation: SyncOperation): Promise<void> {
    const store = await this.db();
    if (operation.type === 'put') {
      await store.executeSql("DELETE FROM sync_queue WHERE task_id = ? AND type = 'put'", [operation.taskId]);
    }
    await store.executeSql('INSERT OR REPLACE INTO sync_queue (id,task_id,type,payload,created_at,attempts,last_error) VALUES (?,?,?,?,?,?,?)',
      [operation.id, operation.taskId, operation.type, operation.payload, operation.createdAt, operation.attempts, operation.lastError]);
  }

  async pendingOperations(): Promise<SyncOperation[]> {
    const store = await this.db();
    const result = await store.querySql('SELECT * FROM sync_queue ORDER BY created_at', []);
    const out: SyncOperation[] = [];
    while (result.goToNextRow()) {
      out.push({
        id: result.getString(result.getColumnIndex('id')),
        taskId: result.getString(result.getColumnIndex('task_id')),
        type: result.getString(result.getColumnIndex('type')) as 'put',
        payload: result.getString(result.getColumnIndex('payload')),
        createdAt: result.getLong(result.getColumnIndex('created_at')),
        attempts: result.getLong(result.getColumnIndex('attempts')),
        lastError: result.getString(result.getColumnIndex('last_error'))
      });
    }
    result.close();
    return out;
  }

  async removeOperation(id: string): Promise<void> {
    const store = await this.db();
    await store.executeSql('DELETE FROM sync_queue WHERE id = ?', [id]);
  }

  async removePutOperations(taskId: string): Promise<void> {
    const store = await this.db();
    await store.executeSql("DELETE FROM sync_queue WHERE task_id = ? AND type = 'put'", [taskId]);
  }

  async updateOperationFailure(operation: SyncOperation, error: string): Promise<void> {
    const store = await this.db();
    await store.executeSql('UPDATE sync_queue SET attempts = ?, last_error = ? WHERE id = ?',
      [operation.attempts + 1, error, operation.id]);
  }

  async markTaskSyncState(taskId: string, state: string, etag: string = ''): Promise<void> {
    const store = await this.db();
    if (state === 'synced' || etag.length > 0) {
      await store.executeSql('UPDATE tasks SET sync_state = ?, etag = ? WHERE id = ?', [state, etag, taskId]);
    } else {
      await store.executeSql('UPDATE tasks SET sync_state = ? WHERE id = ?', [state, taskId]);
    }
  }

  async widgetPayload(lastSyncAt: number): Promise<WidgetPayload> {
    const active = await this.activeTasks();
    const pending = await this.pendingCount();
    const tasks: WidgetTask[] = active.slice(0, 20).map((task: TodoTask): WidgetTask => ({
      id: task.id,
      title: task.title,
      due: task.due,
      syncState: task.syncState
    }));
    return {
      tasks,
      pendingCount: pending,
      lastSyncText: lastSyncAt > 0 ? new Date(lastSyncAt).toLocaleString() : '未同步'
    };
  }
}
