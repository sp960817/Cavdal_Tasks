import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import asset from '@ohos.security.asset';
import { AccountSettings, CalendarSource, SyncOperation, TodoTask, WidgetBlurStyle, WidgetPayload, WidgetTask } from '../model/TaskModels';
import { VTodoCodec } from '../caldav/VTodoCodec';

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
  if (value === 'none' || value === 'thin' || value === 'regular' || value === 'thick') {
    return value;
  }
  return 'thin';
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

function errorText(err: Object): string {
  try {
    return JSON.stringify(err);
  } catch (_jsonErr) {
    return `${err}`;
  }
}

export class CredentialStore {
  private static aliasQuery(): asset.AssetMap {
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, encode(PASSWORD_ALIAS));
    return query;
  }

  static async savePassword(password: string): Promise<void> {
    try {
      try {
        await asset.remove(CredentialStore.aliasQuery());
      } catch (_err) {
      }
      const data = CredentialStore.aliasQuery();
      data.set(asset.Tag.SECRET, encode(password));
      await asset.add(data);
    } catch (err) {
      console.error(`[CredentialStore] savePassword failed: ${errorText(err)}`);
      throw new Error(`savePassword failed: ${errorText(err)}`);
    }
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
    try {
      if (this.pref === undefined) {
        this.pref = await preferences.getPreferences(this.context, PREF_NAME);
      }
      return this.pref;
    } catch (err) {
      console.error(`[SettingsStore] prefs failed: ${errorText(err)}`);
      throw new Error(`prefs failed: ${errorText(err)}`);
    }
  }

  async load(): Promise<AccountSettings> {
    try {
      const pref = await this.prefs();
      return {
        serverUrl: `${await pref.get('serverUrl', '')}`,
        username: `${await pref.get('username', '')}`,
        calendarHref: `${await pref.get('calendarHref', '')}`,
        calendarName: `${await pref.get('calendarName', '')}`,
        lastSyncAt: Number(await pref.get('lastSyncAt', 0)),
        widgetBlurStyle: widgetBlurStyle(`${await pref.get('widgetBlurStyle', 'thin')}`)
      };
    } catch (err) {
      console.error(`[SettingsStore] load failed: ${errorText(err)}`);
      throw new Error(`load settings failed: ${errorText(err)}`);
    }
  }

  async save(settings: AccountSettings): Promise<void> {
    try {
      const pref = await this.prefs();
      await pref.put('serverUrl', settings.serverUrl);
      await pref.put('username', settings.username);
      await pref.put('calendarHref', settings.calendarHref);
      await pref.put('calendarName', settings.calendarName);
      await pref.put('lastSyncAt', settings.lastSyncAt);
      await pref.put('widgetBlurStyle', settings.widgetBlurStyle);
      await pref.flush();
    } catch (err) {
      console.error(`[SettingsStore] save failed: ${errorText(err)}`);
      throw new Error(`save settings failed: ${errorText(err)}`);
    }
  }

  async clear(): Promise<void> {
    try {
      const pref = await this.prefs();
      await pref.clear();
      await pref.flush();
      await CredentialStore.clearPassword();
    } catch (err) {
      console.error(`[SettingsStore] clear failed: ${errorText(err)}`);
      throw new Error(`clear settings failed: ${errorText(err)}`);
    }
  }
}

export class TaskRepository {
  private store?: relationalStore.RdbStore;

  constructor(private context: common.Context) {
  }

  private fail<T>(operation: string, err: Object): T {
    const message = errorText(err);
    console.error(`[TaskRepository] ${operation} failed: ${message}`);
    throw new Error(`${operation} failed: ${message}`);
  }

  private closeResult(result?: relationalStore.ResultSet): void {
    if (result === undefined) {
      return;
    }
    try {
      result.close();
    } catch (err) {
      console.error(`[TaskRepository] close result failed: ${errorText(err)}`);
    }
  }

  private async rollbackQuietly(store: relationalStore.RdbStore, operation: string): Promise<void> {
    try {
      await store.rollback(0);
    } catch (err) {
      console.error(`[TaskRepository] ${operation} rollback failed: ${errorText(err)}`);
    }
  }

  private async withTransaction<T>(operation: string,
    action: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    const store = await this.db();
    try {
      await store.beginTransaction();
      const result = await action(store);
      await store.commit();
      return result;
    } catch (err) {
      await this.rollbackQuietly(store, operation);
      return this.fail<T>(operation, err);
    }
  }

  private async db(): Promise<relationalStore.RdbStore> {
    try {
      if (this.store === undefined) {
        this.store = await relationalStore.getRdbStore(this.context, {
          name: DB_NAME,
          securityLevel: relationalStore.SecurityLevel.S1
        });
        await this.migrate(this.store);
      }
      return this.store;
    } catch (err) {
      return this.fail<relationalStore.RdbStore>('open database', err);
    }
  }

  private async migrate(store: relationalStore.RdbStore): Promise<void> {
    try {
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
    } catch (err) {
      this.fail<void>('migrate database', err);
    }
  }

  async saveTask(task: TodoTask): Promise<void> {
    try {
      const store = await this.db();
      await store.executeSql('INSERT OR REPLACE INTO tasks ' +
        '(id,uid,href,calendar_href,etag,title,description,due,priority,status,completed_at,percent_complete,raw_ics,sync_state,updated_at) ' +
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
        task.id, task.uid, task.href, task.calendarHref, task.etag, task.title, task.description, task.due,
        task.priority, task.status, task.completedAt, task.percentComplete, task.rawIcs, task.syncState, task.updatedAt
      ]);
    } catch (err) {
      this.fail<void>('saveTask', err);
    }
  }

  async saveTasks(tasks: TodoTask[]): Promise<void> {
    if (tasks.length === 0) {
      return;
    }
    try {
      await this.withTransaction<void>('saveTasks', async (store: relationalStore.RdbStore) => {
        for (let i = 0; i < tasks.length; i++) {
          await this.saveTaskInternal(store, tasks[i]);
        }
      });
    } catch (err) {
      this.fail<void>('saveTasks', err);
    }
  }

  private async saveTaskInternal(store: relationalStore.RdbStore, task: TodoTask): Promise<void> {
    try {
      await store.executeSql('INSERT OR REPLACE INTO tasks ' +
        '(id,uid,href,calendar_href,etag,title,description,due,priority,status,completed_at,percent_complete,raw_ics,sync_state,updated_at) ' +
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
        task.id, task.uid, task.href, task.calendarHref, task.etag, task.title, task.description, task.due,
        task.priority, task.status, task.completedAt, task.percentComplete, task.rawIcs, task.syncState, task.updatedAt
      ]);
    } catch (err) {
      this.fail<void>('saveTaskInternal', err);
    }
  }

  async getTask(id: string): Promise<TodoTask | undefined> {
    const rows = await this.queryTasks('SELECT * FROM tasks WHERE id = ?', [id]);
    return rows.length === 0 ? undefined : rows[0];
  }

  async activeTasks(): Promise<TodoTask[]> {
    return this.queryTasks("SELECT * FROM tasks WHERE status <> 'COMPLETED' ORDER BY due = '', due ASC, priority DESC, updated_at DESC", []);
  }

  async completedTasks(limit: number = 20): Promise<TodoTask[]> {
    return this.queryTasks('SELECT * FROM tasks WHERE status = ? ORDER BY completed_at DESC LIMIT ?', ['COMPLETED', limit]);
  }

  async pendingCount(): Promise<number> {
    let result: relationalStore.ResultSet | undefined = undefined;
    try {
      const store = await this.db();
      result = await store.querySql("SELECT COUNT(*) AS cnt FROM tasks WHERE sync_state = 'pending'", []);
      let count = 0;
      if (result.goToFirstRow()) {
        count = result.getLong(result.getColumnIndex('cnt'));
      }
      return count;
    } catch (err) {
      return this.fail<number>('pendingCount', err);
    } finally {
      this.closeResult(result);
    }
  }

  async clearTasks(): Promise<void> {
    try {
      await this.withTransaction<void>('clearTasks', async (store: relationalStore.RdbStore) => {
        await store.executeSql('DELETE FROM tasks');
        await store.executeSql('DELETE FROM sync_queue');
      });
    } catch (err) {
      this.fail<void>('clearTasks', err);
    }
  }

  async getTaskCount(): Promise<number> {
    let result: relationalStore.ResultSet | undefined = undefined;
    try {
      const store = await this.db();
      result = await store.querySql('SELECT COUNT(*) AS cnt FROM tasks', []);
      let count = 0;
      if (result.goToFirstRow()) {
        count = result.getLong(result.getColumnIndex('cnt'));
      }
      return count;
    } catch (err) {
      return this.fail<number>('getTaskCount', err);
    } finally {
      this.closeResult(result);
    }
  }

  async deleteTask(id: string): Promise<void> {
    try {
      const store = await this.db();
      await store.executeSql('DELETE FROM tasks WHERE id = ?', [id]);
      await store.executeSql('DELETE FROM sync_queue WHERE task_id = ?', [id]);
    } catch (err) {
      this.fail<void>('deleteTask', err);
    }
  }

  private async queryTasks(sql: string, args: relationalStore.ValueType[]): Promise<TodoTask[]> {
    let result: relationalStore.ResultSet | undefined = undefined;
    try {
      const store = await this.db();
      result = await store.querySql(sql, args);
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
      return out;
    } catch (err) {
      return this.fail<TodoTask[]>('queryTasks', err);
    } finally {
      this.closeResult(result);
    }
  }

  async saveCalendars(calendars: CalendarSource[]): Promise<void> {
    try {
      await this.withTransaction<void>('saveCalendars', async (store: relationalStore.RdbStore) => {
        await store.executeSql('DELETE FROM calendars');
        for (let i = 0; i < calendars.length; i++) {
          const calendar = calendars[i];
          await store.executeSql('INSERT OR REPLACE INTO calendars (href,display_name,supports_vtodo,ctag) VALUES (?,?,?,?)',
            [calendar.href, calendar.displayName, calendar.supportsVTodo ? 1 : 0, calendar.ctag]);
        }
      });
    } catch (err) {
      this.fail<void>('saveCalendars', err);
    }
  }

  async calendars(): Promise<CalendarSource[]> {
    let result: relationalStore.ResultSet | undefined = undefined;
    try {
      const store = await this.db();
      result = await store.querySql('SELECT * FROM calendars ORDER BY display_name', []);
      const out: CalendarSource[] = [];
      while (result.goToNextRow()) {
        out.push({
          href: result.getString(result.getColumnIndex('href')),
          displayName: result.getString(result.getColumnIndex('display_name')),
          supportsVTodo: result.getLong(result.getColumnIndex('supports_vtodo')) === 1,
          ctag: result.getString(result.getColumnIndex('ctag'))
        });
      }
      return out;
    } catch (err) {
      return this.fail<CalendarSource[]>('calendars', err);
    } finally {
      this.closeResult(result);
    }
  }

  async enqueue(operation: SyncOperation): Promise<void> {
    try {
      const store = await this.db();
      if (operation.type === 'put') {
        await store.executeSql("DELETE FROM sync_queue WHERE task_id = ? AND type = 'put'", [operation.taskId]);
      }
      await store.executeSql('INSERT OR REPLACE INTO sync_queue (id,task_id,type,payload,created_at,attempts,last_error) VALUES (?,?,?,?,?,?,?)',
        [operation.id, operation.taskId, operation.type, operation.payload, operation.createdAt, operation.attempts, operation.lastError]);
    } catch (err) {
      this.fail<void>('enqueue', err);
    }
  }

  async pendingOperations(): Promise<SyncOperation[]> {
    let result: relationalStore.ResultSet | undefined = undefined;
    try {
      const store = await this.db();
      result = await store.querySql('SELECT * FROM sync_queue ORDER BY created_at', []);
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
      return out;
    } catch (err) {
      return this.fail<SyncOperation[]>('pendingOperations', err);
    } finally {
      this.closeResult(result);
    }
  }

  async removeOperation(id: string): Promise<void> {
    try {
      const store = await this.db();
      await store.executeSql('DELETE FROM sync_queue WHERE id = ?', [id]);
    } catch (err) {
      this.fail<void>('removeOperation', err);
    }
  }

  async removePutOperations(taskId: string): Promise<void> {
    try {
      const store = await this.db();
      await store.executeSql("DELETE FROM sync_queue WHERE task_id = ? AND type = 'put'", [taskId]);
    } catch (err) {
      this.fail<void>('removePutOperations', err);
    }
  }

  async updateOperationFailure(operation: SyncOperation, error: string): Promise<void> {
    try {
      const store = await this.db();
      await store.executeSql('UPDATE sync_queue SET attempts = ?, last_error = ? WHERE id = ?',
        [operation.attempts + 1, error, operation.id]);
    } catch (err) {
      this.fail<void>('updateOperationFailure', err);
    }
  }

  async markTaskSyncState(taskId: string, state: string, etag: string = ''): Promise<void> {
    try {
      const store = await this.db();
      if (state === 'synced' || etag.length > 0) {
        await store.executeSql('UPDATE tasks SET sync_state = ?, etag = ? WHERE id = ?', [state, etag, taskId]);
      } else {
        await store.executeSql('UPDATE tasks SET sync_state = ? WHERE id = ?', [state, taskId]);
      }
    } catch (err) {
      this.fail<void>('markTaskSyncState', err);
    }
  }

  async widgetPayload(lastSyncAt: number): Promise<WidgetPayload> {
    const active = await this.activeTasks();
    const pending = await this.pendingCount();
    const tasks: WidgetTask[] = active.slice(0, 20).map((task: TodoTask): WidgetTask => ({
      id: task.id,
      title: task.title,
      due: task.due,
      syncState: task.syncState,
      hasReminder: VTodoCodec.detectReminder(task.rawIcs, task.due) !== '无'
    }));
    return {
      tasks,
      pendingCount: pending,
      lastSyncText: lastSyncAt > 0 ? new Date(lastSyncAt).toLocaleString() : '未同步'
    };
  }
}
