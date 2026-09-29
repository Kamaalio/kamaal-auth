import childProcess from 'node:child_process';
import path from 'node:path';
import url from 'node:url';

const repoRoot = path.dirname(path.dirname(url.fileURLToPath(import.meta.url)));

function run(command: string, args: string[]): void {
  const result = childProcess.spawnSync(command, args, { cwd: repoRoot, stdio: 'inherit' });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`${command} ${args[0]} failed`);
  }
}

function main(): void {
  const branch = process.argv[2];

  if (!branch || process.argv.length !== 3) {
    throw new Error('Usage: just herdr-worktree <new-branch>');
  }

  run('git', ['check-ref-format', '--branch', branch]);

  const existing = childProcess.spawnSync('git', ['show-ref', '--verify', '--quiet', `refs/heads/${branch}`], {
    cwd: repoRoot,
  });

  if (existing.error) {
    throw existing.error;
  }

  if (existing.status === 0) {
    throw new Error(`Branch ${branch} already exists`);
  }

  if (existing.status !== 1) {
    throw new Error('Could not check whether the branch exists');
  }

  run('git', ['fetch', 'origin', 'main']);
  run('herdr', ['worktree', 'create', '--cwd', repoRoot, '--branch', branch, '--base', 'origin/main', '--no-focus']);
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
