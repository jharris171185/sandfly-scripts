-- Thunderbird Keys and Actions, for SandFly (script API v2+).
--
-- Brings desktop Thunderbird's keyboard habits to Thunderbird for
-- Android (net.thunderbird.android), which has almost no keyboard
-- support of its own, and reworks the message list's touch behavior
-- the way iOS VoiceOver handles lists. Designed and directed by the
-- user; fitted to screen trees captured from the real app on
-- November 5, 2026.
--
-- KEYBOARD (message list and message view):
-- - Ctrl+N        New message (taps the Compose button).
-- - Ctrl+R        Reply (message view: the header Reply button.
--                 List: opens the focused message, then replies).
-- - Ctrl+Shift+R  Reply all (via the header overflow menu).
-- - Ctrl+L        Forward (via the header overflow menu).
-- - Delete        Delete. In the message view, the open message.
--                 In the list: the focused message -- or, when a
--                 selection is active, the WHOLE selection (bulk
--                 delete is a feature, by the user's design).
-- - Space         Toggle selection of the focused list row.
-- - Arrow keys    In the list, move message to message (the script
--                 claims them there so they skip the Select stop;
--                 everywhere else they behave as stock).
-- - SandFly+J     Message view: jump between the headers and the
--                 message body. List: the door between the list and
--                 the toolbar, both directions (the arrows stay in
--                 the list, so J is how you get out to the toolbar
--                 and back).
-- In compose, SandFly+Enter (or Ctrl+Enter) taps Send. (Plain
-- Ctrl+Enter cannot be caught while typing -- SandFly does not pass
-- unmodified keys to scripts inside edit fields -- so the SandFly
-- key does the job, same as the user's Jump and Send script.)
--
-- TOUCH (message list):
-- - Swipe right / left moves message to message. The Select area
--   inside each row is skipped as a navigation stop; selecting
--   becomes an action instead of a second swipe on every row.
-- - Swipe down / up cycles the row's actions, spoken as you land:
--   Select (or Deselect), Reply, Reply all, Forward, Delete,
--   Mark as read / Mark as unread, Toggle star.
-- - Double-tap runs the selected action. With nothing selected,
--   double-tap opens the message, as stock.
-- - SELECTION MODE (long-press a message to enter it, stock):
--   while it is active, double-tap on a row toggles that row's
--   selection instead of opening it. After each toggle the script
--   puts focus back on the row if the app moved it, so bulk
--   selecting keeps your place. Mode ends when an action runs,
--   as stock.
--
-- MENU: deliberately empty. Every feature lives on its keys and
-- gestures; nothing is added to the SandFly menu. All commands are
-- still listed on this script's page in SandFly settings, where
-- their bindings can be changed or turned off.
--
-- HOW THE LIST ACTIONS WORK: Reply / Reply all / Forward open the
-- message and tap the real buttons. Delete / Mark / Star select
-- the row (if needed) and tap the real button on the selection
-- bar the app itself shows. Every pick is verified against what
-- is actually on screen before anything is tapped.

local manifest = {
  id = 'thunderbird-keys-actions',
  name = 'Thunderbird Keys and Actions',
  version = '1.3',
  author = 'Atlas',
  description = 'Desktop-style keyboard shortcuts for Thunderbird Android (Ctrl+N, Ctrl+R, Ctrl+Shift+R, Ctrl+L, Delete, Space to select, SandFly+J headers/body, SandFly+Enter to send) plus iOS-style list actions: swipe right/left moves message to message skipping the Select stop, swipe down/up cycles actions, double-tap runs one; in selection mode double-tap toggles selection.',
  minApiVersion = 2,
  testedApiVersion = 3,
  apps = { 'net.thunderbird.android' },
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'next_item', title = 'Next message', gesture = 'swipeRight' },
    { id = 'prev_item', title = 'Previous message', gesture = 'swipeLeft' },
    { id = 'next_action', title = 'Next action', gesture = 'swipeDown' },
    { id = 'prev_action', title = 'Previous action', gesture = 'swipeUp' },
    { id = 'run_action', title = 'Run selected action', gesture = 'doubleTap' },
    { id = 'compose_new', title = 'New message', keys = 'ctrl+n' },
    { id = 'reply', title = 'Reply', keys = 'ctrl+r' },
    { id = 'reply_all', title = 'Reply all', keys = 'ctrl+shift+r' },
    { id = 'forward', title = 'Forward', keys = 'ctrl+l' },
    { id = 'delete_key', title = 'Delete message or selection', keys = 'delete' },
    { id = 'toggle_select', title = 'Toggle selection', keys = 'space' },
    { id = 'next_right', title = 'Next message (Right)', keys = 'right' },
    { id = 'next_down', title = 'Next message (Down)', keys = 'down' },
    { id = 'prev_left', title = 'Previous message (Left)', keys = 'left' },
    { id = 'prev_up', title = 'Previous message (Up)', keys = 'up' },
    { id = 'jump', title = 'Jump headers / body', keys = 'sf+j' },
    { id = 'send', title = 'Send', keys = 'sf+enter' },
    { id = 'send_ctrl', title = 'Send (Ctrl+Enter)', keys = 'ctrl+enter' },
  },
}

local PKG = 'net.thunderbird.android'
local ID = PKG .. ':id/'

-- ----------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------

local function label(item)
  if not item then return '' end
  local d = item.contentDescription
  if d and d ~= '' then return d end
  return item.text or ''
end

local function isInside(inner, outer)
  if not inner or not outer or not inner.bounds or not outer.bounds then
    return false
  end
  local cx = (inner.bounds.left + inner.bounds.right) / 2
  local cy = (inner.bounds.top + inner.bounds.bottom) / 2
  return cx >= outer.bounds.left and cx <= outer.bounds.right
     and cy >= outer.bounds.top and cy <= outer.bounds.bottom
end

local function findId(short)
  return sf.screen.find({ id = ID .. short })
end

local function activityName()
  local ok, app = pcall(sf.app)
  if ok and app and app.activity then return app.activity end
  return ''
end

local function inCompose()
  if activityName():find('MessageCompose', 1, true) then return true end
  return findId('send') ~= nil and findId('message_content') ~= nil
end

local function inMessageView()
  return findId('menu_primary_action') ~= nil and findId('message_list') == nil
end

local function messageList()
  return sf.screen.find({ id = ID .. 'message_list', className = 'RecyclerView' })
end

local function selectionActive()
  return sf.screen.find({ id = ID .. 'action_mode_bar' }) ~= nil
      or sf.screen.find({ id = ID .. 'action_bar_title' }) ~= nil
end

-- ----------------------------------------------------------------
-- Message list rows
-- ----------------------------------------------------------------

local function selectArea(row)
  if not row then return nil end
  return row:find({ id = ID .. 'contact_picture_click_area' })
end

local function listRows()
  local list = messageList()
  if not list then return nil, nil end
  local rows = {}
  local kids = list:children() or {}
  for _, k in ipairs(kids) do
    if selectArea(k) then rows[#rows + 1] = k end
  end
  return rows, list
end

local function rowKey(row)
  local subj = row:find({ id = ID .. 'subject' })
  local date = row:find({ id = ID .. 'date' })
  local who = subj and (subj.contentDescription or subj.text or '') or ''
  local when = date and (date.text or '') or ''
  return who .. '|' .. when
end

local function rowUnread(row)
  local subj = row:find({ id = ID .. 'subject' })
  local d = subj and subj.contentDescription or ''
  return d:sub(1, 7) == 'unread,'
end

local function rowSelected(row)
  local area = selectArea(row)
  return area ~= nil and label(area) == 'Deselect'
end

local function focusedRow()
  local f = sf.screen.focused()
  if not f then return nil end
  local rows = listRows()
  if not rows then return nil end
  for _, r in ipairs(rows) do
    if f == r or isInside(f, r) then return r end
  end
  return nil
end

-- After tapping a row's Select area the app may throw focus up to
-- the selection bar. If focus left the row, put it back so bulk
-- selecting keeps your place; if it stayed, just say the new state.
local function toggleRowSelection(row)
  local area = selectArea(row)
  if not area then return false end
  local key = rowKey(row)
  area:click()
  sf.sleep(300)
  local f = sf.screen.focused()
  local stillThere = false
  if f then
    local rows = listRows()
    if rows then
      for _, r in ipairs(rows) do
        if rowKey(r) == key and (f == r or isInside(f, r)) then
          stillThere = true
          break
        end
      end
    end
  end
  local rows = listRows()
  if rows then
    for _, r in ipairs(rows) do
      if rowKey(r) == key then
        if not stillThere then
          r:focus()
        else
          sf.speak(rowSelected(r) and 'Selected' or 'Deselected')
        end
        return true
      end
    end
  end
  return true
end

-- ----------------------------------------------------------------
-- Traversal: swipe right / left, message to message
-- ----------------------------------------------------------------

local function rowKeys(rows)
  local s = {}
  for _, r in ipairs(rows) do s[rowKey(r)] = true end
  return s
end

local function scrollForMore(list, rows, forward)
  local before = rowKeys(rows)
  if forward then list:scrollForward() else list:scrollBackward() end
  sf.sleep(350)
  local now = listRows()
  if not now then return nil end
  for _, r in ipairs(now) do
    if not before[rowKey(r)] then return now end
  end
  return nil
end

local function moveItem(dir)
  local rows, list = listRows()
  if not rows or #rows == 0 then return false end
  local cur = focusedRow()
  if not cur then return false end
  local idx = nil
  for i, r in ipairs(rows) do
    if rowKey(r) == rowKey(cur) then idx = i break end
  end
  if not idx then return false end
  local target = rows[idx + dir]
  if target then
    target:focus()
    return true
  end
  local grown = scrollForMore(list, rows, dir > 0)
  if grown then
    local edge = dir > 0 and grown[#grown] or grown[1]
    -- focus the first NEW row in the travel direction
    local before = rowKeys(rows)
    if dir > 0 then
      for _, r in ipairs(grown) do
        if not before[rowKey(r)] then edge = r break end
      end
    else
      for i = #grown, 1, -1 do
        if not before[rowKey(grown[i])] then edge = grown[i] break end
      end
    end
    if edge then edge:focus() return true end
  end
  sf.speak(dir > 0 and 'End of list' or 'Start of list')
  return true
end

-- ----------------------------------------------------------------
-- Row actions: cycle and run
-- ----------------------------------------------------------------

local pending = nil -- { key=..., idx=..., labels={...} }

sf.onFocus(function(item)
  if pending and item then
    local r = nil
    local rows = listRows()
    if rows then
      for _, cand in ipairs(rows) do
        if item == cand or isInside(item, cand) then r = cand break end
      end
    end
    if r and rowKey(r) ~= pending.key then pending = nil end
    if not r and inMessageView() then pending = nil end
  end
end)

local function actionLabels(row)
  local labels = {}
  labels[#labels + 1] = rowSelected(row) and 'Deselect' or 'Select'
  labels[#labels + 1] = 'Reply'
  labels[#labels + 1] = 'Reply all'
  labels[#labels + 1] = 'Forward'
  labels[#labels + 1] = 'Delete'
  labels[#labels + 1] = rowUnread(row) and 'Mark as read' or 'Mark as unread'
  labels[#labels + 1] = 'Toggle star'
  return labels
end

local function cycleAction(dir)
  local row = focusedRow()
  if not row then return false end
  local key = rowKey(row)
  local labels = actionLabels(row)
  if not pending or pending.key ~= key then
    pending = { key = key, idx = dir > 0 and 1 or #labels, labels = labels }
  else
    pending.labels = labels
    pending.idx = pending.idx + dir
    if pending.idx > #labels then pending.idx = 1 end
    if pending.idx < 1 then pending.idx = #labels end
  end
  sf.speak(labels[pending.idx])
  return true
end

-- Open a popup menu item by its exact title text and tap its row.
local function tapMenuItem(text, timeout)
  local t = sf.screen.waitFor({ text = text }, timeout or 2000, 100)
  if not t then return false end
  local p = t:parent()
  if p then p:click() else t:click() end
  return true
end

-- From an open message: Reply all / Forward live in the header
-- overflow beside the Reply button.
local function overflowAction(text)
  local ov = findId('menu_overflow')
  if not ov then return false end
  ov:click()
  return tapMenuItem(text, 2000)
end

local function openThen(row, what)
  row:click()
  if what == 'Reply' then
    local b = sf.screen.waitFor({ id = ID .. 'menu_primary_action' }, 2500, 100)
    if not b then return false end
    b:click()
    return true
  end
  local ov = sf.screen.waitFor({ id = ID .. 'menu_overflow' }, 2500, 100)
  if not ov then return false end
  ov:click()
  return tapMenuItem(what, 2000)
end

-- Delete / Mark / Star run through the app's own selection bar.
local function barAction(row, barId)
  if selectionActive() then
    if not rowSelected(row) then
      sf.speak('Selection active')
      return true
    end
  else
    local area = selectArea(row)
    if not area then return false end
    area:click()
  end
  local b = sf.screen.waitFor({ id = ID .. barId }, 2000, 100)
  if not b then
    sf.speak('Not available')
    return true
  end
  b:click()
  return true
end

local function runAction()
  local row = focusedRow()
  if not row then return false end
  -- Selection mode: double-tap toggles this row, unless an action
  -- was explicitly cycled to first.
  if selectionActive() and not (pending and pending.key == rowKey(row)) then
    return toggleRowSelection(row)
  end
  if not pending or pending.key ~= rowKey(row) then
    return false -- nothing selected: stock double-tap opens it
  end
  local pick = pending.labels[pending.idx]
  pending = nil
  if pick == 'Select' or pick == 'Deselect' then
    return toggleRowSelection(row)
  elseif pick == 'Reply' or pick == 'Reply all' or pick == 'Forward' then
    if not openThen(row, pick) then sf.speak('Could not open message') end
    return true
  elseif pick == 'Delete' then
    return barAction(row, 'delete')
  elseif pick == 'Mark as read' or pick == 'Mark as unread' then
    return barAction(row, 'mark_as_read')
  elseif pick == 'Toggle star' then
    return barAction(row, 'flag')
  end
  return true
end

-- ----------------------------------------------------------------
-- Keyboard commands
-- ----------------------------------------------------------------

local function doComposeNew()
  if inCompose() then return false end
  local btns = sf.screen.findAll({ contentDescription = 'Compose', clickable = true }, 5)
  for _, b in ipairs(btns or {}) do
    b:click()
    return true
  end
  return false
end

local function doReplyLike(what)
  if inCompose() then return false end
  if inMessageView() then
    if what == 'Reply' then
      local b = findId('menu_primary_action')
      if not b then return false end
      b:click()
      return true
    end
    return overflowAction(what)
  end
  local row = focusedRow()
  if not row then return false end
  if not openThen(row, what) then sf.speak('Could not open message') end
  return true
end

local function doDeleteKey()
  if inCompose() then return false end
  if inMessageView() then
    local b = findId('delete')
    if not b then return false end
    b:click()
    return true
  end
  if selectionActive() then
    local b = findId('delete')
    if not b then return false end
    b:click()
    return true
  end
  local row = focusedRow()
  if not row then return false end
  return barAction(row, 'delete')
end

local function doToggleSelectKey()
  local row = focusedRow()
  if not row then return false end
  return toggleRowSelection(row)
end

local function doJump()
  if inCompose() then return false end
  if inMessageView() then
    local f = sf.screen.focused()
    local inBody = false
    if f then
      if (f.className or ''):find('WebView', 1, true) then
        inBody = true
      else
        local wvs = sf.screen.findAll({ className = 'WebView' }, 10) or {}
        for _, wv in ipairs(wvs) do
          if isInside(f, wv) then inBody = true break end
        end
      end
    end
    if inBody then
      local subj = findId('subject')
      if subj then subj:focus() return true end
      local pc = findId('participants_container')
      if pc then pc:focus() return true end
      return false
    end
    local wvs = sf.screen.findAll({ className = 'WebView' }, 10) or {}
    local best, bestArea = nil, -1
    for _, wv in ipairs(wvs) do
      if wv.focusable and wv.bounds then
        local area = (wv.bounds.right - wv.bounds.left)
                   * (wv.bounds.bottom - wv.bounds.top)
        if area > bestArea then best, bestArea = wv, area end
      end
    end
    if best then best:focus() return true end
    local heads = sf.screen.findAll({ heading = true }, 20) or {}
    for _, h in ipairs(heads) do
      for _, wv in ipairs(wvs) do
        if isInside(h, wv) then h:focus() return true end
      end
    end
    return false
  end
  -- List: SandFly+J is the door between the list and the toolbar
  -- (the script's arrows keep you in the list otherwise). On a
  -- message it takes you up to the toolbar; from the toolbar it
  -- drops you back on the first message.
  local rows = listRows()
  if not rows or #rows == 0 then return false end
  if focusedRow() then
    local nav = sf.screen.find({ contentDescription = 'Navigate up', clickable = true })
    if nav then nav:focus() return true end
    local comp = sf.screen.find({ contentDescription = 'Compose', clickable = true })
    if comp then comp:focus() return true end
    return false
  end
  rows[1]:focus()
  return true
end

local function doSend()
  if not inCompose() then return false end
  local b = findId('send')
  if not b then
    sf.speak('No send button')
    return true
  end
  if b.enabled == false then
    sf.speak('Nothing to send')
    return true
  end
  b:click()
  return true
end

-- ----------------------------------------------------------------
-- Command wiring
-- ----------------------------------------------------------------

sf.onCommand('next_item', function(event) return moveItem(1) end)
sf.onCommand('prev_item', function(event) return moveItem(-1) end)
sf.onCommand('next_action', function(event) return cycleAction(1) end)
sf.onCommand('prev_action', function(event) return cycleAction(-1) end)
sf.onCommand('run_action', function(event) return runAction() end)
sf.onCommand('compose_new', function(event) return doComposeNew() end)
sf.onCommand('reply', function(event) return doReplyLike('Reply') end)
sf.onCommand('reply_all', function(event) return doReplyLike('Reply all') end)
sf.onCommand('forward', function(event) return doReplyLike('Forward') end)
sf.onCommand('delete_key', function(event) return doDeleteKey() end)
sf.onCommand('toggle_select', function(event) return doToggleSelectKey() end)
sf.onCommand('jump', function(event) return doJump() end)
sf.onCommand('send', function(event) return doSend() end)
sf.onCommand('send_ctrl', function(event) return doSend() end)
sf.onCommand('next_right', function(event) return moveItem(1) end)
sf.onCommand('next_down', function(event) return moveItem(1) end)
sf.onCommand('prev_left', function(event) return moveItem(-1) end)
sf.onCommand('prev_up', function(event) return moveItem(-1) end)

return manifest
