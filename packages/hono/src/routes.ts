import { createRoute, type z } from '@hono/zod-openapi';
import type { MiddlewareHandler } from 'hono';

import {
  AUTH_OPENAPI_TAG,
  AUTH_ROUTE_PATHS,
  AuthenticationHeaders,
  MIME_TYPES,
  STATUS_CODES,
  SignOutResponseSchema,
  TokenHeaders,
} from '@kamaalio/kamaal-auth-core';

export interface RouteBuilderOptions {
  tag: string;
  securitySchemeName: string;
  errorSchema: z.ZodType;
  validationErrorSchema: z.ZodType;
  signUpSchema: z.ZodType;
  signInSchema: z.ZodType;
  authResponseSchema: z.ZodType;
  sessionResponseSchema: z.ZodType;
  tokenResponseSchema: z.ZodType;
  sessionMiddleware: MiddlewareHandler;
}

export function buildAuthRoutes(options: RouteBuilderOptions) {
  const { errorSchema, validationErrorSchema } = options;
  const tags = [options.tag || AUTH_OPENAPI_TAG];

  const signUp = createRoute({
    method: 'post',
    path: AUTH_ROUTE_PATHS.signUp,
    tags,
    summary: 'Sign up with email and password',
    description: 'Create a new user account with email and password',
    request: {
      body: { content: { [MIME_TYPES.JSON]: { schema: options.signUpSchema } } },
    },
    responses: {
      [STATUS_CODES.CREATED]: {
        description: 'Account created successfully',
        content: { [MIME_TYPES.JSON]: { schema: options.authResponseSchema } },
        headers: TokenHeaders,
      },
      [STATUS_CODES.BAD_REQUEST]: {
        description: 'Invalid request or email already exists',
        content: { [MIME_TYPES.JSON]: { schema: validationErrorSchema } },
      },
      [STATUS_CODES.CONFLICT]: {
        description: 'Email already registered',
        content: { [MIME_TYPES.JSON]: { schema: errorSchema } },
      },
      [STATUS_CODES.UNAUTHORIZED]: {
        description: 'Authentication failed or invalid credentials',
        content: { [MIME_TYPES.JSON]: { schema: errorSchema } },
      },
    },
  });

  const signIn = createRoute({
    method: 'post',
    path: AUTH_ROUTE_PATHS.signIn,
    tags,
    summary: 'Sign in with email and password',
    description: 'Authenticate a user with email and password credentials',
    request: {
      body: { content: { [MIME_TYPES.JSON]: { schema: options.signInSchema } } },
    },
    responses: {
      [STATUS_CODES.OK]: {
        description: 'Sign in successful',
        content: { [MIME_TYPES.JSON]: { schema: options.authResponseSchema } },
        headers: TokenHeaders,
      },
      [STATUS_CODES.BAD_REQUEST]: {
        description: 'Invalid credentials or request',
        content: { [MIME_TYPES.JSON]: { schema: validationErrorSchema } },
      },
      [STATUS_CODES.UNAUTHORIZED]: {
        description: 'Authentication failed',
        content: { [MIME_TYPES.JSON]: { schema: errorSchema } },
      },
    },
  });

  const signOut = createRoute({
    method: 'post',
    path: AUTH_ROUTE_PATHS.signOut,
    tags,
    summary: 'Sign out',
    description: 'Sign out the current user and invalidate the session',
    responses: {
      [STATUS_CODES.OK]: {
        description: 'Sign out successful',
        content: { [MIME_TYPES.JSON]: { schema: SignOutResponseSchema } },
      },
      [STATUS_CODES.UNAUTHORIZED]: {
        description: 'Authentication failed',
        content: { [MIME_TYPES.JSON]: { schema: errorSchema } },
      },
    },
  });

  const session = createRoute({
    method: 'get',
    path: AUTH_ROUTE_PATHS.session,
    tags,
    summary: 'Get session',
    middleware: [options.sessionMiddleware],
    description:
      'Get the current user session information. Can authenticate via either Authorization header (JWT bearer token) or session cookie.',
    request: { headers: AuthenticationHeaders.partial() },
    responses: {
      [STATUS_CODES.OK]: {
        description: 'Session retrieved successfully',
        content: { [MIME_TYPES.JSON]: { schema: options.sessionResponseSchema } },
      },
      [STATUS_CODES.UNAUTHORIZED]: {
        description: 'Session not found',
        content: { [MIME_TYPES.JSON]: { schema: errorSchema } },
      },
    },
  });

  const token = createRoute({
    method: 'get',
    path: AUTH_ROUTE_PATHS.token,
    tags,
    summary: 'Get JWT token',
    description: 'Get a new JWT token for the authenticated session. Use bearer token authentication.',
    security: [{ [options.securitySchemeName]: [] }],
    responses: {
      [STATUS_CODES.OK]: {
        description: 'Token retrieved successfully',
        content: { [MIME_TYPES.JSON]: { schema: options.tokenResponseSchema } },
        headers: TokenHeaders,
      },
      [STATUS_CODES.UNAUTHORIZED]: {
        description: 'Not authenticated, session expired, or session not found',
        content: { [MIME_TYPES.JSON]: { schema: errorSchema } },
      },
    },
  });

  return { signUp, signIn, signOut, session, token };
}
