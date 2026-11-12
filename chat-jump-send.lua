local manifest = {
  id = 'chat-jump-send',
  name = 'Jump and Send',
  version = '3.2',
  author = 'Atlas',
  description = 'One jump key for browsing and chat. In Chrome, SandFly plus J jumps past the toolbar into the web page content. In Muse, Gemini, ChatGPT, Google Messages and Facebook Messenger, SandFly plus J jumps between the message box and the most recent message, and SandFly plus Enter sends. On the Messenger home screen, J jumps straight to your most recent chat. Google Messages on a tablet (paired web view) gets a three-stop cycle. In YouTube, J jumps past the toolbar and filter chips straight to the first video. Send does nothing in Chrome or YouTube. In Telegram, SandFly plus J jumps between the message box and the most recent message (or into the topics or chat list), plain Up and Down step within the list you are in and nowhere else, and SandFly plus Enter sends.',
  minApiVersion = 2,
  testedApiVersion = 3,
  apps = {
    'com.android.chrome',
    'com.facebook.aura',
    'com.google.android.apps.bard',
    'com.google.android.googlequicksearchbox',
    'com.openai.chatgpt',
    'com.google.android.apps.messaging',
    'com.facebook.orca',
    'com.google.android.youtube',
    'org.telegram.messenger',
  },
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'jump', title = 'Jump', keys = 'sf+j' },
    { id = 'send', title = 'Send message', keys = { 'sf+enter', 'ctrl+enter' } },
    { id = 'tgNext', title = 'Next item (Telegram)', keys = 'sf+n' },
    { id = 'tgPrev', title = 'Previous item (Telegram)', keys = 'sf+p' },
  },
}

local function currentApp()
  local app = sf.app()
  if app ~= nil then
    return app.package or '', app.activity or ''
  end
  return '', ''
end

-- ---------- shared helpers ----------

local function findEditField()
  local edits = sf.screen.findAll({ editable = true }, 20)
  local best, bestBottom = nil, -1
  for _, e in ipairs(edits) do
    if e.bounds ~= nil and e.bounds.bottom > bestBottom then
      best, bestBottom = e, e.bounds.bottom
    end
  end
  return best
end

local function isInside(item, ancestor)
  local node = item
  for _ = 1, 12 do
    if node == nil then
      return false
    end
    if node == ancestor then
      return true
    end
    node = node:parent()
  end
  return false
end

local function focusEdit(edit)
  edit:focus()
  edit:perform('focusInput')
end

local function climbToFocusable(item, maxSteps)
  local node = item
  for _ = 1, maxSteps do
    if node == nil then
      return item
    end
    if node.focusable then
      return node
    end
    node = node:parent()
  end
  return item
end

local function classContains(item, word)
  if item == nil or item.className == nil then
    return false
  end
  return string.find(item.className, word, 1, true) ~= nil
end

-- ---------- Chrome: jump into the page content ----------

local function chromeFocusContent()
  local web = sf.screen.find({ className = 'WebView' })
  if web ~= nil then
    local heading = web:find({ heading = true })
    if heading ~= nil then
      heading:focus()
      return
    end
    local first = web:find({ focusable = true })
    if first ~= nil then
      first:focus()
      return
    end
    web:focus()
    return
  end
  local anyHeading = sf.screen.find({ heading = true })
  if anyHeading ~= nil then
    anyHeading:focus()
    return
  end
  sf.speak('No page content found')
end

-- ---------- generic chat landmarks ----------

local function findConversation()
  local lists = sf.screen.findAll({ scrollable = true }, 20)
  local best, bestArea = nil, -1
  for _, l in ipairs(lists) do
    if l.bounds ~= nil then
      local a = (l.bounds.right - l.bounds.left) * (l.bounds.bottom - l.bounds.top)
      if a > bestArea then
        best, bestArea = l, a
      end
    end
  end
  return best
end

local function skippedLabel(label)
  if label == 'more options' or label == 'more actions'
    or label == 'message options' or label == 'options' then
    return true
  end
  if label:sub(1, 12) == 'more options' or label:sub(1, 12) == 'more actions' then
    return true
  end
  return false
end

local function genericLastMessage()
  local scope = findConversation()
  if scope == nil then
    scope = sf.screen.root()
  end
  if scope == nil then
    return nil
  end
  local items = scope:findAll({ focusable = true }, 200)
  local cands = {}
  local maxBottom = -1
  for _, it in ipairs(items) do
    local t = it.text or it.contentDescription
    if t ~= nil and t ~= '' and it.bounds ~= nil then
      local label = string.lower((t:gsub('^%s+', ''):gsub('%s+$', '')))
      if not skippedLabel(label) then
        cands[#cands + 1] = { item = it, len = #t, bottom = it.bounds.bottom }
        if it.bounds.bottom > maxBottom then
          maxBottom = it.bounds.bottom
        end
      end
    end
  end
  local best, bestLen, bestBottom = nil, -1, -1
  for _, c in ipairs(cands) do
    if c.bottom >= maxBottom - 300 then
      if c.len > bestLen or (c.len == bestLen and c.bottom > bestBottom) then
        best, bestLen, bestBottom = c.item, c.len, c.bottom
      end
    end
  end
  return best
end

-- ---------- Muse (com.facebook.aura): real ids from the screen tree ----------

local function lowestOf(items)
  local best, bestBottom = nil, -1
  for _, it in ipairs(items) do
    if it.bounds ~= nil and it.bounds.bottom > bestBottom then
      best, bestBottom = it, it.bounds.bottom
    end
  end
  return best
end

local function museLastMessage()
  local cands = {}
  local latest = lowestOf(sf.screen.findAll({ id = 'hatch-message-assistant-latest' }, 10))
  if latest ~= nil then
    cands[#cands + 1] = latest
  end
  local user = lowestOf(sf.screen.findAll({ id = 'hatch-message-user' }, 50))
  if user ~= nil then
    cands[#cands + 1] = user
  end
  local asst = lowestOf(sf.screen.findAll({ id = 'hatch-message-assistant' }, 50))
  if asst ~= nil then
    cands[#cands + 1] = asst
  end
  return lowestOf(cands)
end

local function museTextTarget(container)
  if container == nil then
    return nil
  end
  local tvs = container:findAll({ className = 'TextView' }, 60)
  for _, tv in ipairs(tvs) do
    if tv.text ~= nil and tv.text ~= '' then
      return tv
    end
  end
  return container
end

-- ---------- Google Messages paired web view (Ditto) ----------

local function dittoLastMessage(listRight)
  local tvs = sf.screen.findAll({ className = 'TextView' }, 200)
  local best, bestBottom = nil, -1
  for _, tv in ipairs(tvs) do
    local t = tv.text
    if t ~= nil and #t >= 2 and tv.bounds ~= nil then
      local low = string.lower(t)
      local skip = false
      if t:match('^%d+:%d%d') then
        skip = true
      elseif low:sub(1, 12) == 'texting with' then
        skip = true
      elseif low == 'conversations list' then
        skip = true
      end
      if listRight ~= nil and tv.bounds.left < listRight - 5 then
        skip = true
      end
      if not skip and tv.bounds.bottom > bestBottom then
        best, bestBottom = tv, tv.bounds.bottom
      end
    end
  end
  if best == nil then
    return nil
  end
  return climbToFocusable(best, 8)
end

local function dittoJump()
  local edit = findEditField()
  local list = sf.screen.find({ className = 'ListView' })
  local listRow = nil
  local listRight = nil
  if list ~= nil then
    if list.bounds ~= nil then
      listRight = list.bounds.right
    end
    listRow = list:find({ clickable = true, focusable = true })
  end
  local foc = sf.screen.focused()

  -- No conversation selected (screen tree, November 11, 2026): there is
  -- no message box and no message pane on this screen, only the
  -- conversation list. J plops you straight into the list, on the first
  -- conversation, instead of hunting for a message that is not there.
  if edit == nil then
    if listRow ~= nil then
      listRow:focus()
    elseif list ~= nil then
      list:focus()
    else
      sf.speak('No conversation list found')
    end
    return
  end

  if edit ~= nil and foc ~= nil and isInside(foc, edit) then
    if listRow ~= nil then
      listRow:focus()
    elseif list ~= nil then
      list:focus()
    else
      sf.speak('No conversation list found')
    end
    return
  end

  if list ~= nil and foc ~= nil and isInside(foc, list) then
    local msg = dittoLastMessage(listRight)
    if msg ~= nil then
      msg:focus()
    else
      sf.speak('No message found')
    end
    return
  end

  if edit ~= nil then
    focusEdit(edit)
  else
    sf.speak('No message box found')
  end
end

local function dittoSend()
  local btn = nil
  for _, label in ipairs({ 'Send SMS', 'Send RCS', 'Send MMS' }) do
    btn = sf.screen.find({ contentDescription = label })
    if btn ~= nil then
      break
    end
  end
  if btn == nil then
    -- Current labels (screen tree, November 8, 2026): the send
    -- button is named for what it sends, for example "Send
    -- end-to-end encrypted RCS message". Accept only a Button
    -- whose description STARTS with "Send " and names a
    -- message kind — a similarly placed button with another
    -- name is still refused.
    local cands = sf.screen.findAll({ className = 'Button' }, 50)
    for _, b in ipairs(cands) do
      local d = b.contentDescription or ''
      if d:sub(1, 5) == 'Send ' then
        local low = string.lower(d)
        if string.find(low, 'rcs', 1, true) ~= nil
          or string.find(low, 'sms', 1, true) ~= nil
          or string.find(low, 'mms', 1, true) ~= nil
          or string.find(low, 'message', 1, true) ~= nil then
          btn = b
          break
        end
      end
    end
  end
  if btn ~= nil then
    if btn.enabled then
      btn:click()
    else
      sf.speak('Nothing to send')
    end
    return
  end
  local edit = findEditField()
  if edit ~= nil then
    edit:perform('imeEnter')
  else
    sf.speak('No send button found')
  end
end

local function isDitto(pkg, activity)
  if pkg ~= 'com.google.android.apps.messaging' then
    return false
  end
  if string.find(string.lower(activity), 'ditto', 1, true) ~= nil then
    return true
  end
  -- November 8, 2026: the paired web view now lives inside
  -- MainActivity, so the activity name no longer gives it
  -- away. Recognise the screen by its Ditto fragment instead.
  return sf.screen.find(
    { id = 'com.google.android.apps.messaging:id/ditto_web_fragment_ref' }) ~= nil
end

-- ---------- Facebook Messenger (com.facebook.orca) ----------

local function messengerLastMessage()
  local items = sf.screen.findAll({ textContains = 'double tap to see sent' }, 100)
  local best, bestBottom = nil, -1
  for _, it in ipairs(items) do
    if it.bounds ~= nil and it.bounds.bottom > bestBottom then
      best, bestBottom = it, it.bounds.bottom
    end
  end
  if best == nil then
    return nil
  end
  return climbToFocusable(best, 6)
end

local function messengerThreadJump()
  local edit = findEditField()
  if edit == nil then
    return false
  end
  local foc = sf.screen.focused()
  if foc ~= nil and isInside(foc, edit) then
    local msg = messengerLastMessage()
    if msg ~= nil then
      msg:focus()
    else
      sf.speak('No message found')
    end
  else
    focusEdit(edit)
  end
  return true
end

local function messengerHomeJump()
  local lists = sf.screen.findAll({ className = 'RecyclerView' }, 10)
  local outer = nil
  for _, l in ipairs(lists) do
    local node = l:parent()
    local nested = false
    for _ = 1, 10 do
      if node == nil then
        break
      end
      if classContains(node, 'RecyclerView') then
        nested = true
        break
      end
      node = node:parent()
    end
    if not nested then
      outer = l
      break
    end
  end
  if outer == nil then
    return false
  end
  local kids = outer:children() or {}
  for _, k in ipairs(kids) do
    if k.role == 'button' then
      local d = k.contentDescription or ''
      if #d >= 10 then
        k:focus()
        return true
      end
    end
  end
  outer:focus()
  return true
end

local function messengerSend()
  local btn = sf.screen.find({ contentDescription = 'Send' })
  if btn ~= nil then
    btn:click()
    return true
  end
  local like = sf.screen.find({ contentDescription = 'Send 👍' })
  if like ~= nil then
    sf.speak('Nothing to send')
    return true
  end
  local edit = findEditField()
  if edit ~= nil then
    edit:perform('imeEnter')
    return true
  end
  return false
end

-- ---------- Gemini (Google app package, "robin" surfaces) ----------

local function geminiEdit()
  local ids = {
    'com.google.android.googlequicksearchbox:id/assistant_robin_input_collapsed_text_half_sheet',
    'assistant_robin_input_collapsed_text_half_sheet',
    'com.google.android.googlequicksearchbox:id/assistant_robin_input_text_half_sheet',
    'assistant_robin_input_text_half_sheet',
    'com.google.android.googlequicksearchbox:id/assistant_robin_input_expanded_text_half_sheet',
    'assistant_robin_input_expanded_text_half_sheet',
  }
  for _, id in ipairs(ids) do
    local found = sf.screen.findAll({ id = id }, 5)
    if found ~= nil and #found > 0 then
      return found[1]
    end
  end
  local edits = sf.screen.findAll({ editable = true }, 20)
  for _, e in ipairs(edits) do
    if e.text == 'Ask Gemini' then
      return e
    end
  end
  return findEditField()
end

local function geminiScope()
  local pagers = sf.screen.findAll(
    { id = 'com.google.android.googlequicksearchbox:id/assistant_robin_nav_pager' }, 5)
  if pagers ~= nil and #pagers > 0 then
    return pagers[1]
  end
  local vps = sf.screen.findAll({ className = 'ViewPager' }, 5)
  if vps ~= nil and #vps > 0 then
    return vps[1]
  end
  return sf.screen.root()
end

local function geminiLastMessage()
  -- Real message ids from a conversation tree: assistant replies live in
  -- assistant_robin_text, user messages in assistant_robin_user_message_text.
  local cands = {}
  local ids = {
    'com.google.android.googlequicksearchbox:id/assistant_robin_text',
    'assistant_robin_text',
    'com.google.android.googlequicksearchbox:id/assistant_robin_user_message_text',
    'assistant_robin_user_message_text',
  }
  for _, id in ipairs(ids) do
    local items = sf.screen.findAll({ id = id }, 100) or {}
    for _, it in ipairs(items) do
      cands[#cands + 1] = it
    end
  end
  local byId = lowestOf(cands)
  if byId ~= nil then
    return byId
  end
  -- Fallback for other Gemini layouts: lowest long text in the chat pane,
  -- but never the "Gemini is AI and can make mistakes." boundary note,
  -- which sits below the last reply and is not a message.
  local scope = geminiScope()
  if scope == nil then
    return nil
  end
  local headings = scope:findAll({ heading = true }, 30) or {}
  local tvs = scope:findAll({ className = 'TextView' }, 200) or {}
  local best, bestBottom = nil, -1
  for _, tv in ipairs(tvs) do
    local t = tv.text
    if t ~= nil and #t >= 20 and tv.bounds ~= nil then
      if string.find(t, 'can make mistakes', 1, true) == nil then
        local isHeading = false
        for _, h in ipairs(headings) do
          if h == tv then
            isHeading = true
            break
          end
        end
        if not isHeading and tv.bounds.bottom > bestBottom then
          best, bestBottom = tv, tv.bounds.bottom
        end
      end
    end
  end
  return best
end

local function geminiJump()
  local edit = geminiEdit()
  if edit == nil then
    sf.speak('No message box found')
    return
  end
  local foc = sf.screen.focused()
  if foc ~= nil and isInside(foc, edit) then
    local msg = geminiLastMessage()
    if msg ~= nil then
      msg:focus()
    else
      sf.speak('No message yet')
    end
  else
    focusEdit(edit)
  end
end

local function geminiSend()
  local edit = geminiEdit()
  if edit ~= nil then
    local t = edit.text or ''
    if t == '' or t == 'Ask Gemini' then
      sf.speak('Nothing to send')
      return true
    end
  end
  -- The typed-draft tree names the send button outright: a ComposeView with
  -- id assistant_robin_input_send_button_compose, holding a wrapper labelled
  -- "Send" around the real Button node. Go straight to it by id, walk down
  -- to the actual button, focus it, then click it.
  local conts = sf.screen.findAll(
    { id = 'com.google.android.googlequicksearchbox:id/assistant_robin_input_send_button_compose' }, 5) or {}
  if #conts == 0 then
    conts = sf.screen.findAll({ id = 'assistant_robin_input_send_button_compose' }, 5) or {}
  end
  if #conts > 0 then
    local cont = conts[1]
    local function walk(node, pred, depth)
      if node == nil or depth > 7 then
        return nil
      end
      if pred(node) then
        return node
      end
      local kids = node:children() or {}
      for _, k in ipairs(kids) do
        local hit = walk(k, pred, depth + 1)
        if hit ~= nil then
          return hit
        end
      end
      return nil
    end
    local target = walk(cont, function(n) return n.role == 'button' end, 0)
    if target == nil then
      target = walk(cont, function(n) return n.contentDescription == 'Send' end, 0)
    end
    if target == nil then
      target = walk(cont, function(n) return n.clickable end, 0)
    end
    if target == nil then
      target = cont
    end
    target:focus()
    target:click()
    return true
  end
  -- Fallback for other Gemini layouts: hunt inside the input container only,
  -- for any clickable whose label mentions send ("Send", "Send message", ...).
  local scope = nil
  local containers = sf.screen.findAll(
    { id = 'com.google.android.googlequicksearchbox:id/assistant_robin_chat_input_container' }, 5) or {}
  if #containers > 0 then
    scope = containers[1]
  else
    scope = sf.screen.root()
  end
  if scope ~= nil then
    local items = scope:findAll({ clickable = true }, 100) or {}
    local best, bestBottom, bestRight = nil, -1, -1
    for _, b in ipairs(items) do
      if not b.editable and b.bounds ~= nil then
        local label = string.lower((b.contentDescription or '') .. ' ' .. (b.text or ''))
        if string.find(label, 'send', 1, true) ~= nil then
          if b.bounds.bottom > bestBottom
            or (b.bounds.bottom == bestBottom and b.bounds.right > bestRight) then
            best, bestBottom, bestRight = b, b.bounds.bottom, b.bounds.right
          end
        end
      end
    end
    if best ~= nil then
      if best.enabled == false then
        sf.speak('Nothing to send')
      else
        best:click()
      end
      return true
    end
  end
  if edit ~= nil then
    -- Draft present but no send button found: say so out loud (diagnostic),
    -- and still try the IME Enter action as a last resort.
    sf.speak('No send button found')
    edit:perform('imeEnter')
    return true
  end
  return false
end

local function isGemini(pkg)
  return pkg == 'com.google.android.googlequicksearchbox'
    or pkg == 'com.google.android.apps.bard'
end

-- ---------- YouTube: jump straight to the first video ----------

local function youtubeJump()
  local lists = sf.screen.findAll({ id = 'com.google.android.youtube:id/results' }, 5) or {}
  if #lists == 0 then
    lists = sf.screen.findAll({ id = 'results' }, 5) or {}
  end
  if #lists == 0 then
    sf.speak('No video list found')
    return
  end
  local list = lists[1]
  -- A video row's main button carries a long description ending in
  -- "play video" (title, duration, channel, views, age). Its neighbours do
  -- not: "Action menu for ...", "Go to channel ...", "Tap to watch ...",
  -- and inserted promo cards never say "play video". Topmost match wins.
  local items = list:findAll({ clickable = true }, 100) or {}
  local best, bestTop = nil, nil
  for _, it in ipairs(items) do
    local d = it.contentDescription or ''
    local low = string.lower(d)
    if #d >= 30 and string.find(low, 'play video', 1, true) ~= nil
      and low:sub(1, 11) ~= 'action menu'
      and string.find(low, 'go to channel', 1, true) == nil
      and string.find(low, 'tap to watch', 1, true) == nil
      and it.bounds ~= nil then
      if bestTop == nil or it.bounds.top < bestTop then
        best, bestTop = it, it.bounds.top
      end
    end
  end
  if best ~= nil then
    best:focus()
    return
  end
  local kids = list:children() or {}
  for _, k in ipairs(kids) do
    if k.focusable then
      k:focus()
      return
    end
  end
  sf.speak('No video found')
end

-- ---------- Telegram (org.telegram.messenger) ----------
-- Screen trees, November 11, 2026: Telegram stacks several screens in one
-- window (chat lists under topics under the open conversation), so a list
-- is told by its rows, never by position: chat rows carry the "Chat
-- Preview" action, message rows carry "Message options", and topic rows'
-- descriptions start with "Topic.". With text typed, the input row's send
-- node is a View described exactly "Send"; with an empty box the same spot
-- is "Record voice message" instead, and there is no Send node at all.
-- Plain Up and Down are bound to the step commands only while Telegram is
-- in front (see the app enter/leave hooks at the bottom), so the arrows
-- step inside the current list and can never wander out of it; everywhere
-- else SandFly keeps the arrows. SandFly plus N and P step too.
-- Chat list screen (tree, November 12, 2026): the chat list and a
-- stories strip are two separate RecyclerViews, told apart by rows as
-- always, and the screen carries its own Search Chats edit field. That
-- field is NOT the message box: the box is identified strictly, by a
-- hint or description of exactly "Message" (see tgMessageBox).

local function tgHasAction(item, label)
  local acts = item.actions
  if acts == nil then
    return false
  end
  for _, a in ipairs(acts) do
    if type(a) == 'table' then
      if a.label == label then
        return true
      end
    elseif a == label then
      return true
    end
  end
  return false
end

-- The message box, strictly: an edit field whose hint or description
-- is exactly "Message" (typed tree, November 11, 2026). Nothing else
-- counts. v3.1 used the shared any-edit-field finder here, so on the
-- chat list screen the Search Chats field impersonated the box: J
-- landed on Search, stepping fell back to J and landed there again,
-- and a typed search query counted as a draft to send (field report,
-- November 12, 2026).
local function tgMessageBox()
  local edits = sf.screen.findAll({ editable = true }, 20)
  for _, e in ipairs(edits) do
    if e.hint == 'Message' or e.contentDescription == 'Message' then
      return e
    end
  end
  return nil
end

local function tgKindOf(list)
  local kids = list:children() or {}
  for _, k in ipairs(kids) do
    if tgHasAction(k, 'Message options') then
      return 'messages', kids
    end
  end
  for _, k in ipairs(kids) do
    local d = k.contentDescription or ''
    if d:sub(1, 6) == 'Topic.' then
      return 'topics', kids
    end
  end
  for _, k in ipairs(kids) do
    if tgHasAction(k, 'Chat Preview') then
      return 'chats', kids
    end
  end
  return nil, kids
end

local function tgItems(kind, kids)
  local items = {}
  for _, k in ipairs(kids) do
    if kind == 'messages' then
      if tgHasAction(k, 'Message options') then
        items[#items + 1] = k
      end
    elseif kind == 'topics' then
      local d = k.contentDescription or ''
      if d:sub(1, 6) == 'Topic.' then
        items[#items + 1] = k
      end
    elseif kind == 'chats' then
      if tgHasAction(k, 'Chat Preview') then
        items[#items + 1] = k
      end
    elseif k.focusable then
      items[#items + 1] = k
    end
  end
  return items
end

local function tgPick(kind, foc)
  local lists = sf.screen.findAll({ className = 'RecyclerView' }, 20) or {}
  local last = nil
  for _, l in ipairs(lists) do
    local k, kids = tgKindOf(l)
    if k == kind then
      if foc ~= nil and isInside(foc, l) then
        return { list = l, kind = k, kids = kids }
      end
      last = { list = l, kind = k, kids = kids }
    end
  end
  return last
end

local function tgEntryForFocus(foc)
  if foc == nil then
    return nil
  end
  local lists = sf.screen.findAll({ className = 'RecyclerView' }, 20) or {}
  for _, l in ipairs(lists) do
    if isInside(foc, l) then
      local k, kids = tgKindOf(l)
      return { list = l, kind = k, kids = kids }
    end
  end
  return nil
end

local function tgDefaultItem(entry)
  local items = tgItems(entry.kind, entry.kids)
  if #items == 0 then
    return nil
  end
  if entry.kind == 'messages' then
    return items[#items]
  end
  return items[1]
end

local function tgJump()
  local edit = tgMessageBox()
  local foc = sf.screen.focused()
  if edit ~= nil then
    if foc ~= nil and isInside(foc, edit) then
      local entry = tgPick('messages', foc)
      local item = nil
      if entry ~= nil then
        item = tgDefaultItem(entry)
      end
      if item ~= nil then
        item:focus()
      else
        sf.speak('No messages found')
      end
    else
      focusEdit(edit)
    end
    return
  end
  local entry = tgEntryForFocus(foc)
  if entry == nil then
    entry = tgPick('topics', foc)
  end
  if entry == nil then
    entry = tgPick('chats', foc)
  end
  if entry ~= nil then
    local item = tgDefaultItem(entry)
    if item ~= nil then
      item:focus()
    else
      entry.list:focus()
    end
    return
  end
  sf.speak('No list found')
end

local function tgStep(dir)
  local foc = sf.screen.focused()
  if foc == nil then
    tgJump()
    return
  end
  local node = foc
  local list = nil
  for _ = 1, 10 do
    if node == nil then
      break
    end
    if classContains(node, 'RecyclerView') then
      list = node
      break
    end
    node = node:parent()
  end
  if list == nil then
    tgJump()
    return
  end
  local kind, kids = tgKindOf(list)
  local items = tgItems(kind, kids)
  if #items == 0 then
    tgJump()
    return
  end
  local idx = nil
  for i, it in ipairs(items) do
    if foc == it or isInside(foc, it) then
      idx = i
      break
    end
  end
  if idx == nil then
    if kind == 'messages' then
      items[#items]:focus()
    else
      items[1]:focus()
    end
    return
  end
  local word = 'item'
  if kind == 'messages' then
    word = 'message'
  elseif kind == 'topics' then
    word = 'topic'
  elseif kind == 'chats' then
    word = 'chat'
  end
  local nxt = idx + dir
  if nxt < 1 then
    sf.speak('First ' .. word)
    return
  end
  if nxt > #items then
    sf.speak('Last ' .. word)
    return
  end
  items[nxt]:focus()
end

local function tgSend()
  local edit = tgMessageBox()
  if edit == nil then
    sf.speak('Not in a chat')
    return
  end
  local t = edit.text or ''
  if t == '' then
    sf.speak('Nothing to send')
    return
  end
  local btn = sf.screen.find({ contentDescription = 'Send' })
  if btn ~= nil then
    btn:click()
  else
    sf.speak('No send button found')
  end
end

-- ---------- commands ----------

sf.onCommand('jump', function(event)
  local pkg, activity = currentApp()

  if pkg == 'com.android.chrome' then
    chromeFocusContent()
    return
  end

  if isDitto(pkg, activity) then
    dittoJump()
    return
  end

  if isGemini(pkg) then
    geminiJump()
    return
  end

  if pkg == 'org.telegram.messenger' then
    tgJump()
    return
  end

  if pkg == 'com.google.android.youtube' then
    youtubeJump()
    return
  end

  if pkg == 'com.facebook.aura' then
    local edit = sf.screen.find('hatch-message-input')
    if edit == nil then
      edit = findEditField()
    end
    if edit == nil then
      sf.speak('No message box found')
      return
    end
    local foc = sf.screen.focused()
    if foc ~= nil and foc == edit then
      local target = museTextTarget(museLastMessage())
      if target ~= nil then
        target:focus()
      else
        sf.speak('No message found')
      end
    else
      focusEdit(edit)
    end
    return
  end

  if pkg == 'com.facebook.orca' then
    if messengerThreadJump() then
      return
    end
    if messengerHomeJump() then
      return
    end
  end

  local edit = findEditField()
  if edit == nil then
    sf.speak('No message box found')
    return
  end
  local foc = sf.screen.focused()
  if foc ~= nil and foc == edit then
    local msg = genericLastMessage()
    if msg ~= nil then
      msg:focus()
    else
      sf.speak('No message found')
    end
  else
    focusEdit(edit)
  end
end)

local function labelHas(item, word)
  local t = string.lower((item.text or '') .. ' ' .. (item.contentDescription or ''))
  return string.find(t, word, 1, true) ~= nil
end

sf.onCommand('send', function(event)
  local pkg, activity = currentApp()

  if pkg == 'com.android.chrome' then
    return
  end

  if pkg == 'com.google.android.youtube' then
    return
  end

  if pkg == 'org.telegram.messenger' then
    tgSend()
    return
  end

  if isDitto(pkg, activity) then
    dittoSend()
    return
  end

  if pkg == 'com.facebook.orca' then
    if messengerSend() then
      return
    end
  end

  if isGemini(pkg) then
    if geminiSend() then
      return
    end
  end

  local buttons = sf.screen.findAll({ clickable = true }, 200)
  local best, bestBottom = nil, -1
  for _, b in ipairs(buttons) do
    if not b.editable and labelHas(b, 'send') and b.bounds ~= nil
      and b.bounds.bottom > bestBottom then
      best, bestBottom = b, b.bounds.bottom
    end
  end
  if best ~= nil then
    best:click()
    return
  end
  local edit = findEditField()
  if edit ~= nil then
    edit:perform('imeEnter')
  else
    sf.speak('No send button found')
  end
end)

sf.onCommand('tgNext', function(event)
  local pkg = currentApp()
  if pkg ~= 'org.telegram.messenger' then
    return
  end
  tgStep(1)
end)

sf.onCommand('tgPrev', function(event)
  local pkg = currentApp()
  if pkg ~= 'org.telegram.messenger' then
    return
  end
  tgStep(-1)
end)

-- Plain Up and Down belong to SandFly everywhere else. Bind them to the
-- Telegram step commands only while Telegram is in front and unbind them
-- on the way out, so no other app ever has its arrows taken.
local tgArrowsBound = false

sf.onAppEnter(function(event)
  if event ~= nil and event.package == 'org.telegram.messenger'
    and not tgArrowsBound then
    sf.bind('tgNext', { keys = 'down' })
    sf.bind('tgPrev', { keys = 'up' })
    tgArrowsBound = true
  end
end)

sf.onAppLeave(function(event)
  if tgArrowsBound then
    sf.unbind('tgNext', { keys = 'down' })
    sf.unbind('tgPrev', { keys = 'up' })
    tgArrowsBound = false
  end
end)
