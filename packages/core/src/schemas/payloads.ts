import { z } from 'zod';

export type EmailPasswordSignUp = z.infer<typeof EmailPasswordSignUpSchema>;

export type EmailPasswordSignIn = z.infer<typeof EmailPasswordSignInSchema>;

export type SignOutResponse = z.infer<typeof SignOutResponseSchema>;

export const EmailPasswordSignUpSchema = z
  .object({
    email: z.email().meta({
      description: 'User email address',
      example: 'john.doe@example.com',
    }),
    password: z.string().min(8).max(128).meta({
      description: 'User password (minimum 8 characters)',
      example: 'SecurePassword123!',
    }),
    name: z
      .string()
      .min(3)
      .refine(val => val === val.trim(), {
        message: 'Name must not have leading or trailing spaces',
      })
      .refine(val => /^[^\s]+(\s[^\s]+)+$/.test(val), {
        message: 'Name must contain at least 2 words separated by single spaces',
      })
      .meta({
        description: 'User display name (minimum 2 words separated by single spaces)',
        example: 'John Doe',
      }),
    callbackURL: z.url().optional().meta({
      description: 'URL to redirect to after sign up',
      example: 'https://example.com/dashboard',
    }),
  })
  .meta({
    $id: 'EmailPasswordSignUp',
    title: 'Email Password Sign Up',
    description: 'Request body for signing up with email and password',
    example: {
      email: 'john.doe@example.com',
      password: 'SecurePassword123!',
      name: 'John Doe',
      callbackURL: 'https://example.com/dashboard',
    },
  });

export const EmailPasswordSignInSchema = z
  .object({
    email: z.email().meta({
      description: 'User email address',
      example: 'user@example.com',
    }),
    password: z.string().min(8).max(128).meta({
      description: 'User password (minimum 8 characters)',
      example: 'securePassword123',
    }),
    callbackURL: z.url().optional().meta({
      description:
        'Optional URL to redirect to after successful sign in. If not provided, the default redirect will be used.',
      example: 'https://app.example.com/dashboard',
    }),
  })
  .meta({
    $id: 'EmailPasswordSignIn',
    title: 'Email Password Sign In Request',
    description: 'Request payload for signing in with email and password credentials',
    example: {
      email: 'user@example.com',
      password: 'securePassword123',
      callbackURL: 'https://app.example.com/dashboard',
    },
  });

export const SignOutResponseSchema = z.object({}).meta({
  $id: 'SignOutResponse',
  title: 'Sign Out Response',
  description: 'Successful signout response',
});
