export interface HomeLayoutMetrics {
  activeHeight: number;
  completedHeight: number;
  completedOpen: boolean;
}

export function calculateHomeLayout(viewportHeight: number, activeCount: number, pendingCount: number,
  completedCount: number, completedUserOverride: boolean, showCompleted: boolean): HomeLayoutMetrics {
  const viewport = viewportHeight > 0 ? viewportHeight : 700;
  const usable = Math.max(viewport - 190, 200);
  const activeNatural = activeCount === 0 ? 108 : activeCount * 44 + pendingCount * 14 + 50;
  const completedNatural = completedCount === 0 ? 104 : Math.min(completedCount * 40 + 66, 320);
  const autoFoldCompleted = activeNatural + completedNatural + 14 > usable;
  const completedOpen = completedUserOverride ? showCompleted : !autoFoldCompleted;

  let activeHeight: number;
  if (completedOpen) {
    const completedTarget = Math.min(completedNatural, Math.max(104, usable * 0.42));
    activeHeight = Math.max(72, Math.min(activeNatural, usable - completedTarget - 14));
  } else {
    activeHeight = Math.max(72, Math.min(activeNatural, usable - 58 - 14));
  }

  const completedHeight = completedOpen ?
    Math.min(completedNatural, Math.max(104, usable - activeHeight - 14)) : 58;
  return { activeHeight, completedHeight, completedOpen };
}
