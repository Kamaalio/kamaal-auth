import fs from 'node:fs/promises';
import path from 'node:path';
import { performance } from 'node:perf_hooks';

/**
 * Stamps a release version into a package's `package.json`, in place.
 *
 * The two packages release in lockstep, so the version also replaces the `workspace:*` link the Hono package holds on
 * the core package — a published tarball cannot carry a workspace protocol.
 */
const WORKSPACE_DEPENDENCY_PREFIX = 'workspace:';

async function main() {
  const startTime = performance.now();
  const [packageDirectory, argumentVersion] = process.argv.slice(2);
  if (packageDirectory == null) {
    throw new Error('Usage: node scripts/deployment-package-json.ts <package-directory> <version>');
  }

  const packageJSONPath = path.join(packageDirectory, 'package.json');
  const packageJSON = JSON.parse(await fs.readFile(packageJSONPath, 'utf8'));
  const version = argumentVersion != null && argumentVersion !== 'null' ? argumentVersion : packageJSON.version;
  const modified = { ...packageJSON, version, dependencies: pinWorkspaceDependencies(packageJSON, version) };
  if (modified.dependencies == null) delete modified.dependencies;

  await fs.writeFile(packageJSONPath, `${JSON.stringify(modified, null, 2)}\n`);
  const endTime = performance.now();
  console.log(`Stamped ${packageJSON.name}@${version} in ${(endTime - startTime).toFixed(4)} milliseconds`);
}

function pinWorkspaceDependencies(
  packageJSON: { dependencies?: Record<string, string> },
  version: string,
): Record<string, string> | undefined {
  const dependencies = packageJSON.dependencies;
  if (dependencies == null) return undefined;

  return Object.fromEntries(
    Object.entries(dependencies).map(([name, range]) => [
      name,
      range.startsWith(WORKSPACE_DEPENDENCY_PREFIX) ? version : range,
    ]),
  );
}

await main();
