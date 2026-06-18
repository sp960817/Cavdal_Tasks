export type SyncState = 'synced' | 'pending' | 'conflict' | 'error';
export type WidgetBlurStyle = 'none' | 'thin' | 'regular' | 'thick';

export interface TodoTask {
  id: string;
  uid: string;
  href: string;
  calendarHref: string;
  etag: string;
  title: string;
  description: string;
  due: string;
  priority: number;
  status: string;
  completedAt: string;
  percentComplete: number;
  rawIcs: string;
  syncState: SyncState;
  updatedAt: number;
}

export interface CalendarSource {
  href: string;
  displayName: string;
  supportsVTodo: boolean;
  ctag: string;
}

export interface AccountSettings {
  serverUrl: string;
  username: string;
  calendarHref: string;
  calendarName: string;
  lastSyncAt: number;
  widgetBlurStyle: WidgetBlurStyle;
}

export interface SyncOperation {
  id: string;
  taskId: string;
  type: 'put' | 'delete';
  payload: string;
  createdAt: number;
  attempts: number;
  lastError: string;
}

export interface WidgetTask {
  id: string;
  title: string;
  due: string;
  syncState: SyncState;
}

export interface WidgetPayload {
  tasks: WidgetTask[];
  pendingCount: number;
  lastSyncText: string;
}
