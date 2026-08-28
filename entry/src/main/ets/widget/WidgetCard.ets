interface CardTask {
  id: string;
  title: string;
  due: string;
  syncState: string;
  hasReminder: boolean;
}

function parseTasks(value: string): CardTask[] {
  try {
    return JSON.parse(value) as CardTask[];
  } catch (_err) {
    return [];
  }
}

function blurStyleFor(style: string): BlurStyle {
  if (style === 'thin') {
    return BlurStyle.BACKGROUND_THIN;
  }
  if (style === 'regular') {
    return BlurStyle.BACKGROUND_REGULAR;
  }
  if (style === 'thick') {
    return BlurStyle.BACKGROUND_THICK;
  }
  return BlurStyle.NONE;
}

function isLightHostColor(color: string): boolean {
  let value = color.toUpperCase();
  if (value.length === 9 && value.startsWith('#')) {
    value = `#${value.slice(3)}`;
  }
  if (value.length !== 7 || !value.startsWith('#')) {
    return false;
  }
  const red = Number.parseInt(value.slice(1, 3), 16);
  const green = Number.parseInt(value.slice(3, 5), 16);
  const blue = Number.parseInt(value.slice(5, 7), 16);
  return red * 299 + green * 587 + blue * 114 > 160000;
}

// FormKit supplies the inverse of the host background color. A dark inverse
// therefore means the host background is light, and vice versa.
function hasLightHostBackground(inverseHostColor: string): boolean {
  return !isLightHostColor(inverseHostColor);
}

function foregroundColorFor(inverseHostColor: string): string {
  if ((inverseHostColor.length === 7 || inverseHostColor.length === 9) &&
    inverseHostColor.startsWith('#')) {
    return inverseHostColor;
  }
  return '#F2FFFFFF';
}

function backgroundColorFor(style: string, inverseHostColor: string): string {
  const lightHost = hasLightHostBackground(inverseHostColor);
  if (style === 'none') {
    return '#00000000';
  }
  if (style === 'thin') {
    return lightHost ? '#1AFFFFFF' : '#2E000000';
  }
  if (style === 'regular') {
    return lightHost ? '#2EFFFFFF' : '#46000000';
  }
  if (style === 'thick') {
    return lightHost ? '#66FFFFFF' : '#66000000';
  }
  return '#00000000';
}

function borderColorFor(style: string, inverseHostColor: string): string {
  const lightHost = hasLightHostBackground(inverseHostColor);
  if (style === 'none') {
    return '#00000000';
  }
  return lightHost ? '#24000000' : '#33FFFFFF';
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('tasksJson') @Watch('onTasksJsonChange') tasksJson: string = '[]';
  @LocalStorageProp('pendingCount') pendingCount: string = '0';
  @LocalStorageProp('lastSyncText') lastSyncText: string = '未同步';
  @LocalStorageProp('widgetBlurStyle') @Watch('onBlurStyleChange') widgetBlurStyle: string = 'thin';
  @LocalStorageProp('textColor') @Watch('onTextColorChange') textColor: string = '#E6000000';
  @LocalStorageProp('formDimension') formDimension: string = '2';
  @State completingId: string = '';
  @State cardTasks: CardTask[] = [];

  aboutToAppear(): void {
    this.cardTasks = parseTasks(this.tasksJson);
  }

  private onTextColorChange(): void {
  }

  private onBlurStyleChange(): void {
  }

  private onTasksJsonChange(): void {
    this.cardTasks = parseTasks(this.tasksJson);
    this.completingId = '';
  }

  private tc(): string {
    return foregroundColorFor(this.textColor);
  }

  private pendingLabel(): string {
    const count = Number(this.pendingCount);
    if (Number.isFinite(count) && count > 0) {
      return `${count} 项待同步`;
    }
    return this.lastSyncText;
  }

  private usesCompactVisual(): boolean {
    return this.formDimension !== '3';
  }

  private isWide(): boolean {
    return this.formDimension === '3';
  }

  private isLarge(): boolean {
    return this.formDimension === '4';
  }

  private taskRowHeight(): number {
    if (this.isWide()) {
      return 28;
    }
    return this.isLarge() ? 30 : 30;
  }

  private completeTask(task: CardTask): void {
    this.completingId = task.id;
    postCardAction(this, {
      action: 'message',
      params: {
        operation: 'complete',
        taskId: task.id
      }
    });
  }

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        source: 'widget'
      }
    });
  }

  build() {
    Column({ space: this.usesCompactVisual() ? 3 : 4 }) {
      Row({ space: 6 }) {
        Text('待办')
          .fontSize(this.usesCompactVisual() ? 14 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tc())
        Text(`${this.cardTasks.length}`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tc())
          .opacity(0.68)
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.tc()])
          .opacity(0.72)
      }
      .width('100%')
      .height(this.isWide() ? 20 : this.usesCompactVisual() ? 22 : 24)
      .padding({ left: 4, right: 4 })
      .onClick(() => this.openApp())

      if (this.cardTasks.length === 0) {
        Column({ space: 5 }) {
          Text('今日清爽')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tc())
            .textAlign(TextAlign.Center)
          Text(this.lastSyncText)
            .fontSize(10)
            .fontColor(this.tc())
            .opacity(0.75)
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.openApp())
      } else {
        List({ space: this.isWide() ? 0 : 1 }) {
          ForEach(this.cardTasks, (task: CardTask) => {
            ListItem() {
              Row({ space: 4 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Text('')
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .border({ width: 1.8, color: this.tc() })
                    .backgroundColor(this.completingId === task.id ?
                      '#4778FF' : '#00000000')
                    .animation({ duration: 400, curve: Curve.EaseOut })

                  Text('✓')
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFFFF')
                    .opacity(this.completingId === task.id ? 1 : 0)
                    .scale({
                      x: this.completingId === task.id ? 1 : 0.3,
                      y: this.completingId === task.id ? 1 : 0.3
                    })
                    .animation({ duration: 500, curve: Curve.EaseOut })
                }
                .width(22)
                .height(this.taskRowHeight())
                .onClick(() => this.completeTask(task))

                Text(task.title)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tc())
                  .opacity(this.completingId === task.id ? 0 : 1)
                  .animation({ duration: 600, curve: Curve.EaseOut })
                  .maxLines(this.isLarge() ? 2 : 1)
                  .lineHeight(this.isLarge() ? 16 : 14)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .onClick(() => this.openApp())

                if (task.hasReminder && !this.usesCompactVisual()) {
                  SymbolGlyph($r('sys.symbol.bell'))
                    .fontSize(11)
                    .fontColor([this.tc()])
                    .opacity(this.completingId === task.id ? 0 : 0.85)
                    .animation({ duration: 600, curve: Curve.EaseOut })
                }
              }
              .width('100%')
              .height(this.taskRowHeight())
              .padding({
                left: this.isWide() ? 1 : 0,
                right: this.isWide() ? 4 : 2
              })
              .onClick(() => this.openApp())
            }
          }, (task: CardTask) => task.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      }

      Row() {
        Text(this.pendingLabel())
          .fontSize(this.isWide() ? 8 : 9)
          .fontColor(this.tc())
          .opacity(0.62)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      .width('100%')
      .height(this.isWide() ? 12 : this.usesCompactVisual() ? 12 : 14)
      .padding({ left: 4, right: 4 })
      .onClick(() => this.openApp())
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.isWide() ? 12 : 8,
      right: this.isWide() ? 12 : 8,
      top: this.isWide() ? 6 : this.usesCompactVisual() ? 8 : 10,
      bottom: this.isWide() ? 5 : this.usesCompactVisual() ? 6 : 8
    })
    .backgroundColor(backgroundColorFor(this.widgetBlurStyle, this.textColor))
    .backgroundBlurStyle(blurStyleFor(this.widgetBlurStyle))
    .border({ width: 0.6, color: borderColorFor(this.widgetBlurStyle, this.textColor) })
  }
}
