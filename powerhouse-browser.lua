-- Powerhouse Browser keys — a SandFly script for Powerhouse Browser
-- (net.powerhouseapps.browser). Version 1.0.
--
-- PURPOSE
-- Make Powerhouse Browser behave like a desktop browser from the
-- keyboard while SandFly's per-app "pass keys" setting stays OFF:
--   * On a web page, SandFly keeps its keys and its own browse mode
--     does the reading (the reader's tree cursor reads the WebView
--     tree well; the app's own JS reading layer does not — field
--     evidence, Nov 26, 2026, report uid 467).
--   * The browser's own chords still reach the app from the page:
--     this script claims them before SandFly's keymap and forwards
--     them (see FORWARDING below).
--   * In the app's own bar and dialogs, every key goes to the app,
--     exactly as it did with per-app pass keys ON (see FOCUS RULE).
--
-- FOCUS RULE (the whole design)
-- sf.keys.passAll is held ON exactly while keyboard (input) focus is
-- on the app's native UI, and OFF while focus is in the page:
--   * PAGE context: the input-focused item is, or sits inside, the
--     WebView subtree. From the screen tree of Nov 26, 2026: the
--     level-1 FrameLayout described "Web page" and everything under
--     it (WebView > WebView > the page's nodes). A node counts as
--     page when it or any ancestor has class android.webkit.WebView
--     (or a class ending in "WebView"), or the description
--     "Web page".
--   * NATIVE context: anything else in this app — the root-level bar
--     controls (Back, Forward, the Address field, Reload, Add
--     bookmark, New tab, Downloads, the File..Help menu buttons) and
--     every app dialog or popup. Those are root-level nodes OUTSIDE
--     the WebView container in the tree.
-- Classification runs on input-focus changes (sf.onInputFocus),
-- backed up by window changes and app entry re-checking
-- sf.screen.inputFocused(); if that gives no item, the
-- accessibility-focused item decides. Transitions are written to
-- this script's Log page in SandFly, never spoken — SandFly still
-- announces the focused control itself, so the context is always
-- audible without extra chatter.
--
-- CLAIMED CHORDS (page context only; in native context passAll is
-- on and the app receives these directly, so no claim is needed)
--   Alt+A .. Alt+Z   menu accelerators — the app decides which
--                    letters are menus (File, Edit, Navigate, Tabs,
--                    Bookmarks, Passwords, View, Help in dev.14)
--   Alt+Left         history back      Alt+Right   history forward
--   Ctrl+L           address field     Ctrl+T      new tab
--   Ctrl+W           close tab         Ctrl+Tab    next tab
--   Ctrl+Shift+Tab   previous tab      Ctrl+F      find in page
--   Ctrl+R           reload            Ctrl+D      bookmark
--   Ctrl+H           history           Ctrl+B      bookmarks
--   Ctrl+Shift+L     vault fill picker
-- Everything else on the page stays SandFly's: arrows, browse-mode
-- letters, the SandFly key and its chords.
--
-- FORWARDING (how a claimed chord reaches the app)
-- SandFly's scripting API has no "hand this key to the app" call:
-- a script command that returns false hands the key back to
-- SandFly's normal key path, where the keymap claims it (that is
-- why returning false cannot forward Alt+Left). The one real
-- channel is Shizuku key injection, so a claimed chord is
-- forwarded as a passAll pulse:
--   1. sf.keys.passAll(true) — while this is on, SandFly passes
--      every key to the app, script keys included.
--   2. sf.keys.press(chord) — re-presses the chord through Shizuku
--      (the shell `input keyevent` with all key codes in one call,
--      which Android injects as one chord: modifiers down, key
--      down, key up, modifiers up).
--   3. A short settle (75 ms), then passAll returns to whatever
--      the focus rule currently says.
-- This needs Shizuku running with SandFly allowed in it (Justin's
-- Shizuku-Next build). If a press fails because Shizuku is down,
-- the script says so once per load ("Browser keys need Shizuku
-- running") and stops trying until the script reloads, rather
-- than erroring on every key — SandFly turns a script off after
-- repeated errors, and this one must not die on a missing Shizuku.
--
-- KNOWN LIMIT — BARE ALT CANNOT BE CLAIMED
-- A tap of Alt alone (the desktop menu-bar summon) is NOT
-- forwarded, and no SandFly script can forward it: script key
-- bindings are parsed by ScriptInput.parseKeys, whose parseStep
-- rejects any binding whose final key is a modifier
-- (takeUnless { KeyEvent.isModifierKey(it) }), and ScriptManager
-- never offers a lone modifier keydown to scripts at all. So in
-- page context a bare Alt tap stays SandFly's (it is held as a
-- possible chord prefix and dropped — the behaviour Justin found
-- on Nov 26, 2026). The desktop pattern survives through
-- Alt+letter: Alt+F summons the bar AND opens File in one stroke,
-- which is also how the app's own accelerator design treats it.
-- Once focus is in the bar, bare Alt is the app's again (passAll).
--
-- OTHER LIMITS (all from the source, not guesses)
-- * Script keys without the SandFly modifier never fire while a
--   text field has input focus (ScriptManager.isTyping gate) — so
--   the claimed chords do not fire while typing in a web page's
--   edit field or any other text field. In the app's own address
--   field you are in native context anyway (passAll).
-- * Holding a claimed chord repeats it, but a repeat that lands
--   while a forward is still in flight is dropped, so the pulse
--   can never overlap itself.
-- * NOT DEVICE-TESTED YET. This file was built and checked
--   against the SandFly source (~/sandfly-src) and the scripting
--   API document (version 5) only. The install-and-test note that
--   ships with it carries the on-device test matrix.
--
-- FLEET RULES HONOURED
-- * No command carries menu = true, control = true or a gesture:
--   nothing is added to the SandFly menu. The features live on
--   their keys only. (SandFly still lists the commands under
--   Settings > Commands > Scripts, which is SandFly's own list.)
-- * Package scope is exactly net.powerhouseapps.browser.
--
-- PROVENANCE
-- Justin Harris's call, Nov 26, 2026, 21:32 CT: "Before doing a
-- whole dev, let's build a sandfly script... alt for menu bar,
-- alt + letters, alt + arrows... with passthrough off." The
-- focus-driven passAll shape is his approved design of Nov 26,
-- 2026 (18:11 CT). Justin is the source of the idea, the chord
-- list, the design decisions and the device testing; the code was
-- written by Atlas (Muse) against the SandFly source.
-- Evidence: screen tree
--   ~/workspace/browser-app/evidence/screen-tree-dev14-applevis.txt
-- field report uid 467 (support mailbox, Nov 26, 2026),
-- ~/workspace/research_notes/sandfly-key-override-20261126/report.md
-- and ~/workspace/research_notes/sandfly-web-browsing-20261126/report.md.

local manifest = {
  id = 'powerhouse.browser.keys',
  name = 'Powerhouse Browser keys',
  version = '1.0',
  author = 'Powerhouse Apps (Justin Harris)',
  description = 'Desktop-style keys for Powerhouse Browser with per-app pass keys OFF. On web pages SandFly keeps its keys and browse mode reads the page; Alt+letters, Alt+Left/Right and the browser Ctrl chords are forwarded to the app, and in the menu bar and dialogs every key goes to the app. Needs Shizuku running, with SandFly allowed in it, for the forwarded chords.',
  homepage = 'https://github.com/jharris171185/harris-apps',
  minApiVersion = 3,
  testedApiVersion = 5,
  apps = { 'net.powerhouseapps.browser' },
  permissions = { 'input', 'actions', 'screen', 'speech' },
  commands = {
    { id = 'alt_a', title = 'Alt+A to app', keys = 'alt+a' },
    { id = 'alt_b', title = 'Alt+B to app', keys = 'alt+b' },
    { id = 'alt_c', title = 'Alt+C to app', keys = 'alt+c' },
    { id = 'alt_d', title = 'Alt+D to app', keys = 'alt+d' },
    { id = 'alt_e', title = 'Alt+E to app', keys = 'alt+e' },
    { id = 'alt_f', title = 'Alt+F to app', keys = 'alt+f' },
    { id = 'alt_g', title = 'Alt+G to app', keys = 'alt+g' },
    { id = 'alt_h', title = 'Alt+H to app', keys = 'alt+h' },
    { id = 'alt_i', title = 'Alt+I to app', keys = 'alt+i' },
    { id = 'alt_j', title = 'Alt+J to app', keys = 'alt+j' },
    { id = 'alt_k', title = 'Alt+K to app', keys = 'alt+k' },
    { id = 'alt_l', title = 'Alt+L to app', keys = 'alt+l' },
    { id = 'alt_m', title = 'Alt+M to app', keys = 'alt+m' },
    { id = 'alt_n', title = 'Alt+N to app', keys = 'alt+n' },
    { id = 'alt_o', title = 'Alt+O to app', keys = 'alt+o' },
    { id = 'alt_p', title = 'Alt+P to app', keys = 'alt+p' },
    { id = 'alt_q', title = 'Alt+Q to app', keys = 'alt+q' },
    { id = 'alt_r', title = 'Alt+R to app', keys = 'alt+r' },
    { id = 'alt_s', title = 'Alt+S to app', keys = 'alt+s' },
    { id = 'alt_t', title = 'Alt+T to app', keys = 'alt+t' },
    { id = 'alt_u', title = 'Alt+U to app', keys = 'alt+u' },
    { id = 'alt_v', title = 'Alt+V to app', keys = 'alt+v' },
    { id = 'alt_w', title = 'Alt+W to app', keys = 'alt+w' },
    { id = 'alt_x', title = 'Alt+X to app', keys = 'alt+x' },
    { id = 'alt_y', title = 'Alt+Y to app', keys = 'alt+y' },
    { id = 'alt_z', title = 'Alt+Z to app', keys = 'alt+z' },
    { id = 'alt_left', title = 'Alt+Left to app', keys = 'alt+left' },
    { id = 'alt_right', title = 'Alt+Right to app', keys = 'alt+right' },
    { id = 'ctrl_l', title = 'Ctrl+L to app', keys = 'ctrl+l' },
    { id = 'ctrl_t', title = 'Ctrl+T to app', keys = 'ctrl+t' },
    { id = 'ctrl_w', title = 'Ctrl+W to app', keys = 'ctrl+w' },
    { id = 'ctrl_tab', title = 'Ctrl+Tab to app', keys = 'ctrl+tab' },
    { id = 'ctrl_shift_tab', title = 'Ctrl+Shift+Tab to app', keys = 'ctrl+shift+tab' },
    { id = 'ctrl_f', title = 'Ctrl+F to app', keys = 'ctrl+f' },
    { id = 'ctrl_r', title = 'Ctrl+R to app', keys = 'ctrl+r' },
    { id = 'ctrl_d', title = 'Ctrl+D to app', keys = 'ctrl+d' },
    { id = 'ctrl_h', title = 'Ctrl+H to app', keys = 'ctrl+h' },
    { id = 'ctrl_b', title = 'Ctrl+B to app', keys = 'ctrl+b' },
    { id = 'ctrl_shift_l', title = 'Ctrl+Shift+L to app', keys = 'ctrl+shift+l' },
  },
}

-- ----------------------------------------------------------------
-- Focus rule: passAll follows the context of the focused item.
-- nativeKeys = true means "keys belong to the app" (native UI).
-- ----------------------------------------------------------------

local nativeKeys = false

-- An item is page content when it is, or sits inside, the WebView
-- subtree: itself or any ancestor is a WebView, or carries the
-- "Web page" description of the tree's level-1 container.
local function isPageItem(item)
  local node = item
  for _ = 1, 30 do
    if node == nil then
      return false
    end
    local className = node.className or ''
    if className:sub(-7) == 'WebView' then
      return true
    end
    if node.contentDescription == 'Web page' then
      return true
    end
    node = node:parent()
  end
  return false
end

-- 'native', 'page', or nil when there is no item to judge.
local function verdict(item)
  if item == nil then
    return nil
  end
  if isPageItem(item) then
    return 'page'
  end
  return 'native'
end

local function applyContext(inputItem)
  local ok, err = pcall(function()
    local v = verdict(inputItem)
    if v == nil then
      -- No input-focused item to judge (for example while a popup
      -- window settles): let the accessibility-focused item decide.
      v = verdict(sf.screen.focused())
    end
    if v == nil then
      return
    end
    local native = (v == 'native')
    if native ~= nativeKeys then
      nativeKeys = native
      sf.keys.passAll(nativeKeys)
      sf.log(nativeKeys and 'context: native — keys to the app'
        or 'context: page — keys to SandFly')
    end
  end)
  if not ok then
    sf.log('classify failed, keeping context: ' .. tostring(err))
  end
end

sf.onInputFocus(function(event)
  if event and event.package == 'net.powerhouseapps.browser' then
    applyContext(event.node)
  end
end)

sf.onWindowChange(function()
  applyContext(sf.screen.inputFocused())
end)

sf.onAppEnter(function()
  applyContext(sf.screen.inputFocused())
end)

-- Classify whatever is focused as the script loads.
applyContext(sf.screen.inputFocused())

-- ----------------------------------------------------------------
-- Chord forwarding: a passAll pulse plus a Shizuku re-press.
-- ----------------------------------------------------------------

local forwarding = false
local shizukuDown = false
local shizukuWarned = false

local function forward(chord)
  if forwarding or shizukuDown then
    return
  end
  forwarding = true
  local ok, err = pcall(function()
    sf.keys.passAll(true)
    local sent, pressErr = pcall(sf.keys.press, chord)
    if not sent then
      -- sf.keys.press raises when Shizuku is not running or
      -- SandFly is not allowed in it (ScriptTouch.requireShizuku).
      shizukuDown = true
      sf.log('forward failed for ' .. chord .. ': ' .. tostring(pressErr))
      if not shizukuWarned then
        shizukuWarned = true
        sf.message('Browser keys need Shizuku running', { interrupt = false })
      end
    else
      -- Let the injected chord land before the pulse ends.
      sf.sleep(75)
      if pressErr == false then
        sf.log('press reported failure for ' .. chord)
      end
    end
    -- Restore the focus rule's state, whatever it now says: a
    -- forwarded chord may itself have moved focus into the bar.
    sf.keys.passAll(nativeKeys)
  end)
  if not ok then
    sf.log('forward error for ' .. chord .. ': ' .. tostring(err))
    pcall(sf.keys.passAll, nativeKeys)
  end
  forwarding = false
end

-- The chord each command re-presses, in sf.keys.press names
-- (Android key names; one call is one `input keyevent`, which
-- Android injects as a single chord).
local CHORDS = {
  alt_a = 'alt_left a',
  alt_b = 'alt_left b',
  alt_c = 'alt_left c',
  alt_d = 'alt_left d',
  alt_e = 'alt_left e',
  alt_f = 'alt_left f',
  alt_g = 'alt_left g',
  alt_h = 'alt_left h',
  alt_i = 'alt_left i',
  alt_j = 'alt_left j',
  alt_k = 'alt_left k',
  alt_l = 'alt_left l',
  alt_m = 'alt_left m',
  alt_n = 'alt_left n',
  alt_o = 'alt_left o',
  alt_p = 'alt_left p',
  alt_q = 'alt_left q',
  alt_r = 'alt_left r',
  alt_s = 'alt_left s',
  alt_t = 'alt_left t',
  alt_u = 'alt_left u',
  alt_v = 'alt_left v',
  alt_w = 'alt_left w',
  alt_x = 'alt_left x',
  alt_y = 'alt_left y',
  alt_z = 'alt_left z',
  alt_left = 'alt_left left',
  alt_right = 'alt_left right',
  ctrl_l = 'ctrl_left l',
  ctrl_t = 'ctrl_left t',
  ctrl_w = 'ctrl_left w',
  ctrl_tab = 'ctrl_left tab',
  ctrl_shift_tab = 'ctrl_left shift_left tab',
  ctrl_f = 'ctrl_left f',
  ctrl_r = 'ctrl_left r',
  ctrl_d = 'ctrl_left d',
  ctrl_h = 'ctrl_left h',
  ctrl_b = 'ctrl_left b',
  ctrl_shift_l = 'ctrl_left shift_left l',
}

for id, chord in pairs(CHORDS) do
  local pressed = chord
  sf.onCommand(id, function()
    forward(pressed)
  end)
end

sf.log('Powerhouse Browser keys loaded')
