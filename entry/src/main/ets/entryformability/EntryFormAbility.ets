import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountSettings, WidgetPayload } from '../model/TaskModels';
import { TaskRepository } from '../data/TaskRepository';
import { SyncService } from '../sync/SyncService';
import { WidgetUpdater } from '../widget/WidgetUpdater';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CavdalWidget';

interface FormMessage {
  action: string;
  taskId: string;
  operation?: string;
  params?: FormMessageParams;
}

interface FormMessageParams {
  operation?: string;
  taskId?: string;
}

const EMPTY_SETTINGS: AccountSettings = {
  serverUrl: '', username: '', calendarHref: '', calendarName: '', lastSyncAt: 0, widgetBlurStyle: 'thin'
};

const EMPTY_PAYLOAD: WidgetPayload = {
  tasks: [], pendingCount: 0, lastSyncText: '读取失败'
};

export default class EntryFormAbility extends FormExtensionAbility {
  private async createData(): Promise<formBindingData.FormBindingData> {
    // 使用应用级上下文与主应用共享数据存储
    const appCtx = this.context.getApplicationContext();
    const syncService = new SyncService(appCtx);
    const repository = new TaskRepository(appCtx);
    let settings: AccountSettings = EMPTY_SETTINGS;
    try {
      settings = await syncService.loadSettings();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'createData settings lastSync=%{public}d href=%{public}s', settings.lastSyncAt, settings.calendarHref);
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'createData loadSettings failed %{public}s', `${err}`);
    }
    let payload: WidgetPayload = EMPTY_PAYLOAD;
    try {
      payload = await repository.widgetPayload(settings.lastSyncAt);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'createData payload tasks=%{public}d pending=%{public}d', payload.tasks.length, payload.pendingCount);
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'createData widgetPayload failed %{public}s', `${err}`);
    }
    const bindingData: Record<string, string> = {
      'tasksJson': JSON.stringify(payload.tasks),
      'pendingCount': `${payload.pendingCount}`,
      'lastSyncText': payload.lastSyncText,
      'widgetBlurStyle': settings.widgetBlurStyle
    };
    hilog.info(LOG_DOMAIN, LOG_TAG, 'createData done tasksJson=%{public}s', bindingData['tasksJson']);
    // createFormBindingData 接收一个对象，系统会自动包装为 FormBindingData
    return formBindingData.createFormBindingData(bindingData);
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onAddForm called');
    try {
      const params = want.parameters as Record<string, Object> | undefined;
      let rawId: Object | undefined = undefined;
      if (params !== undefined) {
        if (params['ohos.extra.param.key.form_identity'] !== undefined) {
          rawId = params['ohos.extra.param.key.form_identity'];
        } else if (params['ohos.extra.param.key.formId'] !== undefined) {
          rawId = params['ohos.extra.param.key.formId'];
        } else if (params['formId'] !== undefined) {
          rawId = params['formId'];
        }
      }
      const formId = rawId !== undefined ? `${rawId}` : '';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'onAddForm formId=%{public}s', formId);
      if (formId.length > 0) {
        WidgetUpdater.registerForm(this.context.getApplicationContext(), formId).catch(() => {
        });
        this.createData().then((data: formBindingData.FormBindingData) => {
          formProvider.updateForm(formId, data);
          hilog.info(LOG_DOMAIN, LOG_TAG, 'onAddForm updateForm ok id=%{public}s', formId);
        }).catch((err: Object) => {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'onAddForm updateForm failed %{public}s', `${err}`);
        });
      }
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'onAddForm formId extract failed %{public}s', `${err}`);
    }
    return formBindingData.createFormBindingData({
      tasksJson: '[]',
      pendingCount: '0',
      lastSyncText: '载入中',
      widgetBlurStyle: 'thin'
    });
  }

  onUpdateForm(formId: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onUpdateForm id=%{public}s', formId);
    WidgetUpdater.registerForm(this.context.getApplicationContext(), formId).catch(() => {
    });
    const appCtx = this.context.getApplicationContext();
    new SyncService(appCtx).syncNow().catch((err: Object) => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'onUpdateForm sync failed %{public}s', `${err}`);
    }).then(() => this.createData()).then((data: formBindingData.FormBindingData) => {
      formProvider.updateForm(formId, data);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'onUpdateForm updateForm ok id=%{public}s', formId);
    }).catch((err: Object) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'onUpdateForm failed %{public}s', `${err}`);
    });
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onFormEvent id=%{public}s msg=%{public}s', formId, message);
    let parsed: FormMessage = { action: '', taskId: '' };
    try {
      parsed = JSON.parse(message) as FormMessage;
    } catch (_err) {
      parsed = { action: 'message', operation: 'complete', taskId: message };
    }
    const operation = parsed.operation ?? parsed.params?.operation ?? '';
    const taskId = parsed.taskId ?? parsed.params?.taskId ?? '';
    if (operation === 'complete' && taskId.length > 0) {
      const appCtx = this.context.getApplicationContext();
      const syncService = new SyncService(appCtx);
      syncService.setTaskCompleted(taskId, true).then(() => {
        return this.createData();
      }).then((data: formBindingData.FormBindingData) => {
        setTimeout(() => {
          formProvider.updateForm(formId, data);
          hilog.info(LOG_DOMAIN, LOG_TAG, 'onFormEvent complete ok id=%{public}s', formId);
        }, 700);
      }).catch((err: Object) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'onFormEvent complete failed %{public}s', `${err}`);
      });
    }
  }

  onRemoveForm(formId: string): void {
    WidgetUpdater.unregisterForm(this.context.getApplicationContext(), formId).catch(() => {
    });
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
