import type { JsonValue } from '@kamaalio/kamaal-auth-core';

export function jsonInit(body: JsonValue): RequestInit {
  return { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

export function validSignUpPayload() {
  return { email: `test_${crypto.randomUUID()}@example.com`, password: 'SecurePassword123!', name: 'Test User' };
}
