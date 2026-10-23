#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/dist/Agent Notebook.app/Contents/MacOS/tasknote"
if [[ ! -x "$SOURCE" ]]; then echo '先运行 scripts/build-app.sh' >&2; exit 1; fi
mkdir -p "$HOME/.local/bin"
DEST="$HOME/.local/bin/tasknote"
if [[ -e "$DEST" || -L "$DEST" ]]; then
  if [[ -L "$DEST" && "$(readlink "$DEST")" == "$SOURCE" ]]; then echo "已安装：$DEST"; exit 0; fi
  echo "目标已存在，未覆盖：$DEST" >&2; exit 1
fi
ln -s "$SOURCE" "$DEST"
echo "已安装：$DEST"
echo '若找不到命令，请将 ~/.local/bin 加入 PATH。'
