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

function backgroundColorFor(style: string): string {
  if (style === 'thin') {
    return '#1AFFFFFF';
  }
  if (style === 'regular') {
    return '#26FFFFFF';
  }
  if (style === 'thick') {
    return '#99FFFFFF';
  }
  return '#00000000';
}

function opaqueColor(color: string): string {
  if (color.length === 9 && color.startsWith('#')) {
    return `#FF${color.slice(3)}`;
  }
  return color;
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
    if (this.widgetBlurStyle === 'thick') {
      return '#FF000000';
    }
    return opaqueColor(this.textColor);
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
    Column() {
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
        List({ space: 2 }) {
          ForEach(this.cardTasks, (task: CardTask) => {
            ListItem() {
              Row({ space: 6 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Text('')
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .border({ width: 1.8, color: this.tc() })
                    .backgroundColor(this.completingId === task.id ?
                      this.tc() : '#00000000')
                    .animation({ duration: 400, curve: Curve.EaseOut })

                  Text('✓')
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                    .opacity(this.completingId === task.id ? 1 : 0)
                    .scale({
                      x: this.completingId === task.id ? 1 : 0.3,
                      y: this.completingId === task.id ? 1 : 0.3
                    })
                    .animation({ duration: 500, curve: Curve.EaseOut })
                }
                .width(30)
                .height(30)
                .onClick(() => this.completeTask(task))

                Text(task.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.tc())
                  .opacity(this.completingId === task.id ? 0 : 1)
                  .animation({ duration: 600, curve: Curve.EaseOut })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .onClick(() => this.openApp())

                if (task.hasReminder) {
                  SymbolGlyph($r('sys.symbol.bell'))
                    .fontSize(11)
                    .fontColor([this.tc()])
                    .opacity(this.completingId === task.id ? 0 : 0.85)
                    .animation({ duration: 600, curve: Curve.EaseOut })
                }
              }
              .width('100%')
              .height(30)
              .padding({ left: 4, right: 5 })
            }
          }, (task: CardTask) => task.id)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(backgroundColorFor(this.widgetBlurStyle))
    .backgroundBlurStyle(blurStyleFor(this.widgetBlurStyle))
    .onClick(() => this.openApp())
  }
}
