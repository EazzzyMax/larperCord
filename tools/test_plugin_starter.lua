-- Roda um plugin gerado num `larper` de mentira, com as mesmas regras que o app
-- aplica (src/plugins/runtime.zig): capacidade pedida para cada função, envio e
-- afins só num gesto, e o mesmo ambiente sem io, require nem load. Dispara todos
-- os eventos, comandos, atalhos, menus, botões, temporizadores e respostas HTTP.
-- Chamado por tools/test_plugin_starter.js:
--   lua tools/test_plugin_starter.lua arquivo.lua "caps,..." "api=cap;..." "host,..." pt|en
local path, caps_csv, need_csv, hosts_csv, lang = arg[1], arg[2] or "", arg[3] or "", arg[4] or "", arg[5] or "en"

local caps, NEED, HOSTS = {}, {}, {}
for c in caps_csv:gmatch("[^,]+") do caps[c] = true end
for k, v in need_csv:gmatch("([%w%.]+)=(%w+)") do NEED[k] = v end
for h in hosts_csv:gmatch("[^,]+") do HOSTS[h:lower()] = true end

local gesture, carry = false, false
-- Só num gesto (runtime.zig: p.gesture == 0 dá erro). insert vale também na
-- resposta de um pedido feito num gesto.
local GESTURE = { send = "g", jump = "g", copy = "g", open = "g", ["panel.open"] = "g", insert = "carry" }
local EVENTS = { message = "messages", edit = "messages", delete = "messages", dismiss = "decorate", hosts = "http",
  ready = true, channel = true, lang = true, panel = true }

local function fail(msg) error(msg, 3) end

local function check(name)
  local group = name:match("^(%w+)%.")
  local cap = NEED[name] or (group and NEED[group])
  if cap and not caps[cap] then fail(name .. " needs the capability " .. cap) end
  local g = GESTURE[name]
  if g == "g" and not gesture then fail(name .. " outside a gesture") end
  if g == "carry" and not gesture and not carry then fail(name .. " outside a gesture") end
end

local reg = { on = {}, commands = {}, keys = {}, menus = {}, timers = {}, http = {}, panel = nil, settings = nil, lsp = 0 }
for e in pairs(EVENTS) do reg.on[e] = {} end
local store = {}
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local larper = {}
local function def(name, fn)
  local g, f = name:match("^(%w+)%.(%w+)$")
  local t, k = larper, name
  if g then larper[g] = larper[g] or {}; t, k = larper[g], f end
  t[k] = function(...) check(name); return fn(...) end
end

-- Um texto bem longo (quase 7 KB) também passa pelo plugin: o que vai para uma URL ou para
-- larper.send precisa caber nos limites do app.
local long = string.rep("palavra comprida ção ", 300)

local function text(v, max, what)
  if type(v) ~= "string" or #v == 0 or #v > max then fail(what .. ": expected text up to " .. max .. " bytes") end
end

def("on", function(ev, f, opts)
  local need = EVENTS[ev]
  if not need then fail("larper.on: unknown event " .. tostring(ev)) end
  if need ~= true and not caps[need] then fail("larper.on(\"" .. ev .. "\") needs " .. need) end
  if type(f) ~= "function" then fail("larper.on: not a function") end
  if opts ~= nil then
    if ev ~= "message" and ev ~= "edit" then fail("contains only works on message and edit") end
    -- runtime.zig optNeedles: de 1 a 16 textos, cada um de 1 a 64 bytes.
    if type(opts.contains) ~= "table" or #opts.contains < 1 or #opts.contains > 16 then fail("contains: 1 to 16 texts") end
    for _, w in ipairs(opts.contains) do text(w, 64, "contains") end
  end
  table.insert(reg.on[ev], f)
end)
def("command", function(name, f)
  if type(name) ~= "string" or #name < 2 or #name > 32 or not name:match("^/[%w_%-]+$") then fail("bad command " .. tostring(name)) end
  reg.commands[name] = f
end)
def("keybind", function(spec, f) text(spec, 64, "keybind"); table.insert(reg.keys, f) end)
def("notify", function(t, o) text(t, 4000, "notify") end)
def("send", function(ch, t) text(t, 2000, "send") end)
def("channel", function() return { id = "5000", name = "general" } end)
def("guild", function() return { id = "500", name = "Server" } end)
def("lsp", function(l, argv)
  if type(l) ~= "string" or not l:match("^[a-z0-9_+%-]+$") or #l > 16 then fail("larper.lsp: bad language") end
  if type(argv) ~= "table" or #argv < 1 or #argv > 32 then fail("larper.lsp: bad command") end
  reg.lsp = reg.lsp + 1
end)
def("lang", function() return lang end)
def("tr", function(pt, en) return lang == "en" and en or pt end)
local function timer(secs, f, every)
  if type(secs) ~= "number" or type(f) ~= "function" or (every and secs < 1) then fail("bad timer") end
  table.insert(reg.timers, f)
  return #reg.timers
end
def("after", function(s, f) return timer(s, f, false) end)
def("every", function(s, f) return timer(s, f, true) end)
def("cancel", function(id) end)
def("menu", function(where, label, f, opts)
  if where ~= "message" and where ~= "user" then fail("larper.menu: where") end
  if type(label) == "table" then text(label.pt, 64, "menu pt"); text(label.en, 64, "menu en") else text(label, 64, "menu") end
  table.insert(reg.menus, { where = where, f = f })
  if #reg.menus > 4 then fail("larper.menu: more than 4") end
end)
def("decorate", function(m, o) if type(o) ~= "table" then fail("decorate: options") end if o.note then text(o.note, 2000, "note") end end)
def("undecorate", function(m) end)
def("rules", function(list) if type(list) ~= "table" or #list > 256 then fail("rules") end end)
def("messages", function(o, f) return true end)
def("jump", function(ch, id) end)
-- runtime.zig lInsert corta em 2000 bytes, sem erro.
def("insert", function(t) if type(t) ~= "string" then fail("insert: text") end end)
def("copy", function(t) text(t, 4000, "copy") end)
-- runtime.zig validOpenUrl: http(s), até 2000 bytes, sem espaço nem caractere de controle.
def("open", function(url)
  if type(url) ~= "string" or not url:match("^https?://.") or #url > 2000 or url:find("[%c ]") then fail("open: bad url (" .. #tostring(url) .. " bytes)") end
end)
def("completions", function(trig, list)
  if type(trig) ~= "string" or #trig ~= 1 or not (";!$%&+=?^"):find(trig, 1, true) then fail("completions: trigger") end
  if type(list) ~= "table" or #list > 256 then fail("completions: list") end
  for _, s in ipairs(list) do text(s.name, 64, "completion name"); text(s.text, 2000, "completion text") end
end)
def("rewrite", function(list) if type(list) ~= "table" or #list > 256 then fail("rewrite") end end)
def("urlencode", function(s) return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)) end)
def("storage.get", function(k) return copy(store[k]) end)
def("storage.set", function(k, v) store[k] = copy(v) end)
def("storage.delete", function(k) store[k] = nil end)
def("storage.keys", function() local t = {} for k in pairs(store) do t[#t + 1] = k end return t end)
def("storage.clear", function() store = {} end)
local function tree(t, what)
  if type(t) ~= "table" then fail(what .. ": not a table") end
  for _, n in ipairs(t) do
    if type(n) ~= "table" or type(n.type) ~= "string" then fail(what .. ": node without type") end
    if (n.type == "input" or n.type == "select" or n.type == "toggle") and type(n.key) ~= "string" then fail(what .. ": " .. n.type .. " needs a key") end
    if n.type == "row" then tree(n, what) end
  end
end
def("panel.set", function(t) tree(t, "panel"); reg.panel = t end)
def("panel.open", function() end)
def("panel.close", function() end)
def("settings.set", function(t) tree(t, "settings"); reg.settings = t end)
local function http(url, o, f)
  if type(o) == "function" then f = o end
  if type(url) ~= "string" then fail("http: url") end
  local host = url:match("^https://([^/?#]+)")
  if not host or url:find("[%s\128-\255]") then fail("http: bad url " .. url) end
  -- manifest.zig: a URL inteira tem no máximo 2048 bytes.
  if #url > 2048 then fail("http: url over 2048 bytes (" .. #url .. ")") end
  if not HOSTS[host:lower()] then fail("http: host not in @hosts: " .. host) end
  table.insert(reg.http, { f = f, gesture = gesture })
end
def("http.get", http)
def("http.post", http)
def("http.allowed", function(h) return false end)
def("json.encode", function(v) return "{}" end)
def("json.decode", function(s) return {} end)

local printed = {}
local env = {
  larper = larper, print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, "\t") end,
  string = string, table = table, math = math, utf8 = utf8,
  os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime },
  pairs = pairs, ipairs = ipairs, next = next, select = select, tostring = tostring, tonumber = tonumber, type = type,
  assert = assert, error = error, pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
  rawget = rawget, rawset = rawset, rawequal = rawequal, rawlen = rawlen,
}

local fh = assert(io.open(path, "rb"))
local src = fh:read("a")
fh:close()
local chunk, err = load(src, "=" .. path:match("[^/]+$"), "t", env)
if not chunk then io.stderr:write("syntax: " .. err .. "\n") os.exit(1) end

local calls = 0
local function run(what, f, ...)
  calls = calls + 1
  local ok, e = pcall(f, ...)
  if not ok then io.stderr:write(what .. ": " .. tostring(e) .. "\n") os.exit(1) end
end
local function asGesture(what, f, ...)
  gesture = true
  run(what, f, ...)
  gesture = false
end
local function fire(ev, ...) for _, f in ipairs(reg.on[ev]) do run("on " .. ev, f, ...) end end

-- Botões, campos e listas do painel e das opções: um clique é um gesto.
local function walk(t, what)
  if type(t) ~= "table" then return end
  for _, n in ipairs(t) do
    if n.on_click then asGesture(what .. " click", n.on_click) end
    if n.on_submit then asGesture(what .. " submit", n.on_submit, "texto de teste"); asGesture(what .. " submit", n.on_submit, long) end
    if n.on_change then
      if n.type == "toggle" then asGesture(what .. " toggle", n.on_change, false); asGesture(what .. " toggle", n.on_change, true)
      elseif n.type == "select" then asGesture(what .. " select", n.on_change, n.value)
      else run(what .. " change", n.on_change, "abc") end
    end
    if n.type == "row" then walk(n, what) end
    if n.type == "list" and type(n.items) == "table" then
      for _, it in ipairs(n.items) do
        if it.on_click then asGesture(what .. " item", it.on_click) end
        walk(it.actions, what .. " action")
      end
    end
  end
end

run("load", chunk)
fire("ready")
fire("channel", { id = "5000", name = "general" })
fire("channel", nil)
fire("panel", true)
local msg = { id = "1350000000000000001", content = "larper cve-2021-44228 pizza https://example.com/x?utm_source=a 日本語 é", mine = false, ignored = false,
  author = { id = "1001", name = "ana" }, channel = { id = "5000", name = "general" }, guild = { id = "500", name = "Server" },
  time = os.time(), attachments = 0 }
for i = 1, 3 do fire("message", msg) end
fire("message", { id = "2", content = "", mine = true, author = { id = "1", name = "eu" }, channel = { id = "5000", name = "general" }, time = os.time(), attachments = 1 })
fire("edit", msg)
fire("delete", { id = msg.id, channel = "5000" })
fire("dismiss", { id = msg.id })
fire("hosts")
lang = lang == "en" and "pt" or "en"
fire("lang")
lang = lang == "en" and "pt" or "en"
fire("lang")
for name, f in pairs(reg.commands) do asGesture(name, f, ""); asGesture(name, f, "um texto qualquer"); asGesture(name, f, long) end
for i, f in ipairs(reg.keys) do asGesture("keybind " .. i, f) end
for i, m in ipairs(reg.menus) do
  asGesture("menu " .. i, m.f, m.where == "message" and msg or { id = "1001", name = "ana" })
  if m.where == "message" then
    local big = {}
    for k, v in pairs(msg) do big[k] = v end
    big.content = long
    asGesture("menu " .. i .. " (long message)", m.f, big)
  end
end
walk(reg.panel, "panel")
walk(reg.settings, "settings")
for i, f in ipairs(reg.timers) do run("timer " .. i, f) end
-- As respostas chegam depois, fora do gesto; só pôr texto na caixa vale se o pedido veio de um.
local pending = reg.http
reg.http = {}
for i, r in ipairs(pending) do
  carry = r.gesture
  run("http " .. i, r.f, { ok = true, status = 200, body = "{\"title\":\"ok\"}" })
  run("http " .. i, r.f, { ok = false, status = 0, error = "not_approved" })
  run("http " .. i, r.f, { ok = false, status = 500, error = "network" })
  carry = false
end
walk(reg.panel, "panel")
local loaded = false
for _, p in ipairs(printed) do if p == "loaded" or p == "carregado" then loaded = true end end
if not loaded then io.stderr:write("no loaded line\n") os.exit(1) end
print("ok " .. calls)
