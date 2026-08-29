export interface HomeLayoutMetrics {
  activeHeight: number;
}

export function calculateHomeLayout(viewportHeight: number, activeCount: number,
  pendingCount: number): HomeLayoutMetrics {
  const viewport = viewportHeight > 0 ? viewportHeight : 700;
  const usable = Math.max(viewport - 190, 200);
  const activeNatural = activeCount === 0 ? 108 : activeCount * 44 + pendingCount * 14 + 50;
  // 已完成任务在独立面板中查看，首页只为稳定的摘要入口预留空间。
  const activeHeight = Math.max(72, Math.min(activeNatural, usable - 58 - 12));
  return { activeHeight };
}
