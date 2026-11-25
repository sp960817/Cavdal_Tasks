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

interface TextColor {
  mTextColor: string;
  mWallpaperType: number;
}

const EMPTY_SETTINGS: AccountSettings = {
  serverUrl: '', username: '', calendarHref: '', calendarName: '', lastSyncAt: 0, widgetBlurStyle: 'thin',
  handednessEnabled: false, feedingAnimation: true, compactRows: false
};

const EMPTY_PAYLOAD: WidgetPayload = {
  tasks: [], pendingCount: 0, lastSyncText: '读取失败'
};

function extractTextColor(params: Record<string, Object> | undefined): string | undefined {
  if (!params) {
    return undefined;
  }
  const value = params[formInfo.FormParam.HOST_BG_INVERSE_COLOR_KEY];
  if (!value) return undefined;
  const color = typeof value === 'string' ? value : (value as TextColor).mTextColor;
  if (typeof color !== 'string' || !/^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/i.test(color)) return undefined;
  // The launcher supplies a contrasting foreground. Use its hue at full opacity.
  return '#' + color.slice(-6);
}

function extractFormDimension(params: Record<string, Object> | undefined): string | undefined {
  if (!params) {
    return undefined;
  }
  const value = params[formInfo.FormParam.DIMENSION_KEY];
  return value === undefined ? undefined : `${value}`;
}

export default class EntryFormAbility extends FormExtensionAbility {
  private async refreshForm(formId: string, textColor?: string, formDimension?: string): Promise<void> {
    const appCtx = this.context.getApplicationContext();
    try {
      await WidgetUpdater.registerForm(appCtx, formId);
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'form registry failed %{public}s', `${err}`);
    }
    // Always deliver cached data first, including changes to the date window.
    // A slow/offline server must not prevent this lifecycle from updating UI.
    try {
      await formProvider.updateForm(formId, await this.createData(textColor, formDimension));
      hilog.info(LOG_DOMAIN, LOG_TAG, 'cached form updated id=%{public}s', formId);
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'cached form update failed %{public}s', `${err}`);
    }
    // SyncService publishes the fresh snapshot to all forms before registering
    // reminders, using a shared six-second network deadline for this callback.
    const result = await new SyncService(appCtx).syncNow(true);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'form sync id=%{public}s ok=%{public}s: %{public}s',
      formId, `${result.ok}`, result.message);
  }

  private async createData(textColor?: string, formDimension?: string): Promise<formBindingData.FormBindingData> {
    // 使用应用级上下文与主应用共享数据存储
    const appCtx = this.context.getApplicationContext();
    const syncService = new SyncService(appCtx);
    const repository = new TaskRepository(appCtx);
    let settings: AccountSettings = EMPTY_SETTINGS;
    try {
      settings = await syncService.loadSettings();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'createData settings lastSync=%{public}d', settings.lastSyncAt);
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
    if (textColor !== undefined) {
      bindingData['hostTextColor'] = textColor;
    }
    if (formDimension !== undefined) {
      bindingData['formDimension'] = formDimension;
    }
    // createFormBindingData 接收一个对象，系统会自动包装为 FormBindingData
    return formBindingData.createFormBindingData(bindingData);
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onAddForm called');
    const textColor = extractTextColor(want.parameters as Record<string, Object> | undefined);
    const formDimension = extractFormDimension(want.parameters as Record<string, Object> | undefined) ??
      `${formInfo.FormDimension.Dimension_2_2}`;
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
        this.refreshForm(formId, textColor, formDimension).catch((err: Object) => {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'onAddForm refresh failed %{public}s', `${err}`);
        });
      }
    } catch (err) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'onAddForm formId extract failed %{public}s', `${err}`);
    }
    return formBindingData.createFormBindingData({
      tasksJson: '[]',
      pendingCount: '0',
      lastSyncText: '载入中',
      widgetBlurStyle: 'thin',
      hostTextColor: textColor ?? '',
      formDimension: formDimension
    });
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onUpdateForm id=%{public}s', formId);
    const textColor = extractTextColor(wantParams);
    const formDimension = extractFormDimension(wantParams);
    this.refreshForm(formId, textColor, formDimension).catch((err: Object) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'onUpdateForm failed %{public}s', `${err}`);
    });
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'onFormEvent id=%{public}s', formId);
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
      syncService.setTaskCompletedLocally(taskId, true).then(() => {
        // Persist completion and refresh every card before attempting the network.
        // No delayed payload can overwrite a newer snapshot.
        return syncService.syncNow(true);
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
