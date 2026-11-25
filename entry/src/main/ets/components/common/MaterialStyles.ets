export function taskSheetOptions(onDisappear: () => void = (): void => {}): SheetOptions {
  return {
    detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
    backgroundColor: $r('app.color.page_background'),
    showClose: false,
    onDisappear
  };
}
