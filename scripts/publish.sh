#!/usr/bin/env bash
# Publish this checkout to the existing broemp/nvim-herde GitHub repository.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
for tool in git make nvim python3; do
  command -v "$tool" >/dev/null || { echo "Required command missing: $tool" >&2; exit 1; }
done

make test

if [ ! -e .git ]; then git init -b main; fi
if [ "$(git rev-parse --show-toplevel)" != "$repo_root" ]; then
  echo "This directory must be its own Git repository." >&2
  exit 1
fi
if [ "$(git symbolic-ref --short HEAD)" != main ]; then
  echo "Switch to the main branch before publishing." >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  remote_url="$(git remote get-url origin)"
  case "$remote_url" in
    https://github.com/broemp/nvim-herde|https://github.com/broemp/nvim-herde.git|git@github.com:broemp/nvim-herde.git) ;;
    *) echo "Origin points somewhere other than broemp/nvim-herde; leaving it unchanged." >&2; exit 1 ;;
  esac
else
  git remote add origin https://github.com/broemp/nvim-herde.git
fi

git add -A -- .
if ! git diff --cached --quiet; then
  git commit -m "Publish nvim-herde agent workspace plugin"
fi
# A normal push preserves any remote history; Git will reject divergent history.
git push --set-upstream origin main
echo "Published: https://github.com/broemp/nvim-herde"
