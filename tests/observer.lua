local events = {}
local State = dofile("hypr/ObserverState.lua")

local function push(name, value)
  events[#events + 1] = value and (name .. ":" .. value) or name
end

local machine = State.new({
  initial_modifiers = {},
  on_arm = function(value) push("arm", value) end,
  on_update = function(value) push("update", value) end,
  on_attempt = function(modifiers, keycode) push("attempt", modifiers .. ":" .. keycode) end,
  on_hide = function() push("hide") end,
  on_reload = function() push("reload") end,
})

machine:handle_key(133, 1, { super = true })
machine:handle_key(50, 1, { super = true, shift = true })
machine:handle_key(65, 1, { super = true, shift = true })
machine:handle_key(65, 0, { super = true, shift = true })
machine:handle_key(133, 0, {})
machine:config_reloaded({})

local actual = table.concat(events, ",")
local expected = "arm:SUPER,update:SUPER SHIFT,attempt:SUPER SHIFT:65,hide,reload"
assert(actual == expected, "expected " .. expected .. ", got " .. actual)

print("observer tests passed")
