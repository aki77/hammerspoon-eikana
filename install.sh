#!/bin/bash
#
# install.sh
#
# Hammerspoon と Eikana.spoon を導入する。冪等（2 回目は案内以外を出力しない）。
#   1. Hammerspoon cask が無ければ brew install --cask hammerspoon
#   2. Eikana.spoon を ~/.hammerspoon/Spoons/ へコピー（差分があるときだけ）
#   3. ~/.hammerspoon/init.lua に hs.loadSpoon("Eikana"):start() を生成/追記
#   4. アクセシビリティ権限と再起動の案内
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPOON_SRC="$SCRIPT_DIR/Eikana.spoon"
HS_DIR="$HOME/.hammerspoon"
SPOONS_DIR="$HS_DIR/Spoons"
SPOON_DST="$SPOONS_DIR/Eikana.spoon"
INIT_LUA="$HS_DIR/init.lua"
LOAD_LINE='hs.loadSpoon("Eikana"):start()'

if [ ! -d "$SPOON_SRC" ]; then
  echo "Eikana.spoon が見つかりません: ${SPOON_SRC}" >&2
  exit 1
fi

# 「未導入」と「導入済みだが PATH に無い」を区別して案内する。
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
    echo "Homebrew は導入済みですが PATH に入っていません" >&2
    echo "次を実行してから、もう一度 install.sh を実行してください" >&2
    if [ -x /opt/homebrew/bin/brew ]; then
      # shellcheck disable=SC2016  # 利用者に打ってもらうコマンドをそのまま表示する
      echo '  eval "$(/opt/homebrew/bin/brew shellenv bash)"' >&2
    else
      # shellcheck disable=SC2016  # 同上
      echo '  eval "$(/usr/local/bin/brew shellenv bash)"' >&2
    fi
    exit 1
  fi
  echo "Homebrew が見つかりません" >&2
  echo "先に次のコマンドで Homebrew を導入してください（Xcode Command Line Tools も同時に入ります）" >&2
  # shellcheck disable=SC2016  # 同上
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
  exit 1
fi

if ! brew list --cask hammerspoon >/dev/null 2>&1; then
  echo "==> Hammerspoon を導入します"
  brew install --cask hammerspoon
fi

mkdir -p "$SPOONS_DIR"

# Finder が作る .DS_Store で毎回「違う」判定にならないよう除外する。
# 既存が symlink の場合は（リンク先が同一でも）実ディレクトリに置き換える。
NEED_COPY=0
if [ -L "$SPOON_DST" ] || [ ! -e "$SPOON_DST" ]; then
  NEED_COPY=1
elif ! diff -rq -x .DS_Store "$SPOON_SRC" "$SPOON_DST" >/dev/null 2>&1; then
  NEED_COPY=1
fi

if [ "$NEED_COPY" -eq 1 ]; then
  echo "==> Eikana.spoon をコピーします: ${SPOON_DST}"
  TMP_DST="$SPOONS_DIR/Eikana.spoon.tmp.$$"
  # コピー元は末尾スラッシュ無し（BSD cp は src/ だと中身展開になる）
  cp -R "$SPOON_SRC" "$TMP_DST"
  rm -rf "$SPOON_DST"
  mv "$TMP_DST" "$SPOON_DST"
fi

# init.lua。symlink には追記しない（リンク先を書き換えてしまうため）。
if [ -L "$INIT_LUA" ]; then
  if ! grep -qE 'loadSpoon\(["'"'"']Eikana' "$INIT_LUA" 2>/dev/null; then
    echo "注意: ${INIT_LUA} は symlink のため追記しませんでした。リンク先に次の行を追加してください" >&2
    echo "  ${LOAD_LINE}" >&2
  fi
elif [ ! -e "$INIT_LUA" ]; then
  echo "==> ${INIT_LUA} を生成します"
  {
    echo '-- 左右 Command 単押しで英数/かなを送る'
    echo "$LOAD_LINE"
  } > "$INIT_LUA"
elif ! grep -qE 'loadSpoon\(["'"'"']Eikana' "$INIT_LUA"; then
  echo "==> ${INIT_LUA} の末尾に追記します"
  # 末尾が改行で終わっていないファイルでも行が連結されないようにする
  if [ -s "$INIT_LUA" ] && [ -n "$(tail -c 1 "$INIT_LUA")" ]; then
    echo >> "$INIT_LUA"
  fi
  echo "$LOAD_LINE" >> "$INIT_LUA"
fi

echo
echo "次の手順で有効にしてください"
echo "  1. open -a Hammerspoon"
echo "  2. システム設定 > プライバシーとセキュリティ > アクセシビリティ で Hammerspoon を許可"
echo "  3. Hammerspoon を Quit して起動し直す（許可だけでは eventtap が動きません）"
echo "     既に起動中で設定だけ変えた場合はメニューバーの Reload Config"
echo "ログイン時の自動起動は Hammerspoon の Preferences で Launch at login を有効にしてください"
