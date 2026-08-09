set -e

if [ -z "$VERSION" ]; then
  echo "❌ Error: VERSION environment variable is not set"
  echo "Usage: VERSION=x.x.x ./scripts/publish.sh"
  exit 1
fi

echo "🐸 $VERSION"

pnpm i

# Core first: the Hono package's dependency on it is pinned to this same version.
for package in core hono
do
  directory="packages/$package"
  echo "📦 $directory"
  rm -rf "$directory/dist"
  pnpm --filter "./$directory" build
  node scripts/deployment-package-json.ts "$directory" "$VERSION"
  (cd "$directory" && pnpm publish --access public --no-git-checks)
done
