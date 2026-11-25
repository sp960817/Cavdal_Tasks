import { deviceInfo } from '@kit.BasicServicesKit';

export class TaskTextLayout implements AttributeModifier<TextAttribute | TextAreaAttribute> {
  applyNormalAttribute(attribute: TextAttribute | TextAreaAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      attribute.wordBreak(WordBreak.BREAK_WORD);
      attribute.orphanCharOptimization(true);
      attribute.punctuationOverflow(true);
    }
  }
}
