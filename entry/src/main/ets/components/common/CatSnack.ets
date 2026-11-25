const SNACK_COLORS: string[] = [
  '#DE7A76', '#E99B60', '#DFBE58', '#87B478', '#68AEA6', '#7298CE', '#B18BC5'
];

// Task IDs are shared with FormKit and survive edits, sorting and CalDAV sync.
function wrapperColor(taskId: string): string {
  let hash = 2166136261;
  for (let i = 0; i < taskId.length; i++) {
    hash = Math.imul(hash ^ taskId.charCodeAt(i), 16777619);
  }
  return SNACK_COLORS[(hash >>> 0) % SNACK_COLORS.length];
}

@Component
export struct CatSnack {
  @Prop taskId: string = '';

  build() {
    Stack() {
      Row().width('97.3%').height('62%').backgroundColor(wrapperColor(this.taskId))
      Image($r('app.media.snack_wrapper')).width('100%').height('100%').objectFit(ImageFit.Fill)
    }.width('100%').height('100%').accessibilityLevel('no')
  }
}
