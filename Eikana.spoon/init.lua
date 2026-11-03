-- Eikana.spoon
--
-- 左 Command の単押しで「英数」、右 Command の単押しで「かな」を送る。
-- Command を修飾キーとして使ったとき（Cmd+C など）は何もしない。
--
-- 使い方:
--   hs.loadSpoon("Eikana"):start()
--   spoon.Eikana.holdThreshold = 800   -- 任意（ms）。start() の後でも効く
--
-- ■ なぜ Hammerspoon なのか
--
-- macOS の defaults / AppleSymbolicHotKeys で扱える修飾キーは Cocoa の
-- NSEvent.ModifierFlags のビットマスクで、**左右を区別しない**。つまり
-- 「左 Command だけ」「右 Command だけ」は defaults では表現できず、
-- キーイベントを横取りするレイヤーが必ず要る。Hammerspoon は cask で入り
-- （署名済み）、必要な権限はアクセシビリティのみ。ドライバも root 実行も要らない。
--
-- ■ keycode の由来と、US 配列でも動く理由
--
-- 数値は Apple SDK の Events.h（HIToolbox）の仮想キーコード。
--   kVK_Command      0x37 (55)
--   kVK_RightCommand 0x36 (54)
--   kVK_JIS_Eisu     0x66 (102)
--   kVK_JIS_Kana     0x68 (104)
--
-- 名前のとおり英数/かなは JIS 配列のキーだが、**US 配列の内蔵キーボードでも動く**。
-- IME が反応しているのは物理キーではなくキーコードそのものなので、その物理キーが
-- キーボードに存在する必要はない。
--
-- ■ アクセシビリティ権限（付与だけでは足りない）
--
-- eventtap にはアクセシビリティ権限が要る。しかも**権限を与えた後に
-- Hammerspoon を再起動しないと有効にならない**。出典は Hammerspoon の
-- MJLua.m の Notes: "Eventtaps ... will fail until Accessibility is enabled
-- and the Hammerspoon application is relaunched"。
-- 再起動を忘れると、設定は正しいのに何も起きないという区別の付かない状態になる。
--
-- ■ 押しっぱなしを単押しとみなさない
--
-- 下の simpleCmd ガードは「Command を押している間に他キーの keyDown が来た」
-- ときだけ立つ。修飾キーの押下は keyDown を発生させないため、**Command を単独で
-- 長時間押し続けてから離しても simpleCmd は false のまま**で、単押しと同じ経路を
-- 通って英数/かなが飛ぶ。Command を押したまま考え込んで離すと IME が勝手に
-- 変わるため、押下時間のしきい値（holdThreshold）を入れて抑止する。
--
-- 時計に event:timestamp()（起動からの ns）を使う。出典は hs.eventtap.event の
-- 公式ドキュメント。hs.timer.secondsSinceEpoch() を採らないのは、それが
-- **コールバックが走った時刻**であって押下時間そのものではないため。押下と解放の
-- 両方でイベント自身の時刻を読めば、コールバックの遅延に左右されない。
--
-- cmdDownAt への代入を左右の分岐の**中**に置いているのが要点。分岐の外に出すと
-- Command を押したまま Shift や Option を押すたびに時計が巻き戻り、押しっぱなしの
-- 判定がすり抜ける。非 Command の keycode による flagsChanged はどちらの分岐にも
-- 入らないので cmdDownAt は据え置かれる。
--
-- 未確認の範囲とフォールバック:
--   - flagsChanged のイベントが非ゼロの妥当な timestamp を持つかは環境によって
--     未確認。0 が返るなどして効かない場合は、cmdDownAt への**代入 2 行だけ**を
--     hs.timer.absoluteTime() に差し替える。event:timestamp() と同じ時計
--     （起動からの ns、スリープ除外）なので holdThreshold は変えなくてよい。
--     切り分けは hs -c では届かない（eventtap のコールバック内の値のため）ので、
--     一時的に print を足して Hammerspoon のコンソールで見る。
--   - この script 自身の keyStroke が合成する英数/かなの keyDown も tap に再入するが、
--     cmd フラグを持たない keyDown なので cmdDownAt にも simpleCmd にも触らず無害。
--     公式ドキュメントの Notes "Synthesized events have a timestamp of 0 by default"
--     に対する備えでもある（合成イベントの timestamp が 0 でも、この経路は
--     時計を読まない）。
--
-- ■ 既知の制約（対処しない）
--
-- Command + マウスクリックの後、**しきい値未満で Command を離した場合に限り**
-- 英数/かなが誤発火する。クリックは keyDown を伴わないため、下の simpleCmd ガードが
-- 立たず「単押し」と判定されるのが理由。なお押下時間ガードにより、ゆっくりした
-- Cmd+クリック（しきい値以上）は巻き添えで抑止される。

local obj = {}
obj.__index = obj

obj.name = "Eikana"
obj.version = "0.1.0"
obj.author = "aki77"
obj.license = "MIT"
obj.homepage = "https://github.com/aki77/hammerspoon-eikana"

-- 押しっぱなしとみなすしきい値（ms）。start 時にキャッシュせず、コールバック内で
-- 毎イベント読むので、start() の後に書き換えても効く。
obj.holdThreshold = 1000

-- ここから下のロジックは US 配列 MacBook で実運用実績のある参照実装を
-- **逐語的に**保持している。1 行でも書き換えると未検証コードになる。
-- 書き換えるのはコメントの追加に留めること。

-- Command が「ショートカットの修飾キー」として使われたかどうかのフラグ。
-- Command を押している間に他のキーの keyDown が来たら true になり、
-- Command を離したときの英数/かな送出を抑止する。これが無いと Cmd+C や
-- Cmd+Tab のたびに IME が切り替わり、実害が大きい。
local simpleCmd = false
local leftSet = false
local rightSet = false

local cmdDownAt = 0                          -- 押下時刻（event:timestamp() の ns）

local leftCmd = 0x37   -- kVK_Command (55)
local rightCmd = 0x36  -- kVK_RightCommand (54)
local eisuu = 0x66     -- kVK_JIS_Eisu (102)
local kana = 0x68      -- kVK_JIS_Kana (104)

local function keyStroke(modifiers, character)
    -- 第 3 引数は keyDown から keyUp までの待ち時間（マイクロ秒）。
    -- 既定値をそのまま使うと体感で分かるほど遅延するので、明示的に
    -- 5000 µs = 5 ms まで詰めている。省略してはいけない。
    hs.eventtap.keyStroke(modifiers, character, 5000)
end

local function eikanaEvent(event)
    local c = event:getKeyCode()
    local f = event:getFlags()
    if event:getType() == hs.eventtap.event.types.keyDown then
        if f['cmd'] and c then
            simpleCmd = true
        end
    elseif event:getType() == hs.eventtap.event.types.flagsChanged then
        -- 修飾キー**単体**の keycode は flagsChanged でしか取れない。
        -- 修飾キーの押下は keyDown を発生させないため、keyDown 側で
        -- 左右を判定しようとしても何も来ない。
        if f['cmd'] then
            if c == leftCmd then
                leftSet = true
                rightSet = false
                cmdDownAt = event:timestamp()
            elseif c == rightCmd then
                rightSet = true
                leftSet = false
                cmdDownAt = event:timestamp()
            end
        else
            -- この else は「cmd フラグが立っていない flagsChanged」全般に入る。
            -- Cmd の解放だけでなく Shift や Control 単体の押下・解放でも通るので、
            -- event:timestamp() は大文字を打つたびに呼ばれることになる。
            -- それでも条件の短絡（leftSet の判定を先に置くなど）で呼び出しを
            -- 減らさないのは、1 回あたり µs オーダーのコストに対して、
            -- 参照実装の条件式の形を崩す代償が見合わないため。
            -- held に名前を付けてあるのは、timestamp() が期待どおりの値を返すかを
            -- 切り分けるとき（上の**未確認**の項）に print を挟む先にするため。
            local thresholdNs = obj.holdThreshold * 1000 * 1000   -- ms を ns で
            local held = event:timestamp() - cmdDownAt
            if simpleCmd == false and held < thresholdNs then
                if leftSet then
                    keyStroke({}, eisuu)
                elseif rightSet then
                    keyStroke({}, kana)
                end
            end
            simpleCmd = false
            leftSet = false
            rightSet = false
            cmdDownAt = 0    -- 他 3 つとの対称性のためだけ（leftSet が偽になる時点で送出は止まる）
        end
    end
end

--- Eikana:start()
--- Method
--- eventtap を作って開始する。二重に呼んでも tap は 1 つだけ。
function obj:start()
    if not self._tap then
        self._tap = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.flagsChanged}, eikanaEvent)
    end
    self._tap:start()
    return self
end

--- Eikana:stop()
--- Method
--- eventtap を止めて内部状態をリセットする。
function obj:stop()
    if self._tap then
        self._tap:stop()
    end
    simpleCmd = false
    leftSet = false
    rightSet = false
    cmdDownAt = 0
    return self
end

--- Eikana:isEnabled()
--- Method
--- eventtap が動作中なら true（確認用）。
function obj:isEnabled()
    return (self._tap ~= nil) and self._tap:isEnabled()
end

-- GC 対策: 元の単体スクリプトでは tap を local にすると GC に回収されて黙って止まる
-- 罠があった。Spoon では hs.loadSpoon が spoon.Eikana としてこのテーブルを
-- グローバルに保持し、tap は obj._tap に入るので、この罠は起きない。
-- tap を local 変数に「整理」しないこと。

return obj
