import { z } from 'zod';

export const DefaultErrorResponseSchema = z
  .object({
    message: z.string().meta({ description: 'Error message' }),
    code: z.string().optional().meta({ description: 'Error code' }),
  })
  .meta({
    $id: 'ErrorResponse',
    title: 'Error Response',
    description: 'Error response containing error message and optional error code',
  });

const ValidationIssueSchema = z
  .object({
    code: z.string().meta({ description: 'Validation issue code', example: 'too_small' }),
    path: z
      .array(z.union([z.string(), z.number()]))
      .meta({ description: 'Path to the invalid field', example: ['amount'] }),
    message: z.string().meta({
      description: 'Validation issue message',
      example: 'Number must be greater than 0',
    }),
  })
  .loose();

export const DefaultValidationErrorResponseSchema = z
  .object({
    message: z.string().meta({ description: 'Error message' }),
    code: z.string().optional().meta({ description: 'Error code' }),
    context: z
      .object({
        validations: z.array(ValidationIssueSchema).meta({
          description: 'Per-field validation issues',
        }),
      })
      .optional(),
  })
  .meta({
    $id: 'ValidationErrorResponse',
    title: 'Validation Error Response',
    description: 'Error response for invalid request payloads, optionally including field-level validation issues',
  });
