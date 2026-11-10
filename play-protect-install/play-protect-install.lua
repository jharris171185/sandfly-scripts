-- Play Protect Install
-- On Google Play Protect's "App scan recommended" prompt, Alt+I taps
-- "Install without scanning" (a link inside a paragraph, not a real
-- button, so tab order can never reach it), then watches for the PIN
-- field that follows and puts focus in it.
--
-- Idea, key choice and design: Justin Harris. Built with Atlas.
-- Runs in every app but stays out of the way: outside the Play
-- Protect prompt, Alt+I is handed straight back untouched.

local manifest = {
  id = 'play-protect-install',
  name = 'Play Protect Install',
  version = '1.0',
  author = 'Justin Harris',
  description = 'Alt+I on the Play Protect scan prompt chooses Install without scanning, then focuses the PIN field.',
  minApiVersion = 2,
  testedApiVersion = 3,
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'install', title = 'Install without scanning', keys = 'alt+i' },
  },
}

-- After the tap, watch for the PIN/password field and focus it.
-- Runs as its own task, so it survives the hop from the Play Store
-- prompt to whatever screen asks for the PIN.
local function watchForPin()
  local deadline = os.time() + 20
  while os.time() < deadline do
    local field = sf.screen.find({ password = true, editable = true })
    if not field then
      field = sf.screen.find({ password = true })
    end
    if field then
      field:focus()
      pcall(function() field:perform('focusInput') end)
      sf.speak('PIN field.')
      return
    end
    sf.sleep(400)
  end
end

sf.onCommand('install', function(event)
  -- Only act on the Play Protect prompt in the Play Store app.
  -- Anywhere else, hand the keys back before doing anything slow,
  -- so Alt+I keeps its normal meaning in other apps.
  local app = sf.app()
  local pkg = nil
  if type(app) == 'table' then pkg = app.package else pkg = app end
  if pkg ~= 'com.android.vending' then return false end
  local item = sf.screen.find({ textContains = 'Install without scanning' })
  if not item then return false end

  -- The link is text inside this paragraph item. Best aim: read the
  -- rendered text back with positions and tap the exact line.
  local tapped = false
  local ok, result = pcall(function() return item:recognizeText() end)
  if ok and result and result.blocks then
    for _, block in ipairs(result.blocks) do
      if tapped then break end
      for _, line in ipairs(block.lines or {}) do
        if line.text and line.text:find('Install without scanning', 1, true) then
          local b = line.bounds
          if b then
            sf.touch.tap((b.left + b.right) / 2, (b.top + b.bottom) / 2)
            tapped = true
            break
          end
        end
      end
    end
  end
  if not tapped then
    -- Fallback: the link is the paragraph's last line, at its left.
    local b = item.bounds
    if b then
      sf.touch.tap(b.left + (b.right - b.left) * 0.22,
                   b.bottom - (b.bottom - b.top) * 0.10)
      tapped = true
    end
  end

  if tapped then
    sf.speak('Installing without scanning. Watching for the PIN field.')
    sf.run(watchForPin)
  else
    sf.speak('Install without scanning was not tapped.')
  end
end)
