import { extendZodWithOpenApi } from '@asteasolutions/zod-to-openapi';
import { z } from 'zod';

/**
 * `.openapi()` is a prototype patch, not an import.
 *
 * `@hono/zod-openapi` applies the same patch to the same zod instance, but this package must not depend on a server
 * adapter having been loaded first, so it applies it itself. The call is idempotent and every schema module in this
 * package imports `z` from here rather than from `zod` directly.
 */
extendZodWithOpenApi(z);

export { z };
