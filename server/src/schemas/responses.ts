import { z } from '@hono/zod-openapi';

const ApiCommonDatetimeShape = z.iso.datetime({ offset: true });

const BASE_USER_SHAPE = {
  id: z.string().nonempty().openapi({
    description: 'Unique identifier for the authenticated user',
    example: 'user_2f0b63e4b3a44df0b2f099b1c8f52765',
  }),
  created_at: z.iso.datetime().openapi({
    description: 'Timestamp when the user account was created',
    example: '2026-07-07T10:30:00.000Z',
  }),
  email: z.email().openapi({
    description: 'Email address for the authenticated user',
    example: 'test@example.com',
  }),
  email_verified: z.boolean().openapi({
    description: 'Whether the user has verified their email address',
    example: false,
  }),
  name: z.string().nonempty().openapi({
    description: 'Display name for the authenticated user',
    example: 'Test User',
  }),
} as const;

const SESSION_SHAPE = {
  expires_at: ApiCommonDatetimeShape.openapi({
    description: 'Session expiration timestamp',
    example: '2025-10-12T12:08:28.382Z',
  }),
  created_at: ApiCommonDatetimeShape.openapi({
    description: 'Session creation timestamp',
    example: '2025-10-05T12:08:28.382Z',
  }),
  updated_at: ApiCommonDatetimeShape.openapi({
    description: 'Session last update timestamp',
    example: '2025-10-05T12:08:28.382Z',
  }),
} as const;

export type BaseUser = z.infer<ReturnType<typeof buildUserSchema>>;

export type AuthSchemas<ExtrasShape extends z.ZodRawShape> = ReturnType<typeof buildAuthSchemas<ExtrasShape>>;

export type SessionResponseOf<ExtrasShape extends z.ZodRawShape> = z.infer<
  AuthSchemas<ExtrasShape>['SessionResponseSchema']
>;

/**
 * Builds the response schemas, folding an app-supplied extras shape into the user object.
 *
 * The shape is merged before registration rather than through `.extend()` on an already-registered schema, so the
 * emitted OpenAPI document carries exactly one `UserSchema` component.
 */
export function buildAuthSchemas<ExtrasShape extends z.ZodRawShape>(extrasShape?: ExtrasShape) {
  const UserSchema = buildUserSchema(extrasShape);

  const SessionResponseSchema = z
    .object({
      session: z.object(SESSION_SHAPE),
      user: UserSchema,
    })
    .openapi('SessionResponse', {
      title: 'Session Response',
      description: 'Session response containing session and user information',
    });

  const AuthResponseSchema = z
    .object({
      token: z.string().nonempty().openapi({
        description: 'Authentication token for the signed-in user',
        example: 'f21wcpz7Aokmlh2MB632MZpTgfruPc62',
      }),
      user: UserSchema,
    })
    .openapi('AuthResponse', {
      title: 'Authentication Response',
      description: 'Successful authentication response containing an authentication token and user details',
    });

  const TokenResponseSchema = z
    .object({
      token: z.string().openapi({ description: 'JWT token', example: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9...' }),
    })
    .openapi('TokenResponse');

  return { UserSchema, SessionResponseSchema, AuthResponseSchema, TokenResponseSchema };
}

function buildUserSchema<ExtrasShape extends z.ZodRawShape>(extrasShape?: ExtrasShape) {
  return z.object({ ...BASE_USER_SHAPE, ...(extrasShape ?? ({} as ExtrasShape)) }).openapi('UserSchema', {
    title: 'User',
    description: 'Authenticated user details',
  });
}
