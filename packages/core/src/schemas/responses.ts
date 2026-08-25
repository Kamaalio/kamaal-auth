import { z } from 'zod';

const ApiCommonDatetimeShape = z.iso.datetime({ offset: true });

/**
 * Shared so the user block reads the same wherever it is embedded.
 *
 * Keys mirror the schema exactly; an example that drifts from its schema is worse than none.
 */
const EXAMPLE_USER = {
  id: 'user_2f0b63e4b3a44df0b2f099b1c8f52765',
  created_at: '2026-07-07T10:30:00.000Z',
  email: 'test@example.com',
  email_verified: false,
  name: 'Test User',
} as const;

const SESSION_SHAPE = {
  expires_at: ApiCommonDatetimeShape.meta({
    description: 'Session expiration timestamp',
    example: '2025-10-12T12:08:28.382Z',
  }),
  created_at: ApiCommonDatetimeShape.meta({
    description: 'Session creation timestamp',
    example: '2025-10-05T12:08:28.382Z',
  }),
  updated_at: ApiCommonDatetimeShape.meta({
    description: 'Session last update timestamp',
    example: '2025-10-05T12:08:28.382Z',
  }),
} as const;

export const UserSchema = z
  .object({
    id: z.string().nonempty().meta({
      description: 'Unique identifier for the authenticated user',
      example: 'user_2f0b63e4b3a44df0b2f099b1c8f52765',
    }),
    created_at: z.iso.datetime().meta({
      description: 'Timestamp when the user account was created',
      example: '2026-07-07T10:30:00.000Z',
    }),
    email: z.email().meta({
      description: 'Email address for the authenticated user',
      example: 'test@example.com',
    }),
    email_verified: z.boolean().meta({
      description: 'Whether the user has verified their email address',
      example: false,
    }),
    name: z.string().nonempty().meta({
      description: 'Display name for the authenticated user',
      example: 'Test User',
    }),
  })
  .meta({
    $id: 'UserSchema',
    title: 'User',
    description: 'Authenticated user details',
    example: EXAMPLE_USER,
  });

export type BaseUser = z.infer<typeof UserSchema>;

export const SessionResponseSchema = z
  .object({
    session: z.object(SESSION_SHAPE),
    user: UserSchema,
  })
  .meta({
    $id: 'SessionResponse',
    title: 'Session Response',
    description: 'Session response containing session and user information',
    example: {
      session: {
        expires_at: '2025-10-12T12:08:28.382Z',
        created_at: '2025-10-05T12:08:28.382Z',
        updated_at: '2025-10-05T12:08:28.382Z',
      },
      user: EXAMPLE_USER,
    },
  });

export type SessionResponseOf = z.infer<typeof SessionResponseSchema>;

export const AuthResponseSchema = z
  .object({
    token: z.string().nonempty().meta({
      description: 'Authentication token for the signed-in user',
      example: 'f21wcpz7Aokmlh2MB632MZpTgfruPc62',
    }),
    user: UserSchema,
  })
  .meta({
    $id: 'AuthResponse',
    title: 'Authentication Response',
    description: 'Successful authentication response containing an authentication token and user details',
    example: { token: 'f21wcpz7Aokmlh2MB632MZpTgfruPc62', user: EXAMPLE_USER },
  });

export const TokenResponseSchema = z
  .object({
    token: z.string().meta({ description: 'JWT token', example: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9...' }),
  })
  .meta({ $id: 'TokenResponse' });

export type AuthSchemas = ReturnType<typeof buildAuthSchemas>;

export function buildAuthSchemas() {
  return { UserSchema, SessionResponseSchema, AuthResponseSchema, TokenResponseSchema };
}
