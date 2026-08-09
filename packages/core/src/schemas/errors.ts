import { z } from './openapi.js';

export const DefaultErrorResponseSchema = z
  .object({
    message: z.string().openapi({ description: 'Error message' }),
    code: z.string().optional().openapi({ description: 'Error code' }),
  })
  .openapi('ErrorResponse', {
    title: 'Error Response',
    description: 'Error response containing error message and optional error code',
  });

const ValidationIssueSchema = z
  .object({
    code: z.string().openapi({ description: 'Validation issue code', example: 'too_small' }),
    path: z
      .array(z.union([z.string(), z.number()]))
      .openapi({ description: 'Path to the invalid field', example: ['amount'] }),
    message: z.string().openapi({
      description: 'Validation issue message',
      example: 'Number must be greater than 0',
    }),
  })
  .loose();

export const DefaultValidationErrorResponseSchema = z
  .object({
    message: z.string().openapi({ description: 'Error message' }),
    code: z.string().optional().openapi({ description: 'Error code' }),
    context: z
      .object({
        validations: z.array(ValidationIssueSchema).openapi({
          description: 'Per-field validation issues',
        }),
      })
      .optional(),
  })
  .openapi('ValidationErrorResponse', {
    title: 'Validation Error Response',
    description: 'Error response for invalid request payloads, optionally including field-level validation issues',
  });
