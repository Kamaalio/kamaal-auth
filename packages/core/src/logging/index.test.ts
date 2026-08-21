import { describe, expect, it } from 'vitest';

import { AUTH_EVENTS, noopAuthLogger } from './index.js';

describe('AUTH_EVENTS', () => {
  it('follows the <domain>.<action>[.<detail>] naming rule and is prefixed with auth', () => {
    for (const event of Object.values(AUTH_EVENTS)) {
      expect(event).toMatch(/^[a-z]+(?:\.[a-z][a-z_]*)+$/);
      expect(event.startsWith('auth.')).toBe(true);
    }
  });

  it('has no duplicate event names', () => {
    const events = Object.values(AUTH_EVENTS);

    expect(new Set(events).size).toBe(events.length);
  });
});

describe('noopAuthLogger', () => {
  it('accepts a closed AuthLogFields payload without throwing', () => {
    expect(() =>
      noopAuthLogger.info({ event: AUTH_EVENTS.signInSucceeded, outcome: 'success' }, 'message'),
    ).not.toThrow();
  });
});
