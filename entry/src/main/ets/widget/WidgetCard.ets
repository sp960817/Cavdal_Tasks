interface CardTask {
  id: string;
  title: string;
  due: string;
  syncState: string;
}

interface GlassToken {
  cardBg: string;
  blur: BlurStyle;
  border: string;
  shadowColor: string;
  highlight: string;
  lowlight: string;
}

function parseTasks(value: string): CardTask[] {
  try {
    return JSON.parse(value) as CardTask[];
  } catch (_err) {
    return [];
  }
}

function glassToken(style: string): GlassToken {
  if (style === 'none') {
    return {
      cardBg: '#00000000', blur: BlurStyle.NONE, border: '#00FFFFFF', shadowColor: '#00000000',
      highlight: '#00FFFFFF', lowlight: '#00000000'
    };
  }
  if (style === 'regular') {
    return {
      cardBg: '#14FFFFFF', blur: BlurStyle.BACKGROUND_REGULAR, border: '#52FFFFFF', shadowColor: '#20000000',
      highlight: '#30FFFFFF', lowlight: '#08000000'
    };
  }
  if (style === 'thick') {
    return {
      cardBg: '#24FFFFFF', blur: BlurStyle.BACKGROUND_THICK, border: '#68FFFFFF', shadowColor: '#28000000',
      highlight: '#42FFFFFF', lowlight: '#0D000000'
    };
  }
  return {
    cardBg: '#0CFFFFFF', blur: BlurStyle.BACKGROUND_THIN, border: '#3DFFFFFF', shadowColor: '#16000000',
    highlight: '#24FFFFFF', lowlight: '#05000000'
  };
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('tasksJson') tasksJson: string = '[]';
  @LocalStorageProp('pendingCount') pendingCount: string = '0';
  @LocalStorageProp('lastSyncText') lastSyncText: string = '未同步';
  @LocalStorageProp('widgetBlurStyle') widgetBlurStyle: string = 'thin';
  @State completingId: string = '';

  private token(): GlassToken {
    return glassToken(this.widgetBlurStyle);
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

  private tasks(): CardTask[] {
    return parseTasks(this.tasksJson);
  }

  build() {
    Column() {
      if (this.tasks().length === 0) {
        Column({ space: 5 }) {
          Text('今日清爽')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.widget_text_primary'))
            .textAlign(TextAlign.Center)
          Text(this.lastSyncText)
            .fontSize(10)
            .fontColor($r('app.color.widget_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.openApp())
      } else {
        List({ space: 2 }) {
          ForEach(this.tasks(), (task: CardTask) => {
            ListItem() {
              Row({ space: 6 }) {
                Stack() {
                  Text('')
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .border({ width: 1.5, color: $r('app.color.widget_check_border') })
                    .backgroundColor(this.completingId === task.id ?
                      $r('app.color.widget_check_fill') : '#00000000')
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
                .width(18)
                .height(18)
                .onClick(() => this.completeTask(task))

                Text(task.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.completingId === task.id ?
                    $r('app.color.widget_text_secondary') : $r('app.color.widget_text_primary'))
                  .opacity(this.completingId === task.id ? 0 : 1)
                  .animation({ duration: 600, curve: Curve.EaseOut })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .layoutWeight(1)
                  .onClick(() => this.openApp())
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
    .backgroundColor(this.token().cardBg)
    .backgroundBlurStyle(this.token().blur)
    .linearGradient({
      angle: 135,
      colors: [
        [this.token().highlight, 0],
        ['#00FFFFFF', 0.48],
        [this.token().lowlight, 1]
      ]
    })
    .border({ width: 1, color: this.token().border })
    .shadow({ radius: 18, color: this.token().shadowColor, offsetY: 5 })
    .onClick(() => this.openApp())
  }
}
