--!nonstrict
-- layer 入口：根据设置生成准星 SVG（绝对定位 / 独立透明度 / 描边轮廓由 SVG 完成），
-- 写入插件数据目录后用 ui.image 渲染。surface 按内容屏幕居中，click_through 鼠标完全穿透。
--
-- 实时性说明：宿主在设置变更时不重建 layer runtime、也不调用其 onConfigChanged，
-- 因此这里用 onFrameTick 节流轮询"配置指纹"，指纹变化即重绘（准实时，约 0.12s 延迟）。

local DEFAULT_COLOR = "#00E676"

local function warnx(msg)
  warn("crosshair: " .. msg)
end

local rev = 0
local lastSig = ""
local pollAcc = 0
local POLL_MS = 120

local KEYS = {
  "color", "outline", "outline_pct", "outline_thickness", "offset_x", "offset_y",
  "center_enabled", "center_shape", "center_pct", "center_thickness",
  "inner_enabled", "inner_pct", "inner_length", "inner_thickness", "inner_offset",
  "outer_enabled", "outer_pct", "outer_length", "outer_thickness", "outer_offset",
}

local function configSig()
  local t = {}
  for i = 1, #KEYS do
    t[i] = tostring(noctalia.getConfig(KEYS[i]))
  end
  return table.concat(t, "|")
end

-- 透明度设置是 0–100 的整数百分比，这里换算成 0–1。
local function pct(v, dflt)
  local n = v or dflt
  return math.clamp(n / 100, 0, 1)
end

local function cfg()
  return {
    color      = noctalia.getConfig("color") or DEFAULT_COLOR,
    outline    = noctalia.getConfig("outline") == true,
    outline_op = pct(noctalia.getConfig("outline_pct"), 60),
    outline_t  = noctalia.getConfig("outline_thickness") or 1,
    ox         = noctalia.getConfig("offset_x") or 0,
    oy         = noctalia.getConfig("offset_y") or 0,
    center_on  = noctalia.getConfig("center_enabled") == true,
    center_sh  = noctalia.getConfig("center_shape") or "cross",
    center_op  = pct(noctalia.getConfig("center_pct"), 100),
    center_t   = noctalia.getConfig("center_thickness") or 2,
    inner_on   = noctalia.getConfig("inner_enabled") == true,
    inner_op   = pct(noctalia.getConfig("inner_pct"), 100),
    inner_len  = noctalia.getConfig("inner_length") or 6,
    inner_t    = noctalia.getConfig("inner_thickness") or 2,
    inner_off  = noctalia.getConfig("inner_offset") or 6,
    outer_on   = noctalia.getConfig("outer_enabled") == true,
    outer_op   = pct(noctalia.getConfig("outer_pct"), 100),
    outer_len  = noctalia.getConfig("outer_length") or 14,
    outer_t    = noctalia.getConfig("outer_thickness") or 2,
    outer_off  = noctalia.getConfig("outer_offset") or 20,
  }
end

-- 矩形：坐标相对准星中心 (cx, cy)。outline 用居中描边 + paint-order，视觉上即外扩轮廓。
local function rect(cx, cy, x, y, w, h, color, op, c)
  local s = string.format(
    '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" fill-opacity="%.3f"',
    cx + x, cy + y, w, h, color, op
  )
  if c.outline then
    s = s .. string.format(
      ' stroke="#000000" stroke-opacity="%.3f" stroke-width="%.2f" paint-order="stroke"',
      c.outline_op, c.outline_t * 2
    )
  end
  return s .. "/>"
end

-- 圆（点/环共用）。strokeW 为 nil 时画实心点，否则画描边环。
local function circle(cx, cy, r, color, op, strokeW)
  if strokeW == nil then
    return string.format('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" fill-opacity="%.3f"/>', cx, cy, r, color, op)
  end
  return string.format(
    '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="none" stroke="%s" stroke-opacity="%.3f" stroke-width="%.2f"/>',
    cx, cy, r, color, op, strokeW
  )
end

-- 一组四向线段（上 / 下 / 左 / 右）。
local function fourLines(cx, cy, off, len, th, op, c)
  return {
    rect(cx, cy, -th / 2, -off - len, th, len, c.color, op, c),
    rect(cx, cy, -th / 2, off, th, len, c.color, op, c),
    rect(cx, cy, -off - len, -th / 2, len, th, c.color, op, c),
    rect(cx, cy, off, -th / 2, len, th, c.color, op, c),
  }
end

-- 中心准星形状：cross / dot / ring / x。thickness 同时驱动线宽与整体尺度。
local function centerParts(cx, cy, c)
  local t = c.center_t
  local sh = c.center_sh
  if sh == "dot" then
    local out = {}
    if c.outline then
      -- 轮廓 = 底下垫一个更大的黑色实心圆
      out[1] = circle(cx, cy, t + c.outline_t, "#000000", c.outline_op, nil)
    end
    out[#out + 1] = circle(cx, cy, t, c.color, c.center_op, nil)
    return out
  elseif sh == "ring" then
    local r = t * 2
    local out = {}
    if c.outline then
      -- 轮廓 = 底下垫一条更粗的黑色描边
      out[1] = circle(cx, cy, r, "#000000", c.outline_op, t + 2 * c.outline_t)
    end
    out[#out + 1] = circle(cx, cy, r, c.color, c.center_op, t)
    return out
  else -- cross / x
    local arm = t * 3
    local parts = {
      rect(cx, cy, -arm / 2, -t / 2, arm, t, c.color, c.center_op, c),
      rect(cx, cy, -t / 2, -arm / 2, t, arm, c.color, c.center_op, c),
    }
    if sh == "x" then
      return { string.format('<g transform="rotate(45 %.2f %.2f)">%s</g>', cx, cy, table.concat(parts, "")) }
    end
    return parts
  end
end

local function svgOf(c)
  -- 画布半幅 = 最大部件伸展 + 轮廓外扩 + 整体偏移 + 1px 抗锯齿边距
  local e = 1
  if c.inner_on then e = math.max(e, c.inner_off + c.inner_len) end
  if c.outer_on then e = math.max(e, c.outer_off + c.outer_len) end
  if c.center_on then
    if c.center_sh == "dot" then
      e = math.max(e, c.center_t + (c.outline and c.outline_t or 0))
    elseif c.center_sh == "ring" then
      e = math.max(e, c.center_t * 2 + c.center_t / 2 + (c.outline and c.outline_t or 0))
    else
      e = math.max(e, math.ceil(c.center_t * 1.5) + (c.outline and c.outline_t or 0))
    end
  end
  e = e + math.max(math.abs(c.ox), math.abs(c.oy)) + 1

  local cx, cy = e + c.ox, e + c.oy
  local body = {}

  -- 绘制顺序：外准星 → 内准星 → 中心（重叠时上层可见）
  if c.outer_on then
    local ls = fourLines(cx, cy, c.outer_off, c.outer_len, c.outer_t, c.outer_op, c)
    for i = 1, #ls do body[#body + 1] = ls[i] end
  end
  if c.inner_on then
    local ls = fourLines(cx, cy, c.inner_off, c.inner_len, c.inner_t, c.inner_op, c)
    for i = 1, #ls do body[#body + 1] = ls[i] end
  end
  if c.center_on then
    local cp = centerParts(cx, cy, c)
    for i = 1, #cp do body[#body + 1] = cp[i] end
  end

  return string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>',
    e * 2, e * 2, e * 2, e * 2, table.concat(body, "")
  ), e * 2
end

local function render()
  local c = cfg()
  local dir = noctalia.pluginDataDir()
  if dir == nil then
    warnx("pluginDataDir unavailable")
    return
  end

  -- 交替文件名，避免渲染层按同一路径缓存旧图
  rev = (rev % 2) + 1
  local path = dir .. "/crosshair_" .. rev .. ".svg"
  local svg, size = svgOf(c)
  local ok, err = noctalia.writeFile(path, svg)
  if not ok then
    warnx("write svg failed: " .. tostring(err))
    return
  end

  -- 全屏 surface：用 flex 将准星图像居中于物理屏幕中心；offset 已在 SVG 内部平移实现
  layer.render(
    ui.column({ flexGrow = 1, justify = "center", align = "center", gap = 0 }, {
      -- ui.image 必须显式传宽高
      ui.image({ path = path, width = size, height = size, fit = "stretch" }),
    })
  )
  lastSig = configSig()
end

render()
layer.setNeedsFrameTick(true)

function onFrameTick(deltaMs)
  pollAcc += tonumber(deltaMs) or 0
  if pollAcc < POLL_MS then
    return
  end
  pollAcc = 0
  if configSig() ~= lastSig then
    render()
  end
end

-- 若宿主将来支持 layer 的设置回调，这里可直接命中，轮询只是兜底。
function onConfigChanged()
  render()
end
