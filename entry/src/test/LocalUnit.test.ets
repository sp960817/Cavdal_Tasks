import { describe, it, expect } from '@ohos/hypium';
import { VTodoCodec, unescapeText } from '../main/ets/caldav/VTodoCodec';
import { CalendarObjectResponse, XmlHelpers } from '../main/ets/caldav/XmlHelpers';
import { TodoTask } from '../main/ets/model/TaskModels';
import { utf8Bytes, utf8String } from '../main/ets/utils/TextCodec';

export default function localUnitTest() {
  describe('cavdalTaskCore', () => {
    it('parsesFoldedAndEscapedVTodo', 0, () => {
      const ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\nUID:1\r\nSUMMARY:Buy\\, milk\\nand bread\r\nDESCRIPTION:hello\r\n world\r\nDUE:20260617T100000Z\r\nSTATUS:NEEDS-ACTION\r\nEND:VTODO\r\nEND:VCALENDAR\r\n';
      const task: TodoTask | undefined = VTodoCodec.toTask(ics, '/tasks/1.ics', '/tasks/', '"1"');
      if (task === undefined) {
        expect(false).assertTrue();
        return;
      }
      expect(task.title).assertEqual('Buy, milk\nand bread');
      expect(task.description).assertEqual('helloworld');
      expect(task.due).assertEqual('20260617T100000Z');
    });

    it('completionMutationPreservesUnknownFields', 0, () => {
      const ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\nUID:2\r\nSUMMARY:Write plan\r\nX-CUSTOM:keep-me\r\nSTATUS:NEEDS-ACTION\r\nPERCENT-COMPLETE:0\r\nEND:VTODO\r\nEND:VCALENDAR\r\n';
      const task: TodoTask | undefined = VTodoCodec.toTask(ics, '/tasks/2.ics', '/tasks/', '"2"');
      if (task === undefined) {
        expect(false).assertTrue();
        return;
      }
      const completed: TodoTask = VTodoCodec.setCompletion(task, true, new Date(Date.UTC(2026, 5, 17, 8, 0, 0)));
      expect(completed.rawIcs.includes('X-CUSTOM:keep-me')).assertTrue();
      expect(completed.rawIcs.includes('STATUS:COMPLETED')).assertTrue();
      expect(completed.rawIcs.includes('PERCENT-COMPLETE:100')).assertTrue();
      expect(completed.rawIcs.includes('COMPLETED:20260617T080000Z')).assertTrue();
    });

    it('createsLocalTaskWithoutDueByDefault', 0, () => {
      const task: TodoTask = VTodoCodec.createLocal('No due', '', '', '/tasks/');
      expect(task.due).assertEqual('');
      expect(task.rawIcs.includes('DUE:')).assertFalse();
      expect(task.rawIcs.includes('BEGIN:VALARM')).assertFalse();
    });

    it('createsLocalTaskWithReminderAndRepeat', 0, () => {
      const task: TodoTask = VTodoCodec.createLocal('With due', '', '20260617T043000Z', '/tasks/', '提前一天', '每周');
      expect(task.rawIcs.includes('DUE:20260617T043000Z')).assertTrue();
      expect(task.rawIcs.includes('RRULE:FREQ=WEEKLY')).assertTrue();
      expect(task.rawIcs.includes('BEGIN:VALARM')).assertTrue();
      expect(task.rawIcs.includes('TRIGGER:-P1D')).assertTrue();
    });

    it('updateFieldsPreservesUnknownFieldsAndReplacesAlarm', 0, () => {
      const ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\nUID:3\r\nSUMMARY:Old\r\nX-CUSTOM:keep-me\r\nDUE:20260617T043000Z\r\nRRULE:FREQ=DAILY\r\nBEGIN:VALARM\r\nTRIGGER:PT0S\r\nACTION:DISPLAY\r\nDESCRIPTION:Old\r\nEND:VALARM\r\nEND:VTODO\r\nEND:VCALENDAR\r\n';
      const task: TodoTask | undefined = VTodoCodec.toTask(ics, '/tasks/3.ics', '/tasks/', '"3"');
      if (task === undefined) {
        expect(false).assertTrue();
        return;
      }
      const updated = VTodoCodec.updateFields(task, 'New', '', '20260618T043000Z', '提前一天', '每周');
      expect(updated.rawIcs.includes('X-CUSTOM:keep-me')).assertTrue();
      expect(updated.rawIcs.includes('SUMMARY:New')).assertTrue();
      expect(updated.rawIcs.includes('DESCRIPTION:Old')).assertFalse();
      expect(updated.rawIcs.includes('DUE:20260618T043000Z')).assertTrue();
      expect(updated.rawIcs.includes('RRULE:FREQ=WEEKLY')).assertTrue();
      expect(updated.rawIcs.includes('TRIGGER:PT0S')).assertFalse();
      expect(updated.rawIcs.includes('TRIGGER:-P1D')).assertTrue();
    });

    it('parsesCalDavCalendarObjects', 0, () => {
      const xml = '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' +
        '<d:response><d:href>/cal/a.ics</d:href><d:propstat><d:prop><d:getetag>"a"</d:getetag>' +
        '<c:calendar-data><![CDATA[BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:a\r\nSUMMARY:A\r\nEND:VTODO\r\nEND:VCALENDAR]]></c:calendar-data>' +
        '</d:prop></d:propstat></d:response></d:multistatus>';
      const objects: CalendarObjectResponse[] = XmlHelpers.calendarObjects(xml);
      expect(objects.length).assertEqual(1);
      expect(objects[0].href).assertEqual('/cal/a.ics');
      expect(objects[0].etag).assertEqual('"a"');
      expect(objects[0].calendarData.includes('BEGIN:VTODO')).assertTrue();
    });

    it('unescapesIcalendarText', 0, () => {
      expect(unescapeText('a\\;b\\,c\\nnext')).assertEqual('a;b,c\nnext');
    });

    it('roundTripsUtf8Text', 0, () => {
      const value = '用户:密码🔐';
      expect(utf8String(utf8Bytes(value))).assertEqual(value);
      expect(utf8Bytes('用').length).assertEqual(3);
    });
  });
}
