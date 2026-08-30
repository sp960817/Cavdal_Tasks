import { WidgetBlurStyle } from '../../model/TaskModels';

export function widgetBlurLabel(style: WidgetBlurStyle): string {
  if (style === 'none') return '透明';
  if (style === 'thin') return '轻薄';
  if (style === 'thick') return '厚重';
  return '标准';
}

@Component
export struct WidgetAppearanceCard {
  @Prop selectedStyle: WidgetBlurStyle = 'thin';
  onStyleChange: (style: WidgetBlurStyle) => void = (_style: WidgetBlurStyle): void => {};
  private styles: WidgetBlurStyle[] = ['none', 'thin', 'regular', 'thick'];

  build() {
    Column({ space: 10 }) {
      Text('桌面卡片背景')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row({ space: 4 }) {
        ForEach(this.styles, (style: WidgetBlurStyle) => {
          Button(widgetBlurLabel(style))
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor(this.selectedStyle === style ?
              $r('app.color.on_accent') : $r('app.color.text_secondary'))
            .backgroundColor(this.selectedStyle === style ?
              $r('app.color.accent') : $r('app.color.surface_input'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => this.onStyleChange(style))
        }, (style: WidgetBlurStyle) => style)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(16)
  }
}
