import { describe, it, expect } from '@ohos/hypium';
import { VTodoCodec } from '../main/ets/caldav/VTodoCodec';
import { dueDayOffset } from '../main/ets/formatters/DueTimeFormatter';
import { TodoTask } from '../main/ets/model/TaskModels';

function readTask(ics: string): TodoTask {
  const task = VTodoCodec.toTask(ics, '/tasks/codec.ics', '/tasks/', '"codec"');
  if (task === undefined) {
    throw new Error('Expected a valid VTODO task');
  }
  return task;
}

export default function vTodoCodecTest() {
  describe('vTodoComponentProperties', () => {
    it('roundTripsPriorityThroughCreateEditCompleteAndClear', 0, () => {
      const original = VTodoCodec.createLocal('紧急待办', '', '', '/tasks/', '无', '无', 3);
      expect(readTask(original.rawIcs).priority).assertEqual(3);
      const edit = VTodoCodec.updateFields(original, '修改标题', '', '', '无', '无');
      expect(readTask(edit.rawIcs).priority).assertEqual(3);
      const important = VTodoCodec.updateFields(edit, edit.title, '', '', '无', '无', 1);
      expect(readTask(VTodoCodec.setCompletion(important, true).rawIcs).priority).assertEqual(1);
      const cleared = VTodoCodec.updateFields(important, important.title, '', '', '无', '无', 0);
      expect(readTask(cleared.rawIcs).priority).assertEqual(0);
    });

    it('classifiesDueDatesAcrossBeijingMidnight', 0, () => {
      const midnight = Date.UTC(2026, 10, 24, 16);
      expect(dueDayOffset('20261124T155959Z', midnight)).assertEqual(-1);
      expect(dueDayOffset('20261124T160000Z', midnight)).assertEqual(0);
      expect(dueDayOffset('20261202', midnight)).assertEqual(7);
      expect(dueDayOffset('', midnight) === undefined).assertTrue();
    });

    it('doesNotUseAlarmDescriptionAsAnEmptyTaskBody', 0, () => {
      const original = VTodoCodec.createLocal('记下这件事', '', '20261020T080000Z', '/tasks/', '立刻');
      const parsed = readTask(original.rawIcs);
      expect(parsed.title).assertEqual('记下这件事');
      expect(parsed.description).assertEqual('');
      expect(VTodoCodec.detectReminder(parsed.rawIcs, parsed.due)).assertEqual('立刻');
    });

    it('readsParentDescriptionAfterAlarmSubcomponents', 0, () => {
      const ics = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'BEGIN:VTODO',
        'UID:alarm-first',
        'SUMMARY:任务标题',
        'BEGIN:VALARM',
        'TRIGGER:PT0S',
        'ACTION:DISPLAY',
        'DESCRIPTION:提醒文案',
        'END:VALARM',
        'DESCRIPTION:真正的任务正文',
        'END:VTODO',
        'END:VCALENDAR'
      ].join('\r\n') + '\r\n';
      const parsed = readTask(ics);
      expect(parsed.title).assertEqual('任务标题');
      expect(parsed.description).assertEqual('真正的任务正文');
    });

    it('keepsClearedBodyEmptyAfterSavingAndParsingWithAlarm', 0, () => {
      const original = VTodoCodec.createLocal('任务标题', '需要清空的正文', '20261020T080000Z', '/tasks/', '立刻');
      const updated = VTodoCodec.updateFields(original, '新标题', '', original.due, '立刻', '无');
      const parsed = readTask(updated.rawIcs);
      expect(parsed.title).assertEqual('新标题');
      expect(parsed.description).assertEqual('');
      expect(VTodoCodec.detectReminder(parsed.rawIcs, parsed.due)).assertEqual('立刻');
      expect(parsed.rawIcs.includes('BEGIN:VALARM')).assertTrue();
    });

    it('roundTripsDistinctEditedTitleBodyAndReminder', 0, () => {
      const original = VTodoCodec.createLocal('原标题', '原正文', '20261020T080000Z', '/tasks/', '立刻');
      const title = '新标题，第一件事';
      const body = '独立正文;保留细节\n第二行,继续记录';
      const updated = VTodoCodec.updateFields(original, title, body, original.due, '立刻', '每周');
      const parsed = readTask(updated.rawIcs);
      expect(parsed.title).assertEqual(title);
      expect(parsed.description).assertEqual(body);
      expect(parsed.due).assertEqual(original.due);
      expect(VTodoCodec.detectReminder(parsed.rawIcs, parsed.due)).assertEqual('立刻');
      expect(VTodoCodec.detectRepeat(parsed.rawIcs)).assertEqual('每周');
    });

    it('preservesAnIntentionalBodyEqualToTheTitle', 0, () => {
      const original = VTodoCodec.createLocal('相同内容也要保留', '相同内容也要保留',
        '20261020T080000Z', '/tasks/', '立刻');
      const parsed = readTask(original.rawIcs);
      expect(parsed.title).assertEqual('相同内容也要保留');
      expect(parsed.description).assertEqual('相同内容也要保留');
      expect(VTodoCodec.detectReminder(parsed.rawIcs, parsed.due)).assertEqual('立刻');
    });
  });
}
