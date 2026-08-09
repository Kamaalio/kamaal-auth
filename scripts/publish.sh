set -e

if [ -z "$VERSION" ]; then
  echo "❌ Error: VERSION environment variable is not set"
  echo "Usage: VERSION=x.x.x ./scripts/publish.sh"
  exit 1
fi

echo "🐸 $VERSION"

if [ "${GITHUB_ACTIONS:-}" != "true" ] \
  || [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] \
  || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]
then
  echo "❌ npm packages may only be published by the GitHub Actions release workflow"
  echo "Create and push the release tag instead: git tag $VERSION && git push origin $VERSION"
  exit 1
fi

pnpm i

# Core first: the Hono package's dependency on it is pinned to this same version.
for package in core hono
do
  directory="packages/$package"
  echo "📦 $directory"
  rm -rf "$directory/dist"
  pnpm --filter "./$directory" build
  node scripts/deployment-package-json.ts "$directory" "$VERSION"
  # npm CLI performs the GitHub Actions OIDC exchange required by npm trusted publishing.
  (cd "$directory" && npm publish --access public --no-git-checks)
done
