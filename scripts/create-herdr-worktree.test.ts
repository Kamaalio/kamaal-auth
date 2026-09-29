import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import url from 'node:url';

const script = url.fileURLToPath(new URL('./create-herdr-worktree.ts', import.meta.url));
let directory: string;
let repo: string;
let commandPath: string;
let invocationPath: string;

function git(cwd: string, ...args: string[]): string {
  const result = childProcess.spawnSync('git', args, { cwd, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function create(...args: string[]): childProcess.SpawnSyncReturns<string> {
  return childProcess.spawnSync(process.execPath, [path.join(repo, 'scripts/create-herdr-worktree.ts'), ...args], {
    cwd: directory,
    encoding: 'utf8',
    env: { ...process.env, PATH: commandPath, HERDR_INVOCATION: invocationPath },
  });
}

void describe('create-herdr-worktree', () => {
  beforeEach(async () => {
    directory = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'herdr worktree test-')));
    repo = path.join(directory, 'repo');
    const bin = path.join(directory, 'bin');
    invocationPath = path.join(directory, 'herdr-invocation.json');
    commandPath = `${bin}${path.delimiter}${process.env.PATH}`;
    await fs.mkdir(path.join(repo, 'scripts'), { recursive: true });
    await fs.mkdir(bin);
    await fs.copyFile(script, path.join(repo, 'scripts/create-herdr-worktree.ts'));
    await fs.writeFile(path.join(repo, 'package.json'), '{"type":"module"}\n');
    git(directory, 'init', '--bare', '--initial-branch=main', 'remote.git');
    git(repo, 'init', '--initial-branch=main');
    git(repo, 'config', 'user.name', 'Worktree Test');
    git(repo, 'config', 'user.email', 'worktree-test@example.com');
    git(repo, 'add', '.');
    git(repo, 'commit', '-m', 'Initial commit');
    git(repo, 'remote', 'add', 'origin', path.join(directory, 'remote.git'));
    git(repo, 'push', 'origin', 'main');
    await fs.writeFile(
      path.join(bin, 'herdr.mjs'),
      `import fs from 'node:fs';
import childProcess from 'node:child_process';
const args = process.argv.slice(2);
fs.writeFileSync(process.env.HERDR_INVOCATION, JSON.stringify(args));
const result = childProcess.spawnSync('git', [
  'worktree', 'add', '-b', args[args.indexOf('--branch') + 1], '../checkout', args[args.indexOf('--base') + 1],
], { cwd: args[args.indexOf('--cwd') + 1], stdio: 'inherit' });
process.exitCode = result.status ?? 1;
`,
    );
    await fs.writeFile(path.join(bin, 'herdr'), `#!/bin/sh\nexec '${process.execPath}' '${bin}/herdr.mjs' "$@"\n`, {
      mode: 0o755,
    });
  });

  afterEach(async () => {
    await fs.rm(directory, { recursive: true, force: true });
  });

  void it('fetches the latest main and creates the branch without focusing or needing an env file', async () => {
    const publisher = path.join(directory, 'publisher');
    git(directory, 'clone', path.join(directory, 'remote.git'), publisher);
    git(publisher, 'config', 'user.name', 'Worktree Test');
    git(publisher, 'config', 'user.email', 'worktree-test@example.com');
    git(publisher, 'commit', '--allow-empty', '-m', 'New remote commit');
    git(publisher, 'push', 'origin', 'main');
    const latest = git(publisher, 'rev-parse', 'HEAD');

    const result = create('feature/auth');

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(await fs.readFile(invocationPath, 'utf8')), [
      'worktree',
      'create',
      '--cwd',
      repo,
      '--branch',
      'feature/auth',
      '--base',
      'origin/main',
      '--no-focus',
    ]);
    assert.equal(git(repo, 'rev-parse', 'feature/auth'), latest);
    assert.equal(git(path.join(directory, 'checkout'), 'symbolic-ref', '--short', 'HEAD'), 'feature/auth');
    assert.equal(git(repo, 'symbolic-ref', '--short', 'HEAD'), 'main');
  });

  void it('requires a branch name before calling Herdr', async () => {
    const result = create();

    assert.equal(result.status, 1);
    assert.match(result.stderr, /Usage: just herdr-worktree <new-branch>/);
    await assert.rejects(fs.access(invocationPath), { code: 'ENOENT' });
  });

  void it('rejects extra arguments before calling Herdr', async () => {
    const result = create('feature/auth', 'unexpected');

    assert.equal(result.status, 1);
    assert.match(result.stderr, /Usage: just herdr-worktree <new-branch>/);
    await assert.rejects(fs.access(invocationPath), { code: 'ENOENT' });
  });

  void it('rejects an invalid branch before calling Herdr', async () => {
    const result = create('--invalid');

    assert.equal(result.status, 1);
    assert.match(result.stderr, /git check-ref-format failed/);
    await assert.rejects(fs.access(invocationPath), { code: 'ENOENT' });
  });

  void it('rejects an existing branch before calling Herdr', async () => {
    const result = create('main');

    assert.equal(result.status, 1);
    assert.match(result.stderr, /Branch main already exists/);
    await assert.rejects(fs.access(invocationPath), { code: 'ENOENT' });
  });

  void it('stops before creating a branch when fetching fails', async () => {
    git(repo, 'remote', 'set-url', 'origin', path.join(directory, 'missing.git'));

    const result = create('feature/auth');

    assert.equal(result.status, 1);
    assert.match(result.stderr, /git fetch failed/);
    await assert.rejects(fs.access(invocationPath), { code: 'ENOENT' });
    assert.equal(git(repo, 'branch', '--list', 'feature/auth'), '');
  });

  void it('reports a Herdr failure instead of claiming success', async () => {
    await fs.writeFile(path.join(directory, 'bin/herdr'), '#!/bin/sh\nexit 9\n');

    const result = create('feature/auth');

    assert.equal(result.status, 1);
    assert.match(result.stderr, /herdr worktree failed/);
    assert.equal(git(repo, 'branch', '--list', 'feature/auth'), '');
  });
});
