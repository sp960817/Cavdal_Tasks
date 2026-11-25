import { buffer } from '@kit.ArkTS';

export function utf8Bytes(value: string): Uint8Array {
  const encoded = buffer.from(value, 'utf8');
  const bytes = new Uint8Array(encoded.length);
  encoded.copy(bytes);
  return bytes;
}

export function utf8String(bytes: Uint8Array): string {
  return buffer.from(bytes).toString('utf8');
}
