-- WaveSmith Swipes
-- While the WaveSmith waveform has focus AND audio is playing,
-- one-finger swipes become the arrow keys: left = rewind,
-- right = fast-forward, up = zoom in, down = zoom out.
-- Paused, or focus anywhere else, every swipe is handed straight
-- back to SandFly untouched — navigation never changes.
--
-- Idea, gesture choice and design: Justin Harris. Built with Atlas.
-- Works by performing the waveform's labeled accessibility
-- actions, which run the same code as WaveSmith's arrow keys.

local manifest = {
  id = 'wavesmith-swipes',
  name = 'WaveSmith Swipes',
  version = '1.0',
  author = 'Justin Harris',
  description = 'In WaveSmith, while audio plays and the waveform has focus, swipes rewind, fast-forward and zoom.',
  minApiVersion = 2,
  testedApiVersion = 3,
  apps = 'app.wavesmith',
  permissions = { 'screen', 'actions', 'input', 'speech' },
  commands = {
    { id = 'rewind', title = 'Rewind', gesture = 'swipeLeft' },
    { id = 'forward', title = 'Fast forward', gesture = 'swipeRight' },
    { id = 'zoomin', title = 'Zoom in', gesture = 'swipeUp' },
    { id = 'zoomout', title = 'Zoom out', gesture = 'swipeDown' },
  },
}

local function transport(event, label)
  local node = event.node
  if not node then return false end
  -- Only the waveform item itself, identified by its view id or
  -- its class, qualifies. Anything else: hand the swipe back.
  local id = node.id or ''
  local cls = node.className or ''
  if not (id:find('waveform', 1, true) or cls:find('WaveformView', 1, true)) then
    return false
  end
  -- Only while playing. Paused means the swipe is navigation.
  local state = node.stateDescription or ''
  local desc = node.contentDescription or ''
  if not (state == 'Playing' or desc:find('Playing', 1, true)) then
    return false
  end
  if node:perform(label) then
    return -- consumed: SandFly does nothing more with this swipe
  end
  sf.speak('Swipe action failed.')
end

sf.onCommand('rewind', function(event) return transport(event, 'Rewind') end)
sf.onCommand('forward', function(event) return transport(event, 'Fast forward') end)
sf.onCommand('zoomin', function(event) return transport(event, 'Zoom in') end)
sf.onCommand('zoomout', function(event) return transport(event, 'Zoom out') end)
