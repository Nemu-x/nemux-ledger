-- Orders: guild crafting requests. "Please make me Mooncloth x2."
-- The craft and the trade happen in the game, by hand; this only keeps the list.
--
-- Message: O|1|<ver>|<id>|<recipeID>|<qty>|<mats>|<status>|<upd>|<from>|<to>
--   id     = "<requester GUID>:<seq>", never reused
--   mats   = 1 when the requester brings the reagents, else 0
--   status = O open, A accepted, D done, X cancelled (requester), N declined (crafter)
--   upd    = server time of the last change; the newest wins
--   from   = requester, to = crafter ("" = anyone who knows the recipe)
-- Sent to the guild on every change, and again to a guild mate who comes
-- online, so a request reaches a crafter who was offline when it was made.

local _, RL = ...
local O = RL:NewModule("Orders")
RL.Orders = O

local PROTO = "1"
local MAX_OPEN = 10           -- open requests one player may have
local MAX_QTY = 20
local KEEP_CLOSED = 7 * 86400 -- finished requests stay visible this long
local KEEP_OPEN = 30 * 86400  -- open ones are dropped after this
local CLOSED = { D = true, X = true, N = true }
O.STATUS = { O = "Open", A = "Accepted", D = "Done", X = "Cancelled", N = "Declined" }

local function G() return RL.Guild end

local function same(a, b)
  if not a or not b or a == "" or b == "" then return false end
  return G().Short(a) == G().Short(b)
end

function O:IsMine(o) return G():IsMe(o.from) end
function O:IsForMe(o) return o.to ~= "" and G():IsMe(o.to) end

-- Requests a crafter may pick up: addressed to them, or open to anyone who knows it.
function O:CanCraft(o)
  if self:IsForMe(o) then return true end
  if o.to ~= "" then return false end
  for _, rec in pairs(RL.charDB.recipes) do
    if type(rec) == "table" and rec.ids and rec.ids[o.recipe] then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------
function O:Message(o)
  return table.concat({ "O", PROTO, RL.version, o.id, o.recipe, o.qty, o.mats and 1 or 0, o.status, o.upd,
    o.from, o.to or "" }, "|")
end

function O:Send(o, channel, target)
  if not IsInGuild() then return end
  RL.Guild:Queue(self:Message(o), channel or "GUILD", target)
end

-- Returns the sender's version when the message was valid.
-- Only the requester or the crafter send a request (the requester re-sends the
-- crafter's answer on hello). A finished request never opens again.
function O.OnMessage(who, _, _, msg)
  local proto, version, id, recipe, qty, mats, status, upd, from, to =
    msg:match("^O|(%d+)|(%d+%.%d+%.%d+)|([^|]+)|(%d+)|(%d+)|([01])|([OADXN])|(%d+)|([^|]+)|([^|]*)$")
  if proto ~= PROTO then return nil end
  recipe, qty, upd = tonumber(recipe), tonumber(qty), tonumber(upd)
  if #id > 64 or recipe > 10000000 or qty < 1 or qty > MAX_QTY or upd > GetServerTime() + 3600 then return nil end
  local fromSender, toSender = same(who, from), same(who, to)
  if not (fromSender or toSender) then return nil end
  if status == "O" and not fromSender then return nil end
  if (status == "A" or status == "N") and to == "" then return nil end
  if status == "X" and not fromSender then return nil end
  local old = RL.db.orders[id]
  if old and old.upd >= upd then return version end -- we already know this or newer
  if old and CLOSED[old.status] and not CLOSED[status] then return version end
  local new = { id = id, recipe = recipe, qty = qty, mats = mats == "1", status = status, upd = upd, from = from, to = to,
    created = old and old.created or upd }
  RL.db.orders[id] = new
  O:Notify(old, new)
  if new.status == "D" and not (old and old.status == "D") and new.to ~= "" then RL:Fire("RL_ORDER_DONE", new) end
  RL:Fire("RL_ORDERS_UPDATED")
  return version
end

-- Chat lines for what matters to me.
function O:Notify(old, new)
  local T = RL.Theme
  local name = RL.Recipes:RecipeName(new.recipe) .. (new.qty > 1 and (" x" .. new.qty) or "")
  local function who(n) return T.ClassColored(G().Short(n), (G().byName[G().FullName(n) or ""] or {}).classFile) end
  if (not old or old.status ~= new.status) and self:IsMine(new) then
    if new.status == "A" then RL:Print("%s accepted your request: %s.", who(new.to), name)
    elseif new.status == "D" then RL:Print("%s marked your request done: %s. Check your mail or trade.", who(new.to), name)
    elseif new.status == "N" then RL:Print("%s can't make %s right now.", who(new.to), name) end
  elseif new.status == "O" and (not old or old.status ~= "O") and self:CanCraft(new) and not self:IsMine(new) then
    RL:Print("%s asks %s to craft %s%s. %s", who(new.from), self:IsForMe(new) and "you" or "the guild", name,
      new.mats and " (brings reagents)" or "", T.Color("/rq orders", "info"))
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
  elseif new.status == "X" and old and old.status ~= "X" and self:IsForMe(new) then
    RL:Print("%s cancelled the request for %s.", who(new.from), name)
  end
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
local function myName()
  local G = RL.Guild
  for _, m in ipairs(G.members) do if G:IsMe(m.name) then return m.name end end
  return (UnitName("player"))
end

local function change(o, status, extra)
  o.status, o.upd = status, math.max(math.floor(GetServerTime()), (o.upd or 0) + 1)
  if extra then for k, v in pairs(extra) do o[k] = v end end
  RL.db.orders[o.id] = o
  O:Send(o)
  if status == "D" then RL:Fire("RL_ORDER_DONE", o) end
  RL:Fire("RL_ORDERS_UPDATED")
end

-- The open request I already have for this recipe (and crafter), if any.
function O:Existing(recipeID, to)
  for _, o in pairs(RL.db.orders) do
    if o.recipe == recipeID and o.status == "O" and self:IsMine(o) and (to == nil or same(o.to, to) or (o.to == "" and to == "")) then
      return o
    end
  end
end

-- New request, or one more of the same while it is still open.
-- to = crafter's name, or nil/"" for anyone. Returns the request or nil, reason.
function O:Request(recipeID, to)
  if not IsInGuild() then return nil, "noguild" end
  to = (to and to ~= "") and (RL.Guild.FullName(to) or to) or ""
  if to ~= "" and G():IsMe(to) then return nil, "self" end
  local o = self:Existing(recipeID, to)
  if o then
    if o.qty >= MAX_QTY then return nil, "max" end
    change(o, "O", { qty = o.qty + 1 })
    return o
  end
  local open = 0
  for _, x in pairs(RL.db.orders) do if self:IsMine(x) and not CLOSED[x.status] then open = open + 1 end end
  if open >= MAX_OPEN then return nil, "toomany" end
  local id = RL.DB:NextEventId()
  if not id then return nil, "noid" end
  local _, ready = RL.Recipes:ReagentStatus(recipeID)
  o = { id = id, recipe = recipeID, qty = 1, mats = ready and true or false, status = "O", upd = math.floor(GetServerTime()),
    from = myName(), to = to, created = math.floor(GetServerTime()) }
  RL.db.orders[id] = o
  self:Send(o)
  RL:Fire("RL_ORDERS_UPDATED")
  return o
end

function O:Accept(o)
  if self:IsMine(o) or not (o.status == "O" and self:CanCraft(o)) then return false end
  change(o, "A", { to = myName() })
  return true
end

function O:Decline(o)
  if not (self:IsForMe(o) and (o.status == "O" or o.status == "A")) then return false end
  change(o, "N")
  return true
end

function O:Done(o)
  if not ((self:IsForMe(o) or self:IsMine(o)) and o.status == "A") then return false end
  change(o, "D")
  return true
end

function O:Cancel(o)
  if not (self:IsMine(o) and not CLOSED[o.status]) then return false end
  change(o, "X")
  return true
end

-- Hide a finished request from my list (it is forgotten after a week anyway).
function O:Dismiss(o)
  if CLOSED[o.status] then RL.db.orders[o.id] = nil; RL:Fire("RL_ORDERS_UPDATED") end
end

-- ---------------------------------------------------------------------------
-- Lists
-- ---------------------------------------------------------------------------
-- Rows for the UI: requests I made, requests I can craft, then the rest of the guild's open ones.
-- Each row = the request plus { name, role = "mine" | "craft" | "guild" }.
function O:Rows()
  local rows = {}
  for _, o in pairs(RL.db.orders) do
    local role = self:IsMine(o) and "mine" or (self:CanCraft(o) or self:IsForMe(o)) and "craft" or "guild"
    if role ~= "guild" or not CLOSED[o.status] then
      local r = setmetatable({ name = RL.Recipes:RecipeName(o.recipe), role = role }, { __index = o })
      rows[#rows + 1] = r
    end
  end
  local roleOrder = { craft = 1, mine = 2, guild = 3 }
  local statusOrder = { O = 1, A = 2, D = 3, N = 4, X = 5 }
  table.sort(rows, function(a, b)
    local ca, cb = CLOSED[a.status] and 1 or 0, CLOSED[b.status] and 1 or 0
    if ca ~= cb then return ca < cb end
    if roleOrder[a.role] ~= roleOrder[b.role] then return roleOrder[a.role] < roleOrder[b.role] end
    if statusOrder[a.status] ~= statusOrder[b.status] then return statusOrder[a.status] < statusOrder[b.status] end
    return a.upd > b.upd
  end)
  return rows
end

-- Numbers for the tab button and the HUD: requests waiting for me.
function O:Waiting()
  local n = 0
  for _, o in pairs(RL.db.orders) do
    if (o.status == "O" and self:CanCraft(o) and not self:IsMine(o)) or (o.status == "A" and self:IsForMe(o)) then n = n + 1 end
  end
  return n
end

function O:Prune()
  local now = GetServerTime()
  for id, o in pairs(RL.db.orders) do
    local keep = CLOSED[o.status] and KEEP_CLOSED or KEEP_OPEN
    if type(o) ~= "table" or now - (o.upd or 0) > keep then RL.db.orders[id] = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function O:Init()
  RL.Guild.handlers.O = O.OnMessage
  O:Prune()
end

-- A guild mate came online: send them every live request that involves them,
-- and tell me when the crafter of my request is around.
RL:On("RL_PEER_HELLO", function(sender)
  local told = false
  for _, o in pairs(RL.db.orders) do
    if not CLOSED[o.status] and (O:IsMine(o) or O:IsForMe(o)) then
      if O:IsMine(o) or same(o.from, sender) then O:Send(o, "WHISPER", sender) end
      if O:IsMine(o) and same(o.to, sender) and not told then
        told = true
        RL:Print("%s is online: they have your request for %s.", RL.Guild.Short(sender), RL.Recipes:RecipeName(o.recipe))
      end
    end
  end
end)

-- My own open requests go to the guild when I log in (crafters who were offline get them).
RL:On("RL_HELLO_SENT", function()
  C_Timer.After(11, function()
    for _, o in pairs(RL.db.orders) do
      if not CLOSED[o.status] and (O:IsMine(o) or O:IsForMe(o)) then O:Send(o) end
    end
  end)
end)
