import util from '@ohos.util';

export function utf8Bytes(value: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(value);
}

export function utf8String(bytes: Uint8Array): string {
  return util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true }).decodeToString(bytes);
}
