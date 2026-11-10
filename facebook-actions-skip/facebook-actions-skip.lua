-- Facebook Actions and Skip, for SandFly (script API v2+).
--
-- Two jobs in the Facebook app (com.facebook.katana):
--
-- 1. Post actions, iOS VoiceOver style. On a feed post, swipe down to
--    cycle through the actions, swipe up to cycle back; each action is
--    spoken as you land on it. Double-tap then runs the selected action.
--    If you never swiped, double-tap behaves exactly as it always did --
--    the command hands the gesture back untouched.
--    A feed post only exposes two actions of its own ("Open full post"
--    and "Open actions menu"); the real actions live in the long-press
--    menu: Like, React, Comment, Share, See more options for this post,
--    Get detailed image descriptions. So on a post, the cycle runs
--    through THAT menu instead, and double-tap opens the menu and taps
--    your pick for you -- the long-press, without the long-press.
--    The menu is stateful: once you react, "Like" becomes "Remove Like
--    reaction" and "React" becomes "Change reaction". The script tracks
--    what it did per post and cycles the matching labels, and when it
--    opens the menu it reads the REAL buttons before tapping -- so if
--    the state changed some other way, it says so ("Already reacted",
--    "Not reacted") instead of tapping the wrong thing, and learns the
--    true state for next time.
--
-- 2. Section skip. SandFly+J, or a two-finger swipe right, jumps out of
--    a feed section -- the story tray, a reels shelf, People You May
--    Know -- to the first real post below it. Escape only: pressed on a
--    normal post, it does nothing. Sections are recognized by shape
--    (a feed row that contains a sideways list inside it), so renamed
--    or new sections are covered too. Normal swiping still walks
--    through the sections for anyone who wants them.

local manifest = {
  id = 'facebook-actions-skip',
  name = 'Facebook Actions and Skip',
  version = '1.6',
  author = 'Atlas',
  description = 'Swipe up/down on a post to cycle its actions, double-tap to run the selected one. SandFly+J or two-finger swipe right skips feed sections (stories, reels, People You May Know) to the next post.',
  minApiVersion = 2,
  testedApiVersion = 3,
  apps = { 'com.facebook.katana' },
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'next_action', title = 'Next action', gesture = 'swipeDown' },
    { id = 'prev_action', title = 'Previous action', gesture = 'swipeUp' },
    { id = 'run_action', title = 'Run selected action', gesture = 'doubleTap' },
    { id = 'skip_section', title = 'Skip section', gesture = { 'twoFingerSwipeRight', 'threeFingerSwipeRight' }, keys = 'sf+j' },
  },
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function endsWith(s, tail)
  if s == nil then return false end
  return tail == '' or s:sub(-#tail) == tail
end

local function containsText(node)
  local t = node.text
  if t ~= nil and t ~= '' then return true end
  local d = node.contentDescription
  return d ~= nil and d ~= ''
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

-- ---------------------------------------------------------------------------
-- Part 1: action cycling + run on double-tap
-- ---------------------------------------------------------------------------

local selNode = nil   -- the item the selection belongs to
local selIdx = nil    -- index into its usable actions
local selLabel = nil  -- label of the selected action
local selId = nil     -- id of the selected action (fallback for perform)
local selKind = nil   -- 'menu' (a post's long-press menu) or 'action'

local function clearSelection()
  selNode, selIdx, selLabel, selId, selKind = nil, nil, nil, nil, nil
end

-- Reaction state per post, learned from what this script did and from
-- what it reads in opened menus. Keys are post descriptions; values are
-- 'like', 'other' (reacted, but not a plain Like), or nil (no reaction).
-- Kept in memory only: it is a session convenience, and the run-time
-- menu check below corrects it whenever it is wrong.
local postState = {}

local function postKey(node)
  local d = node.contentDescription
  if d ~= nil and d ~= '' then return d end
  return node.text or ''
end

-- The post's long-press menu entries, in the menu's own order, adjusted
-- for the post's reaction state. For a non-Like reaction the remove
-- entry is spoken generically ("Remove reaction"); at run time any
-- "Remove ... reaction" button satisfies it.
local function postMenuItems(state)
  local first, second
  if state == 'like' then
    first, second = 'Remove Like reaction', 'Change reaction'
  elseif state == 'other' then
    first, second = 'Remove reaction', 'Change reaction'
  else
    first, second = 'Like', 'React'
  end
  return {
    first,
    second,
    'Comment',
    'Share',
    'See more options for this post',
    'Get detailed image descriptions',
  }
end

-- The node's custom actions with a real label, in the node's own order.
local function usableActions(node)
  local out = {}
  local acts = node.actions
  if acts == nil then return out end
  for _, a in ipairs(acts) do
    local label = nil
    local id = nil
    if type(a) == 'table' then
      label = a.label
      id = a.id
    elseif type(a) == 'string' then
      label = a
    end
    if label ~= nil and label ~= '' then
      out[#out + 1] = { label = label, id = id }
    end
  end
  return out
end

-- Does this item expose the post's "Open actions menu" action? Then it IS
-- a feed post, and cycling runs through the long-press menu instead.
local function isPost(node)
  local acts = node.actions
  if acts == nil then return false end
  for _, a in ipairs(acts) do
    if type(a) == 'table' and a.label == 'Open actions menu' then
      return true
    end
    if type(a) == 'string' and a == 'Open actions menu' then
      return true
    end
  end
  return false
end

local function cycle(dir, node)
  if node == nil then return false end
  local items = nil
  local kind = nil
  if isPost(node) then
    items = {}
    for _, label in ipairs(postMenuItems(postState[postKey(node)])) do
      items[#items + 1] = { label = label }
    end
    kind = 'menu'
  else
    items = usableActions(node)
    kind = 'action'
  end
  if #items == 0 then return false end  -- not ours: hand the swipe back
  if selNode ~= node or selIdx == nil or selKind ~= kind then
    selIdx = (dir > 0) and 1 or #items
  else
    selIdx = selIdx + dir
    if selIdx > #items then selIdx = 1 end
    if selIdx < 1 then selIdx = #items end
  end
  selNode = node
  selKind = kind
  selLabel = items[selIdx].label
  selId = items[selIdx].id
  sf.speak(selLabel)
  return true
end

sf.onCommand('next_action', function(event)
  local node = event.node or sf.screen.focused()
  if not cycle(1, node) then return false end
end)

sf.onCommand('prev_action', function(event)
  local node = event.node or sf.screen.focused()
  if not cycle(-1, node) then return false end
end)

-- Open the post's menu, read its REAL buttons, and tap the pick --
-- resolving state differences instead of blindly tapping a stale label.
local function runMenuPick(post, label)
  local key = postKey(post)
  local opened = false
  local ran, res = pcall(function() return post:perform('Open actions menu') end)
  if ran and res then opened = true end
  if not opened then
    sf.speak('Could not open the menu')
    return
  end
  -- "Comment" is in the menu in every state: it is the menu-ready signal.
  local ready = sf.screen.waitFor({ contentDescription = 'Comment', className = 'Button' }, 3000)
  if ready == nil then
    sf.speak('Menu did not open')
    return
  end
  local buttons = sf.screen.findAll({ className = 'Button' }, 60) or {}
  local byLabel = {}
  local removeBtn, removeLabel = nil, nil
  for _, b in ipairs(buttons) do
    local d = b.contentDescription
    if d ~= nil and d ~= '' then
      if byLabel[d] == nil then byLabel[d] = b end
      if d:sub(1, 7) == 'Remove ' and d:sub(-9) == ' reaction' then
        removeBtn, removeLabel = b, d
      end
    end
  end
  local function closeMenu()
    local c = byLabel['Close']
    if c ~= nil then c:click() end
  end
  local function learnFromRemove()
    if removeLabel == 'Remove Like reaction' then
      postState[key] = 'like'
    else
      postState[key] = 'other'
    end
  end

  if label == 'Like' then
    if byLabel['Like'] ~= nil then
      byLabel['Like']:click()
      postState[key] = 'like'
      sf.speak('Liked')
    elseif removeBtn ~= nil then
      learnFromRemove()
      closeMenu()
      sf.speak('Already reacted')
    else
      sf.speak('Not in this menu')
    end
    return
  end

  if label == 'Remove Like reaction' or label == 'Remove reaction' then
    if removeBtn ~= nil then
      removeBtn:click()
      postState[key] = nil
      sf.speak('Reaction removed')
    elseif byLabel['Like'] ~= nil then
      postState[key] = nil
      closeMenu()
      sf.speak('Not reacted')
    else
      sf.speak('Not in this menu')
    end
    return
  end

  if label == 'React' or label == 'Change reaction' then
    local b = byLabel['React'] or byLabel['Change reaction']
    if b ~= nil then
      b:click()
      -- The picker is open now; whatever he picks there is a reaction.
      -- If he backs out, the next menu check corrects the record.
      if postState[key] == nil then postState[key] = 'other' end
      if label == 'Change reaction' then postState[key] = 'other' end
    else
      sf.speak('Not in this menu')
    end
    return
  end

  local b = byLabel[label]
  if b ~= nil then
    b:click()
  else
    -- Left open on screen, so he can pick by hand.
    sf.speak('Not in this menu')
  end
end

sf.onCommand('run_action', function(event)
  local node = event.node or sf.screen.focused()
  if selNode == nil or selLabel == nil or node == nil or node ~= selNode then
    return false  -- nothing selected here: double-tap does its normal job
  end
  local fresh = node:refresh()
  if fresh == nil then
    clearSelection()
    return false
  end
  local label, id, kind = selLabel, selId, selKind
  clearSelection()
  if kind == 'menu' then
    runMenuPick(fresh, label)
    return true
  end
  local ok = false
  local ran, res = pcall(function() return fresh:perform(label) end)
  if ran and res then ok = true end
  if not ok and id ~= nil then
    local ran2, res2 = pcall(function() return fresh:perform(id) end)
    if ran2 and res2 then ok = true end
  end
  if not ok then sf.speak('Action did not run') end
  return true
end)

-- Moving focus to a different item forgets the selection.
sf.onFocus(function(item)
  if selNode ~= nil and item ~= nil and item ~= selNode then
    clearSelection()
  end
end)

-- ---------------------------------------------------------------------------
-- Part 2: section skip
-- ---------------------------------------------------------------------------

-- The feed list: the RecyclerView that is not itself inside another list.
local function feedList()
  local lists = sf.screen.findAll({ className = 'RecyclerView' }, 50) or {}
  for _, l in ipairs(lists) do
    local nested = false
    local p = l:parent()
    local guard = 0
    while p ~= nil and guard < 40 do
      if endsWith(p.className or '', 'RecyclerView') then
        nested = true
        break
      end
      p = p:parent()
      guard = guard + 1
    end
    if not nested then return l end
  end
  return nil
end

-- Does this node contain a list anywhere inside it? (trays and shelves do;
-- posts and the composer block do not)
local function containsList(node, depth)
  if depth > 6 then return false end
  local kids = node:children() or {}
  for _, k in ipairs(kids) do
    local cn = k.className or ''
    if endsWith(cn, 'RecyclerView') or endsWith(cn, 'ListView') then
      return true
    end
    if containsList(k, depth + 1) then return true end
  end
  return false
end

local SECTION_WORDS = { 'story tray', 'people you may know', 'reels' }

local function isSection(child)
  if containsList(child, 0) then return true end
  local d = child.contentDescription
  if d ~= nil then
    local lower = d:lower()
    for _, w in ipairs(SECTION_WORDS) do
      if lower:find(w, 1, true) then return true end
    end
  end
  return false
end

-- First focusable, text-bearing item inside a feed row (the post itself).
local function postTarget(node, depth)
  if depth > 6 then return nil end
  if node.focusable and containsText(node) then return node end
  local kids = node:children() or {}
  for _, k in ipairs(kids) do
    local t = postTarget(k, depth + 1)
    if t ~= nil then return t end
  end
  return nil
end

local function focusPostBelow(kids, fromIdx)
  for i = fromIdx, #kids do
    local k = kids[i]
    if not isSection(k) then
      local t = postTarget(k, 0)
      if t ~= nil then
        t:focus()
        return true
      end
    end
  end
  return false
end

-- Signature scan: a real post is any focusable item carrying the
-- "Open actions menu" action. Find the topmost visible one at or below
-- minTop (a y position in the SAME snapshot, so the comparison is
-- valid). Used as a cross-check when the row walk comes up empty.
local function scanPostBelow(minTop)
  local items = sf.screen.findAll({ focusable = true }, 200) or {}
  local best, bestTop = nil, nil
  for _, p in ipairs(items) do
    if isPost(p) and p.bounds ~= nil and p.bounds.top ~= nil then
      local top = p.bounds.top
      local bottom = p.bounds.bottom or top
      if bottom > 0 and (minTop == nil or top >= minTop - 4) then
        if bestTop == nil or top < bestTop then
          best, bestTop = p, top
        end
      end
    end
  end
  if best ~= nil then
    best:focus()
    return true
  end
  return false
end

-- A SMALL real finger scroll: about a sixth of the screen. The skip
-- creeps with these, checking after every step, so it stops at the
-- first post under the section instead of leaping a page past it.
-- (A list's own scrollForward jumps a full page, and stacking the two
-- jumped nearly two -- that was v1.4's overshoot, and it is gone.)
local function touchScrollSmall()
  local root = sf.screen.root()
  local b = root ~= nil and root.bounds or nil
  local cx, y1, y2 = 500, 900, 650
  if b ~= nil and b.right ~= nil and b.bottom ~= nil then
    local h = (b.bottom or 0) - (b.top or 0)
    cx = math.floor(((b.left or 0) + b.right) / 2)
    y1 = math.floor((b.top or 0) + h * 0.60)
    y2 = math.floor((b.top or 0) + h * 0.44)
  end
  pcall(function() return sf.touch.swipe(cx, y1, cx, y2, 250) end)
end

-- After a scroll: land using only the fresh snapshot. If a section is
-- still loaded, land after it (row walk, then signature scan bounded by
-- that section's bottom edge). If no section is loaded, land on the
-- first visible post.
local function landAfterScroll()
  local list2 = feedList()
  if list2 == nil then return false end
  local kids2 = list2:children() or {}
  local secIdx2, secBottom = nil, nil
  for i, k in ipairs(kids2) do
    if isSection(k) then
      secIdx2 = i
      if k.bounds ~= nil then secBottom = k.bounds.bottom end
      break
    end
  end
  if secIdx2 ~= nil then
    if focusPostBelow(kids2, secIdx2 + 1) then return true end
    return scanPostBelow(secBottom)
  end
  for _, k in ipairs(kids2) do
    if not isSection(k) then
      -- Only rows whose top edge is on screen: with small scroll steps,
      -- the first of these is the post that was right under the section.
      local onScreen = true
      if k.bounds ~= nil then
        if k.bounds.bottom ~= nil and k.bounds.bottom <= 0 then onScreen = false end
        if k.bounds.top ~= nil and k.bounds.top < 0 then onScreen = false end
      end
      if onScreen then
        local t = postTarget(k, 0)
        if t ~= nil then
          t:focus()
          return true
        end
      end
    end
  end
  return false
end

sf.onCommand('skip_section', function(event)
  local node = event.node or sf.screen.focused()
  if node == nil then return end
  local list = feedList()
  if list == nil then return end
  local kids = list:children() or {}
  local curIdx = nil
  for i, k in ipairs(kids) do
    if node == k or isInside(node, k) then
      curIdx = i
      break
    end
  end
  if curIdx == nil then return end
  if not isSection(kids[curIdx]) then return end  -- escape only
  if focusPostBelow(kids, curIdx + 1) then return end
  -- Cross-check in this same snapshot: the topmost real post (by its
  -- actions signature) at or below the section's bottom edge.
  local secBottom = nil
  if kids[curIdx].bounds ~= nil then secBottom = kids[curIdx].bounds.bottom end
  if scanPostBelow(secBottom) then return end
  -- Nothing below is loaded: creep with small scrolls (the feed
  -- lazy-loads as it moves), checking after every step, so the first
  -- post under the section is the one that gets landed on.
  for _ = 1, 4 do
    touchScrollSmall()
    sf.sleep(350)
    if landAfterScroll() then return end
  end
  sf.speak('No post below')
end)
