// Run with DevEco's bundled Node.js. Uses the installed SDK's TypeScript
// compiler and mocked system APIs; no device or additional packages required.
// This checks application behavior, not the OS scheduler or physical vibration.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.HARMONY_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const sourceRoot = path.resolve(__dirname, '../entry/src/main/ets');
const log = { info() {}, warn() {}, error() {} };
const turn = () => new Promise(resolve => setImmediate(resolve));
const pending = () => new Promise(() => {});

function loader(mocks = {}, globals = {}) {
  const cache = new Map();
  function load(relative, parent = sourceRoot) {
    if (Object.hasOwn(mocks, relative)) return mocks[relative];
    let filename = path.resolve(parent, relative);
    if (!fs.existsSync(filename)) filename += fs.existsSync(filename + '.ts') ? '.ts' : '.ets';
    if (cache.has(filename)) return cache.get(filename).exports;
    const module = { exports: {} };
    cache.set(filename, module);
    const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      fileName: filename.replace(/\.ets$/, '.ts'),
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    });
    vm.runInNewContext(result.outputText, {
      module, exports: module.exports,
      require: name => {
        if (Object.hasOwn(mocks, name)) return mocks[name];
        if (name === '@kit.PerformanceAnalysisKit') return { hilog: log };
        if (!name.startsWith('.')) throw new Error(`Missing mock: ${name}`);
        return load(name, path.dirname(filename));
      },
      Date, Promise, setTimeout, clearTimeout, console: log, ...globals
    }, { filename });
    return module.exports;
  }
  return load;
}

const settings = {
  serverUrl: 'https://example.invalid', username: 'test', calendarHref: '/tasks/',
  calendarName: 'Tasks', lastSyncAt: 0, widgetBlurStyle: 'thin', handednessEnabled: false
};

function syncFixture({ fetchTodos = async () => [], reminders = async () => {}, operations = [], globals = {}, putTask } = {}) {
  const events = [];
  const mocks = {
    '../data/TaskRepository': {
      SettingsStore: class {
        async load() { return { ...settings }; }
        async saveLastSyncAt() { events.push('timestamp'); }
      },
      CredentialStore: { async loadPassword() { return 'test'; } },
      TaskRepository: class {
        async pendingOperations() { return operations; }
        async saveRemoteSnapshot() { events.push('snapshot'); }
        async activeTasks() { return []; }
        async getTask(id) { return { id, href: '/tasks/test.ics', rawIcs: '' }; }
        async markTaskSyncState() {}
        async removePutOperations(id) { events.push(`removed:${id}`); }
        async updateOperationFailure() { events.push('failed-write'); }
      }
    },
    '../caldav/CalDavClient': { CalDavClient: class {
      constructor(_credentials, deadline) { events.push(deadline > 0 ? 'bounded' : 'foreground'); }
      async fetchTodos() { events.push('fetch'); return fetchTodos(); }
      async putTask(task) { events.push(`put:${task.id}`); return putTask(task); }
    } },
    '../reminder/ReminderService': { ReminderService: class {
      async syncTasks() { events.push('reminders'); return reminders(); }
    } },
    '../widget/WidgetUpdater': { WidgetUpdater: { async updateAllForms() { events.push('widget'); } } }
  };
  return { events, SyncService: loader(mocks, globals)('sync/SyncService.ts').SyncService };
}

test('fresh server data reaches cards while reminder registration is still pending', async () => {
  let finish;
  const wait = new Promise(resolve => { finish = resolve; });
  const { SyncService, events } = syncFixture({ reminders: () => wait });
  const syncing = new SyncService({}).syncNow(true);
  try {
    await turn();
    assert.equal(events.join(','), 'bounded,fetch,snapshot,timestamp,widget,reminders');
  } finally {
    finish();
  }
  assert.equal((await syncing).ok, true);
});

test('offline refresh keeps the cache and releases the sync lock for retry', async () => {
  let offline = true;
  const { SyncService, events } = syncFixture({ fetchTodos: async () => {
    if (offline) throw new Error('offline');
    return [];
  } });
  const service = new SyncService({});
  assert.equal((await service.syncNow(true)).ok, false);
  assert.equal(events.includes('snapshot'), false);
  assert.equal(events.includes('timestamp'), false);
  assert.equal(events.at(-1), 'widget');
  offline = false;
  assert.equal((await service.syncNow(true)).ok, true);
});

test('background deadline leaves unattempted writes in the persistent queue', async () => {
  let now = 1000;
  class TestDate extends Date { static now() { return now; } }
  const { SyncService, events } = syncFixture({
    globals: { Date: TestDate },
    operations: [{ taskId: 'first', type: 'put' }, { taskId: 'second', type: 'put' }],
    putTask: async () => { now += 6001; return { ok: true, etag: 'new' }; },
    fetchTodos: async () => { throw new Error('deadline'); }
  });
  assert.equal((await new SyncService({}).syncNow(true)).ok, false);
  assert.equal(events.includes('put:first'), true);
  assert.equal(events.includes('put:second'), false);
  assert.equal(events.includes('removed:second'), false);
});

function formFixture({ registrationFails = false } = {}) {
  const events = [];
  const FormAbility = loader({
    '@kit.FormKit': {
      FormExtensionAbility: class {},
      formInfo: { FormParam: { HOST_BG_INVERSE_COLOR_KEY: 'color', DIMENSION_KEY: 'dimension' } },
      formBindingData: { createFormBindingData: data => data },
      formProvider: { async updateForm(id, data) { events.push(`update:${id}:${data.pendingCount}`); } }
    },
    '../data/TaskRepository': { TaskRepository: class {
      async widgetPayload() { return { tasks: [], pendingCount: 3, lastSyncText: 'cached' }; }
    } },
    '../sync/SyncService': { SyncService: class {
      async loadSettings() { return settings; }
      async syncNow(bounded) { events.push(`sync:${bounded}`); return pending(); }
      async setTaskCompletedLocally(id) { events.push(`complete:${id}`); return true; }
    } },
    '../widget/WidgetUpdater': { WidgetUpdater: {
      async registerForm() {
        if (registrationFails) throw new Error('registry unavailable');
        events.push('register');
      },
      async savedTextColor() { return '#80000000'; }
    } }
  })('entryformability/EntryFormAbility.ets').default;
  const form = new FormAbility();
  form.context = { getApplicationContext() { return {}; } };
  return { form, events };
}

test('scheduled refresh delivers cached data before a stalled network sync', async () => {
  const { form, events } = formFixture();
  form.onUpdateForm('card');
  await turn();
  assert.equal(events.join(','), 'register,update:card:3,sync:true');
});

test('newly added cards also fetch remote data with the app closed', async () => {
  const { form, events } = formFixture();
  form.onAddForm({ parameters: { formId: 'new-card', dimension: 2 } });
  await turn();
  assert.equal(events.join(','), 'register,update:new-card:3,sync:true');
});

test('registry failure still allows the known card to receive local data', async () => {
  const { form, events } = formFixture({ registrationFails: true });
  form.onUpdateForm('card');
  await turn();
  assert.equal(events.join(','), 'update:card:3,sync:true');
});

test('card completion persists locally before starting bounded synchronization', async () => {
  const { form, events } = formFixture();
  form.onFormEvent('card', JSON.stringify({ operation: 'complete', taskId: 'task' }));
  await turn();
  assert.equal(events.join(','), 'complete:task,sync:true');
});

function httpClientFixture(request) {
  return loader({
    '@kit.NetworkKit': { http: { createHttp: request, HttpDataType: { STRING: 0 } } },
    '@ohos.util': { default: { Base64Helper: class { encodeToStringSync() { return 'test'; } } } },
    '../utils/TextCodec': { utf8Bytes: text => Buffer.from(text) }
  })('caldav/CalDavClient.ts').CalDavClient;
}

test('a hung request is cancelled and rejected without starting a fallback after the deadline', { timeout: 2000 }, async () => {
  let created = 0;
  let destroyed = 0;
  const Client = httpClientFixture(() => {
    created++;
    return { request: pending, destroy() { destroyed++; } };
  });
  const client = new Client(settings, Date.now() + 30);
  await assert.rejects(client.fetchTodos('/tasks/'), /超时/);
  assert.equal(created, 1);
  assert.ok(destroyed > 0);
});

test('foreground synchronization retains its normal timeout', async () => {
  let options;
  const Client = httpClientFixture(() => ({
    async request(_url, value) { options = value; return { responseCode: 207, result: '' }; },
    destroy() {}
  }));
  await new Client(settings).fetchTodos('/tasks/');
  assert.equal(options.connectTimeout, 30000);
  assert.equal(options.readTimeout, 30000);
});

const formatter = loader()('formatters/ReminderFormatter.ts');
test('notification content keeps a stable due date and omits duplicate task text', () => {
  assert.equal(formatter.formatReminderContent('买牛奶', '买牛奶', '20261023T060000Z', '无'),
    '截止 2026年10月23日 14:00');
  assert.equal(formatter.formatReminderContent('买牛奶', '  顺路\n去超市  ', '20261023', '无'),
    '截止 2026年10月23日 · 全天\n顺路 去超市');
});

test('recurring notification text does not display the original expired date', () => {
  assert.equal(formatter.formatReminderContent('周报', '', '20200103T060000Z', '每周'), '每周五 14:00');
  assert.equal(formatter.formatReminderContent('喝水', '', '20200103T060000Z', '每天'), '每天 14:00');
  assert.equal(formatter.formatReminderContent('记账', '', '20200103', '每月'), '每月3日 · 全天');
});

test('long notification titles preserve emoji and fall back for empty titles', () => {
  assert.equal(formatter.formatReminderTitle('  '), '待办提醒');
  const title = formatter.formatReminderTitle('🌱'.repeat(100));
  assert.equal(Array.from(title).length, 80);
  assert.equal(title.endsWith('🌱…'), true);
});
