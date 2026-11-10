-- Phone Actions and Switch, for SandFly (script API v2+).
--
-- Reworks two Google apps -- Phone (com.google.android.dialer) and
-- Contacts (com.google.android.contacts) -- the way iOS VoiceOver
-- handles lists, as designed and directed by the user:
--
-- RECENTS (the Phone app's call log):
-- - Swipe right / left moves entry to entry. The buttons inside each
--   entry card (the quick-contact avatar and the quick-call button)
--   are skipped, so navigation lands on entries only.
-- - Swipe down / up cycles the focused entry's actions, spoken as you
--   land on each: Call, Message, History, Quick contact, plus any
--   extra buttons the entry's expanded area actually has.
-- - Double-tap runs the selected action. With nothing selected,
--   double-tap CALLS -- it taps the entry's own quick-call button.
--   (Stock behavior expanded the entry instead; expanding now happens
--   behind the scenes when you run Message or History.)
--
-- CONTACTS (the list reached from the Phone app's drawer):
-- - Swipe right / left moves contact to contact.
-- - Swipe down / up cycles: Call, Message, Video call, Email,
--   Open card, Edit contact.
-- - Double-tap runs the selected action. With nothing selected,
--   double-tap CALLS: the script opens the contact and taps its Call
--   button for you.
--
-- SWITCHING:
-- - Three-finger swipe right or left toggles between Recents and
--   Contacts. From Recents it opens the drawer and taps Contacts;
--   from Contacts it taps Navigate up. From a contact's detail page,
--   one swipe goes back to the list, the next leaves to Recents.
--
-- SAFETY:
-- - Everything hands the gesture back untouched the moment it does
--   not apply: the keypad and voicemail tabs, the in-call screen,
--   the quick-contact popup, search boxes, and anywhere else keep
--   stock behavior. Message and History picks are verified against
--   the entry's real expanded buttons before anything is tapped;
--   a pick that is not there gets "Not on this entry", never a
--   blind tap.

local manifest = {
  id = 'phone-actions-switch',
  name = 'Phone Actions and Switch',
  version = '1.1',
  author = 'Atlas',
  description = 'iOS-style actions for the Phone app call log and the Contacts list: swipe right/left moves entry to entry skipping in-entry buttons, swipe down/up cycles actions, double-tap calls (or runs the selected action). Three-finger swipe left/right switches between Recents and Contacts.',
  minApiVersion = 2,
  testedApiVersion = 3,
  apps = { 'com.google.android.dialer', 'com.google.android.contacts' },
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'next_action', title = 'Next action', gesture = 'swipeDown' },
    { id = 'prev_action', title = 'Previous action', gesture = 'swipeUp' },
    { id = 'run_action', title = 'Run selected action / call', gesture = 'doubleTap' },
    { id = 'next_item', title = 'Next entry', gesture = 'swipeRight' },
    { id = 'prev_item', title = 'Previous entry', gesture = 'swipeLeft' },
    { id = 'switch_view', title = 'Switch Recents / Contacts', gesture = { 'threeFingerSwipeRight', 'threeFingerSwipeLeft' } },
  },
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function startsWith(s, head)
  if s == nil then return false end
  return s:sub(1, #head) == head
end

local function endsWith(s, tail)
  if s == nil then return false end
  return tail == '' or s:sub(-#tail) == tail
end

local function isInside(node, anc)
  local p = node
  local guard = 0
  while p ~= nil and guard < 40 do
    if p == anc then return true end
    p = p:parent()
    guard = guard + 1
  end
  return false
end

local function actionLabels(node)
  local out = {}
  local acts = node.actions
  if acts ~= nil then
    for _, a in ipairs(acts) do
      if type(a) == 'table' then
        if a.label ~= nil then out[#out + 1] = a.label end
      elseif type(a) == 'string' then
        out[#out + 1] = a
      end
    end
  end
  return out
end

local function hasAction(node, label)
  for _, l in ipairs(actionLabels(node)) do
    if l == label then return true end
  end
  return false
end

local function sortByPos(items)
  table.sort(items, function(a, b)
    local at = (a.bounds and a.bounds.top) or 0
    local bt = (b.bounds and b.bounds.top) or 0
    if at ~= bt then return at < bt end
    local al = (a.bounds and a.bounds.left) or 0
    local bl = (b.bounds and b.bounds.left) or 0
    return al < bl
  end)
  return items
end

local function focusedNode(event)
  if event ~= nil and event.node ~= nil then return event.node end
  return sf.screen.focused()
end

-- ---------------------------------------------------------------------------
-- Selection state (shared by both apps)
-- ---------------------------------------------------------------------------

local selKey = nil    -- identity of the item the selection belongs to
local selIdx = nil    -- index into selLabels
local selLabels = nil -- the cycle offered for that item

local function clearSelection()
  selKey, selIdx, selLabels = nil, nil, nil
end

local function cycle(step)
  -- Returns the newly selected label, or nil when there is no cycle.
  if selLabels == nil or #selLabels == 0 then return nil end
  if selIdx == nil then
    selIdx = (step > 0) and 1 or #selLabels
  else
    selIdx = selIdx + step
    if selIdx > #selLabels then selIdx = 1 end
    if selIdx < 1 then selIdx = #selLabels end
  end
  return selLabels[selIdx]
end

-- ---------------------------------------------------------------------------
-- RECENTS -- the call log
-- ---------------------------------------------------------------------------

local CARD_ID = 'com.google.android.dialer:id/call_log_entry_card'
local LOG_ID = 'com.google.android.dialer:id/call_log_recycler_view'
local EXPAND_LABEL = 'expand or collapse menu'

local function findCards()
  local cards = sf.screen.findAll({ id = CARD_ID }, 100) or {}
  if #cards == 0 then
    local all = sf.screen.findAll({ className = 'CardView' }, 100) or {}
    for _, c in ipairs(all) do
      if hasAction(c, EXPAND_LABEL) then cards[#cards + 1] = c end
    end
  end
  return sortByPos(cards)
end

local function cardOf(node)
  local p = node
  local guard = 0
  while p ~= nil and guard < 12 do
    if hasAction(p, EXPAND_LABEL) then return p end
    p = p:parent()
    guard = guard + 1
  end
  return nil
end

local function cardKey(card)
  return card.contentDescription or card.text or ''
end

local function cardChildByDesc(card, prefix)
  local kids = card:findAll({}, 60) or {}
  for _, k in ipairs(kids) do
    local d = k.contentDescription
    if d ~= nil and startsWith(d, prefix) then return k end
  end
  return nil
end

-- The entry's expanded-area buttons (Message, History, and whatever
-- else this entry type shows), visible ones only, in screen order.
local function cardButtons(card)
  local out = {}
  local kids = card:findAll({ className = 'Button' }, 40) or {}
  for _, k in ipairs(kids) do
    local t = k.text
    if t ~= nil and t ~= '' and k.visible ~= false then
      out[#out + 1] = k
    end
  end
  return sortByPos(out)
end

local function cardCycleLabels(card)
  local labels = { 'Call', 'Message', 'History', 'Quick contact' }
  local seen = {}
  for _, l in ipairs(labels) do seen[l] = true end
  for _, b in ipairs(cardButtons(card)) do
    if not seen[b.text] then
      labels[#labels + 1] = b.text
      seen[b.text] = true
    end
  end
  return labels
end

local function refindCard(key)
  for _, c in ipairs(findCards()) do
    if cardKey(c) == key then return c end
  end
  return nil
end

local function runCardPick(card, pick)
  local key = cardKey(card)
  if pick == 'Call' then
    local btn = cardChildByDesc(card, 'call ')
    if btn ~= nil then btn:click() else sf.speak('No call button') end
    return
  end
  if pick == 'Quick contact' then
    local av = cardChildByDesc(card, 'Quick contact for')
    if av ~= nil then av:click() else sf.speak('No quick contact') end
    return
  end
  -- Anything else lives in the expanded area. Expand if needed, then
  -- read the REAL buttons and tap the match -- never a blind tap.
  if #cardButtons(card) == 0 then
    pcall(function() return card:perform(EXPAND_LABEL) end)
    sf.sleep(450)
  end
  local fresh = refindCard(key) or card
  for _, b in ipairs(cardButtons(fresh)) do
    if b.text == pick then
      b:click()
      return
    end
  end
  sf.speak('Not on this entry')
end

-- ---------------------------------------------------------------------------
-- CONTACTS -- the list and its rows
-- ---------------------------------------------------------------------------

local CONTACTS_CONTENT_ID = 'com.google.android.contacts:id/content'
local VERB_CALL_ID = 'com.google.android.contacts:id/verb_call'

local function onContactDetail()
  return sf.screen.find({ id = 'com.google.android.contacts:id/quickcontact_fragment_root' }) ~= nil
end

local function contactsList()
  if onContactDetail() then return nil end
  local content = sf.screen.find({ id = CONTACTS_CONTENT_ID })
  if content == nil then return nil end
  local lists = content:findAll({ scrollable = true }, 10) or {}
  if #lists == 0 then return nil end
  return lists[1]
end

-- Topmost focusable rows of the list: a focusable item that sits
-- inside another focusable item (like the Share button inside the
-- "Your info" row) is not a stop of its own.
local function listRows(list)
  local all = list:findAll({ focusable = true }, 200) or {}
  local rows = {}
  for _, it in ipairs(all) do
    local nested = false
    for _, other in ipairs(all) do
      if other ~= it and isInside(it, other) then
        nested = true
        break
      end
    end
    if not nested then rows[#rows + 1] = it end
  end
  return sortByPos(rows)
end

local function rowTexts(row)
  local out = {}
  local tvs = row:findAll({ className = 'TextView' }, 12) or {}
  for _, t in ipairs(tvs) do
    if t.text ~= nil and t.text ~= '' then out[#out + 1] = t.text end
  end
  return out
end

-- A contact row carries exactly one text: the name. "Create contact"
-- has one too but is not a contact; "Your info" has two.
local function isContactRow(row)
  local texts = rowTexts(row)
  if #texts ~= 1 then return false end
  return texts[1] ~= 'Create contact'
end

local function rowKey(row)
  local texts = rowTexts(row)
  return table.concat(texts, ' | ')
end

local function rowOf(list, node)
  local p = node
  local guard = 0
  while p ~= nil and guard < 12 do
    if p:parent() ~= nil and isInside(p, list) and p.focusable then
      -- p is a stop if no focusable ancestor of p is also in the list
      local q = p:parent()
      local outerFocusable = false
      local g2 = 0
      while q ~= nil and g2 < 12 do
        if q == list then break end
        if q.focusable then outerFocusable = true break end
        q = q:parent()
        g2 = g2 + 1
      end
      if not outerFocusable then return p end
    end
    p = p:parent()
    guard = guard + 1
  end
  return nil
end

local CONTACT_CYCLE = { 'Call', 'Message', 'Video call', 'Email', 'Open card', 'Edit contact' }

local function verbButton(containerId)
  local box = sf.screen.find({ id = containerId })
  if box == nil then return nil end
  local btns = box:findAll({ className = 'Button' }, 10) or {}
  if #btns > 0 then return btns[1] end
  return nil
end

local function runContactPick(row, pick)
  row:click()
  local ready = sf.screen.waitFor({ id = VERB_CALL_ID }, 2500)
  if ready == nil then
    sf.speak('Contact did not open')
    return
  end
  if pick == 'Open card' then return end
  if pick == 'Edit contact' then
    local edit = sf.screen.find({ id = 'com.google.android.contacts:id/menu_insert_or_edit' })
    if edit ~= nil then edit:click() else sf.speak('Not available') end
    return
  end
  local idByPick = {
    ['Call'] = 'com.google.android.contacts:id/verb_call',
    ['Message'] = 'com.google.android.contacts:id/verb_text',
    ['Video call'] = 'com.google.android.contacts:id/verb_video',
    ['Email'] = 'com.google.android.contacts:id/verb_email',
  }
  local btn = verbButton(idByPick[pick])
  if btn == nil then
    sf.speak('Not available')
    return
  end
  if pick == 'Email' and btn.enabled == false then
    sf.speak('No email for this contact')
    return
  end
  btn:click()
end

-- ---------------------------------------------------------------------------
-- Traversal -- swipe right / left moves item to item
-- ---------------------------------------------------------------------------

local function moveFocus(stops, keyOf, node, step, list)
  if #stops == 0 then return false end
  local curIdx = nil
  for i, s in ipairs(stops) do
    if node == s or isInside(node, s) then
      curIdx = i
      break
    end
  end
  if curIdx == nil then
    -- Focus is inside the list but not on a stop (a chip, a banner, a
    -- header): take the first stop past it in the swipe direction.
    local top = (node.bounds and node.bounds.top) or 0
    if step > 0 then
      for i, s in ipairs(stops) do
        if ((s.bounds and s.bounds.top) or 0) > top then
          s:focus()
          return true
        end
      end
    else
      for i = #stops, 1, -1 do
        if ((stops[i].bounds and stops[i].bounds.top) or 0) < top then
          stops[i]:focus()
          return true
        end
      end
      return false
    end
    -- No stop past it in the swipe direction: fall through to the
    -- scroll attempt below.
  end
  if curIdx ~= nil then
    local target = curIdx + step
    if target >= 1 and target <= #stops then
      stops[target]:focus()
      return true
    end
  end
  -- At the edge: scroll the list and look again.
  local oldKeys = {}
  for _, s in ipairs(stops) do oldKeys[keyOf(s)] = true end
  if step > 0 then
    pcall(function() return list:scrollForward() end)
  else
    pcall(function() return list:scrollBackward() end)
  end
  sf.sleep(350)
  return 'scrolled', oldKeys
end

local function moveDialer(node, step)
  local list = sf.screen.find({ id = LOG_ID })
  if list == nil then return false end
  if not isInside(node, list) then return false end
  local stops = findCards()
  local res, oldKeys = moveFocus(stops, cardKey, node, step, list)
  if res == 'scrolled' then
    local fresh = findCards()
    if step > 0 then
      for _, s in ipairs(fresh) do
        if not oldKeys[cardKey(s)] then s:focus() return true end
      end
      sf.speak('End of list')
      return true
    else
      for i = #fresh, 1, -1 do
        if not oldKeys[cardKey(fresh[i])] then fresh[i]:focus() return true end
      end
      sf.speak('Start of list')
      return true
    end
  end
  return res
end

local function moveContacts(node, step)
  local list = contactsList()
  if list == nil then return false end
  if not isInside(node, list) then return false end
  local stops = listRows(list)
  local res, oldKeys = moveFocus(stops, rowKey, node, step, list)
  if res == 'scrolled' then
    local freshList = contactsList()
    if freshList == nil then return true end
    local fresh = listRows(freshList)
    if step > 0 then
      for _, s in ipairs(fresh) do
        if not oldKeys[rowKey(s)] then s:focus() return true end
      end
      sf.speak('End of list')
      return true
    else
      for i = #fresh, 1, -1 do
        if not oldKeys[rowKey(fresh[i])] then fresh[i]:focus() return true end
      end
      sf.speak('Start of list')
      return true
    end
  end
  return res
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------

sf.onCommand('next_action', function(event) return cycleCommand(event, 1) end)
sf.onCommand('prev_action', function(event) return cycleCommand(event, -1) end)

function cycleCommand(event, step)
  local node = focusedNode(event)
  if node == nil then return false end
  local app = sf.app()
  local pkg = (app and app.package) or ''
  if pkg == 'com.google.android.dialer' then
    local card = cardOf(node)
    if card == nil then return false end
    local key = cardKey(card)
    if selKey ~= key then
      clearSelection()
      selKey = key
      selLabels = cardCycleLabels(card)
    end
    local label = cycle(step)
    if label == nil then return false end
    sf.speak(label)
    return true
  end
  if pkg == 'com.google.android.contacts' then
    local list = contactsList()
    if list == nil then return false end
    local row = rowOf(list, node)
    if row == nil or not isContactRow(row) then return false end
    local key = rowKey(row)
    if selKey ~= key then
      clearSelection()
      selKey = key
      selLabels = CONTACT_CYCLE
    end
    local label = cycle(step)
    if label == nil then return false end
    sf.speak(label)
    return true
  end
  return false
end

sf.onCommand('run_action', function(event)
  local node = focusedNode(event)
  if node == nil then return false end
  local app = sf.app()
  local pkg = (app and app.package) or ''
  if pkg == 'com.google.android.dialer' then
    local card = cardOf(node)
    if card == nil then return false end
    local key = cardKey(card)
    if selKey == key and selIdx ~= nil and selLabels ~= nil then
      local pick = selLabels[selIdx]
      clearSelection()
      runCardPick(card, pick)
    else
      runCardPick(card, 'Call')
    end
    return true
  end
  if pkg == 'com.google.android.contacts' then
    local list = contactsList()
    if list == nil then return false end
    local row = rowOf(list, node)
    if row == nil or not isContactRow(row) then return false end
    local key = rowKey(row)
    if selKey == key and selIdx ~= nil and selLabels ~= nil then
      local pick = selLabels[selIdx]
      clearSelection()
      runContactPick(row, pick)
    else
      runContactPick(row, 'Call')
    end
    return true
  end
  return false
end)

sf.onCommand('next_item', function(event)
  local node = focusedNode(event)
  if node == nil then return false end
  local app = sf.app()
  local pkg = (app and app.package) or ''
  if pkg == 'com.google.android.dialer' then return moveDialer(node, 1) end
  if pkg == 'com.google.android.contacts' then return moveContacts(node, 1) end
  return false
end)

sf.onCommand('prev_item', function(event)
  local node = focusedNode(event)
  if node == nil then return false end
  local app = sf.app()
  local pkg = (app and app.package) or ''
  if pkg == 'com.google.android.dialer' then return moveDialer(node, -1) end
  if pkg == 'com.google.android.contacts' then return moveContacts(node, -1) end
  return false
end)

sf.onCommand('switch_view', function(event)
  local app = sf.app()
  local pkg = (app and app.package) or ''
  local act = (app and app.activity) or ''
  if pkg == 'com.google.android.dialer' then
    if not act:find('MainActivity', 1, true) then return false end
    local drawer = sf.screen.find({ id = 'com.google.android.dialer:id/design_navigation_view' })
    if drawer == nil then
      local btn = sf.screen.find({ contentDescription = 'Open navigation drawer' })
      if btn == nil then return false end
      btn:click()
      drawer = sf.screen.waitFor({ id = 'com.google.android.dialer:id/design_navigation_view' }, 2000)
      if drawer == nil then
        sf.speak('Menu did not open')
        return true
      end
    end
    local texts = sf.screen.findAll({ id = 'com.google.android.dialer:id/design_menu_item_text' }, 20) or {}
    for _, t in ipairs(texts) do
      if t.text == 'Contacts' then
        local row = t:parent()
        local ok = false
        if row ~= nil then
          ok = pcall(function() return row:click() end)
        end
        if not ok then pcall(function() return t:click() end) end
        return true
      end
    end
    sf.speak('Contacts not in menu')
    return true
  end
  if pkg == 'com.google.android.contacts' then
    if not act:find('ContactLeafActivity', 1, true) then return false end
    local up = sf.screen.find({ contentDescription = 'Navigate up' })
    if up == nil then return false end
    up:click()
    return true
  end
  return false
end)

-- Changing focus to a different item drops the pending selection, so a
-- stale pick can never fire on the wrong entry.
sf.onFocus(function(item)
  if selKey == nil then return end
  if item == nil then
    clearSelection()
    return
  end
  local app = sf.app()
  local pkg = (app and app.package) or ''
  local key = nil
  if pkg == 'com.google.android.dialer' then
    local card = cardOf(item)
    if card ~= nil then key = cardKey(card) end
  elseif pkg == 'com.google.android.contacts' then
    local list = contactsList()
    if list ~= nil then
      local row = rowOf(list, item)
      if row ~= nil then key = rowKey(row) end
    end
  end
  if key ~= selKey then clearSelection() end
end)
