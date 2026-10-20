import localUnitTest from './LocalUnit.test';
import vTodoCodecTest from './VTodoCodec.test';

export default function testsuite() {
  localUnitTest();
  vTodoCodecTest();
}
