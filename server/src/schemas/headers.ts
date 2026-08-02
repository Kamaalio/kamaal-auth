import { z } from '@hono/zod-openapi';

export const AuthenticationHeaders = z.object({
  authorization: z.string().openapi({
    description: 'Bearer token for authentication',
    example: 'Bearer f21wcpz7Aokmlh2MB632MZpTgfruPc62',
  }),
});

export const TokenHeaders = z.object({
  'set-auth-token': z.string().openapi({
    description: 'JWT token for API authentication',
    example: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9...',
  }),
  'set-auth-token-expiry': z.string().openapi({
    description: 'JWT expiry time in seconds (as a string representing digits)',
    example: '604800',
  }),
  'set-session-token': z.string().openapi({
    description: 'Session token for token refresh',
    example: 'f21wcpz7Aokmlh2MB632MZpTgfruPc62',
  }),
  'set-session-update-age': z.string().openapi({
    description: 'Session update age in seconds - session should be verified after this time',
    example: '86400',
  }),
});
