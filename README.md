# hammerspoon-eikana

左 Command の単押しで「英数」、右 Command の単押しで「かな」を送る Hammerspoon の Spoon。

## 動作

- 左 Command を単独で押して離すと英数、右 Command なら かな を送る。
- Command を修飾キーとして使ったとき（Cmd+C、Cmd+Tab など）は何もしない。
- 1 秒（既定）以上押しっぱなしにして離したときは何もしない。
- US 配列キーボードでも動く（IME が見るのはキーコードで、物理キーの有無は関係ない）。

## 必要条件

- macOS
- Homebrew（`install.sh` が Hammerspoon cask を導入する）
- Hammerspoon のアクセシビリティ権限

## 導入

```bash
curl -fsSL https://raw.githubusercontent.com/aki77/hammerspoon-eikana/main/install.sh | bash
```

パイプで実行すると、`Eikana.spoon` を GitHub の tarball から一時ディレクトリに取ってきて使う
（取得するブランチやタグは `EIKANA_REF` で変えられる。既定は `main`）。
clone 済みなら `bash install.sh` でも同じように入る（手元の `Eikana.spoon` を使う）。

`install.sh` は冪等で、Hammerspoon の導入、`~/.hammerspoon/Spoons/Eikana.spoon` へのコピー（symlink ではなくコピー）、
`~/.hammerspoon/init.lua` への `hs.loadSpoon("Eikana"):start()` の生成/追記を行う。
`init.lua` が symlink の場合は追記せず、追加すべき行を案内する。

その後:

1. `open -a Hammerspoon`
2. システム設定 > プライバシーとセキュリティ > アクセシビリティ で Hammerspoon を許可
3. **Hammerspoon を Quit して起動し直す。** 許可だけでは eventtap が動かない
   （Hammerspoon の `MJLua.m` の Notes: "Eventtaps ... will fail until Accessibility is enabled and the Hammerspoon application is relaunched"）

ログイン時の自動起動は Hammerspoon の Preferences で Launch at login を有効にする（この Spoon は `hs.autoLaunch` を触らない）。

## 設定

```lua
hs.loadSpoon("Eikana"):start()
spoon.Eikana.holdThreshold = 800   -- 押しっぱなしとみなす ms（既定 1000）
```

`holdThreshold` は毎イベント読むので、`start()` の後に変えても効く。

メソッド: `start()` / `stop()` / `isEnabled()`。

## 手動導入

`Eikana.spoon` を `~/.hammerspoon/Spoons/` に置き、`~/.hammerspoon/init.lua` に
`hs.loadSpoon("Eikana"):start()` を書いて Reload Config する。

## アンインストール

`~/.hammerspoon/init.lua` の `hs.loadSpoon("Eikana"):start()` を消し、
`~/.hammerspoon/Spoons/Eikana.spoon` を削除して Reload Config する。

## 既知の制約

- Command + マウスクリックの後、しきい値未満で Command を離すと英数/かなが誤発火する
  （クリックは keyDown を伴わないため単押しと区別できない）。
- Karabiner-Elements や ⌘英かな など、同じキーを横取りするツールとは併用しない。

## 出典

- Hammerspoon `MJLua.m` の Accessibility に関する Notes
- `hs.eventtap.event` の `timestamp()`（押下時間の計測にイベント自身の時刻を使う）

## ライセンス

MIT
