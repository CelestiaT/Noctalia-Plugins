--!nonstrict
-- WaterClock layer：全屏 overlay 水面（纯风格化绘制，不采样背景）。
-- 定时运行时水位从 0% 线性升到 100%；每帧按 render_fps 节流重新生成 SVG。
-- 所有元素参数在 runtime 内固定（LCG 预生成），动画只推进时间 t，元素不跳变。

local TWO_PI = math.pi * 2

local rev = 0
local acc = 0

local seed = 987654321
local function rnd()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed / 2147483648
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- ---------- 稳定元素参数（每 runtime 生成一次） ----------

local CAUSTICS, RAYS, BUBBLES, SPARKLES, SPECKS = {}, {}, {}, {}, {}
for i = 1, 30 do
  CAUSTICS[i] = { dy = rnd(), wl = 140 + rnd() * 280, amp = 3 + rnd() * 7,
                  ph = rnd() * TWO_PI, w = 2.5 + rnd() * 4.5,
                  op = 0.10 + rnd() * 0.20, spd = 0.5 + rnd() * 0.9 }
end
for i = 1, 20 do
  RAYS[i] = { x = rnd(), w = 50 + rnd() * 110, reach = 0.25 + rnd() * 0.5,
              op = 0.05 + rnd() * 0.07, sway = rnd() * TWO_PI }
end
for i = 1, 60 do
  BUBBLES[i] = { x = rnd(), phase = rnd(), r = 2.5 + rnd() * 4.5,
                 spd = 0.04 + rnd() * 0.10, wob = 6 + rnd() * 16 }
end
for i = 1, 24 do
  SPARKLES[i] = { x = rnd(), r = 1.5 + rnd() * 2.5, tw = rnd() * TWO_PI }
end
for i = 1, 70 do
  SPECKS[i] = { x = rnd(), y = rnd(), r = 0.8 + rnd() * 1.4, op = 0.15 + rnd() * 0.35 }
end

-- ---------- 配置 ----------

local function settings()
  return {
    duration_min   = noctalia.getConfig("duration_min") or 25,
    end_action     = noctalia.getConfig("end_action") or "stay",
    static_level   = noctalia.getConfig("static_level") or 45,
    color_surface  = noctalia.getConfig("color_surface") or "#3ec6e0",
    color_deep     = noctalia.getConfig("color_deep") or "#032c54",
    fog            = (noctalia.getConfig("fog_strength") or 55) / 100,
    wave_amp       = noctalia.getConfig("wave_amplitude") or 8,
    wave_len       = noctalia.getConfig("wave_length") or 640,
    wave_spd       = (noctalia.getConfig("wave_speed") or 35) / 100,
    caustics_n     = noctalia.getConfig("caustics_density") or 12,
    caustics_k     = (noctalia.getConfig("caustics_strength") or 55) / 100,
    rays_n         = noctalia.getConfig("rays_density") or 9,
    rays_k         = (noctalia.getConfig("rays_strength") or 50) / 100,
    bubbles_on     = noctalia.getConfig("bubbles") == true,
    bubble_n       = noctalia.getConfig("bubble_density") or 18,
    sparkles_on    = noctalia.getConfig("sparkles") == true,
  }
end

-- ---------- 水位 ----------

local function levelNow(c, now_ms)
  if noctalia.state.get("wc_running") == true then
    local start = noctalia.state.get("wc_start")
    local dur = noctalia.state.get("wc_dur")
    if type(start) ~= "number" then
      return c.static_level
    end
    if type(dur) ~= "number" then
      dur = c.duration_min * 60
    end
    local prog = (now_ms - start) / (dur * 1000)
    if prog >= 1 then
      noctalia.state.set("wc_running", false)
      if c.end_action == "hide" then
        noctalia.layer.hide("water")
        return nil
      end
      return 100
    end
    return clamp(prog * 100, 0, 100)
  end
  return c.static_level
end

-- ---------- SVG 生成 ----------

local function waveY(x, y0, amp, wl, ph)
  return y0 + amp * math.sin(TWO_PI * x / wl + ph)
            + 0.4 * amp * math.sin(TWO_PI * x / (wl * 0.37) + ph * 1.7)
end

local function wavePath(W, y0, amp, wl, ph)
  local out, n = {}, 0
  for x = 0, W, 20 do
    n = n + 1
    out[n] = string.format("%.1f %.1f", x, waveY(x, y0, amp, wl, ph))
  end
  return "M " .. table.concat(out, " L ")
end

local function svgOf(c, W, H, level, t)
  local wl_y = H - (level / 100) * H
  local bh = H - wl_y
  local ph = t * c.wave_spd * 2
  local defs, body = {}, {}

  -- 深度雾渐变
  defs[#defs + 1] = string.format(
    '<linearGradient id="fog" x1="0" y1="%.0f" x2="0" y2="%.0f" gradientUnits="userSpaceOnUse">'
    .. '<stop offset="0" stop-color="%s" stop-opacity="%.3f"/>'
    .. '<stop offset="0.45" stop-color="%s" stop-opacity="%.3f"/>'
    .. '<stop offset="1" stop-color="%s" stop-opacity="%.3f"/></linearGradient>',
    wl_y, H,
    c.color_surface, 0.38 * c.fog,
    c.color_deep, 0.58 * c.fog,
    c.color_deep, 0.88 * c.fog)
  body[#body + 1] = string.format('<rect x="0" y="%.1f" width="%d" height="%.1f" fill="url(#fog)"/>',
    wl_y, W, bh)

  if bh > 30 then
    -- 体积光柱
    for i = 1, c.rays_n do
      local r = RAYS[i]
      local x = r.x * W + math.sin(t * 0.3 + r.sway) * 30
      local y2 = wl_y + bh * r.reach
      defs[#defs + 1] = string.format(
        '<linearGradient id="ray%d" x1="0" y1="%.0f" x2="0" y2="%.0f" gradientUnits="userSpaceOnUse">'
        .. '<stop offset="0" stop-color="#d8f7ff" stop-opacity="%.3f"/>'
        .. '<stop offset="1" stop-color="#d8f7ff" stop-opacity="0"/></linearGradient>',
        i, wl_y, y2, r.op * c.rays_k)
      body[#body + 1] = string.format(
        '<polygon points="%.0f,%.0f %.0f,%.0f %.0f,%.0f %.0f,%.0f" fill="url(#ray%d)"/>',
        x - r.w / 2, wl_y, x + r.w / 2, wl_y, x + r.w * 0.9, y2, x - r.w * 0.9, y2, i)
    end

    -- 焦散：亮暗成对
    for i = 1, c.caustics_n do
      local k = CAUSTICS[i]
      local y0 = wl_y + 14 + k.dy * (bh - 50)
      local kp = k.ph + t * k.spd * c.wave_spd * 2
      local op = k.op * c.caustics_k
      body[#body + 1] = string.format(
        '<path d="%s" fill="none" stroke="#e8fbff" stroke-opacity="%.3f" stroke-width="%.1f" filter="url(#cau)"/>',
        wavePath(W, y0, k.amp, k.wl, kp), op, k.w)
      body[#body + 1] = string.format(
        '<path d="%s" fill="none" stroke="#032a4a" stroke-opacity="%.3f" stroke-width="%.1f" filter="url(#cau)"/>',
        wavePath(W, y0 + k.w * 1.6, k.amp, k.wl, kp), op * 0.8, k.w * 1.3)
    end

    -- 悬浮微粒
    for i = 1, #SPECKS do
      local s = SPECKS[i]
      body[#body + 1] = string.format('<circle cx="%.0f" cy="%.0f" r="%.1f" fill="#eaffff" fill-opacity="%.2f"/>',
        s.x * W, wl_y + 10 + s.y * (bh - 20), s.r, s.op * (0.4 + 0.6 * c.fog))
    end

    -- 上升气泡
    if c.bubbles_on then
      for i = 1, c.bubble_n do
        local b = BUBBLES[i]
        local cycle = (t * b.spd + b.phase) % 1
        local y = H - cycle * (bh + 30)
        if y > wl_y + 6 then
          local x = b.x * W + math.sin(cycle * 9 + b.phase * 6) * b.wob
          local op = 0.35 + 0.35 * math.sin(cycle * math.pi)
          body[#body + 1] = string.format(
            '<circle cx="%.0f" cy="%.0f" r="%.1f" fill="none" stroke="#e6fbff" stroke-opacity="%.2f" stroke-width="1.5"/>',
            x, y, b.r * (0.55 + 0.45 * cycle), op)
          body[#body + 1] = string.format(
            '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#ffffff" fill-opacity="%.2f"/>',
            x - b.r * 0.35, y - b.r * 0.35, b.r * 0.25, op * 0.8)
        end
      end
    end
  end

  -- 水面复合线：全反射暗带 / 天空反射亮带 / 主高光线 / 副线
  local amp = c.wave_amp
  local wl = c.wave_len
  body[#body + 1] = string.format(
    '<path d="%s L %d %.1f L 0 %.1f Z" fill="#02325a" fill-opacity="0.5" filter="url(#soft)"/>',
    wavePath(W, wl_y, amp, wl, ph), W, wl_y + 26, wl_y + 26)
  body[#body + 1] = string.format(
    '<path d="%s L %d %.1f L 0 %.1f Z" fill="#cfeeff" fill-opacity="0.28" filter="url(#soft)"/>',
    wavePath(W, wl_y - 10, amp, wl, ph), W, wl_y, wl_y)
  body[#body + 1] = string.format(
    '<path d="%s" fill="none" stroke="#f2fdff" stroke-opacity="0.95" stroke-width="2.6" filter="url(#soft)"/>',
    wavePath(W, wl_y, amp, wl, ph))
  body[#body + 1] = string.format(
    '<path d="%s" fill="none" stroke="#7fd8ff" stroke-opacity="0.5" stroke-width="1.6"/>',
    wavePath(W, wl_y + 3, amp, wl, ph))

  -- 水面闪点
  if c.sparkles_on then
    for i = 1, #SPARKLES do
      local sp = SPARKLES[i]
      local x = sp.x * W
      local y = waveY(x, wl_y, amp, wl, ph)
      local tw = 0.5 + 0.5 * math.sin(t * 3 + sp.tw)
      body[#body + 1] = string.format(
        '<circle cx="%.0f" cy="%.1f" r="%.1f" fill="#ffffff" fill-opacity="%.2f" filter="url(#soft)"/>',
        x, y, sp.r * (0.6 + 0.4 * tw), 0.35 + 0.6 * tw)
    end
  end

  defs[#defs + 1] = '<filter id="soft" x="-20%" y="-300%" width="140%" height="700%"><feGaussianBlur stdDeviation="2.2"/></filter>'
  defs[#defs + 1] = '<filter id="cau" x="-5%" y="-500%" width="110%" height="1100%"><feGaussianBlur stdDeviation="5"/></filter>'

  return string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><defs>%s</defs>%s</svg>',
    W, H, W, H, table.concat(defs, ""), table.concat(body, ""))
end

-- ---------- 渲染 ----------

local function render(now)
  local c = settings()
  now = now or noctalia.nowMs()
  local level = levelNow(c, now)
  if level == nil then
    return
  end

  local W, H = 1920, 1080
  local name = layer.outputName()
  for _, o in ipairs(noctalia.outputs()) do
    if name == nil or o.name == name then
      W, H = o.width, o.height
      break
    end
  end

  local dir = noctalia.pluginDataDir()
  if dir == nil then
    warn("waterclock: pluginDataDir unavailable")
    return
  end

  rev = (rev % 2) + 1
  local path = dir .. "/water_" .. rev .. ".svg"
  local ok, err = noctalia.writeFile(path, svgOf(c, W, H, level, now / 1000))
  if not ok then
    warn("waterclock: write svg failed: " .. tostring(err))
    return
  end

  layer.render(ui.image({ path = path, width = W, height = H, fit = "stretch" }))
end

-- 穿透开关可在运行时同步设置（manifest 默认 true）
noctalia.layer.configure("water", { clickThrough = noctalia.getConfig("click_through") ~= false })

render()
layer.setNeedsFrameTick(true)

function onFrameTick(deltaMs)
  acc += tonumber(deltaMs) or 0
  local budget = 1000 / (tonumber(noctalia.getConfig("render_fps")) or 30)
  if acc >= budget then
    acc = 0
    render(noctalia.nowMs())
  end
end
