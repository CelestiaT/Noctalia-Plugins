--!nonstrict
-- 栏组件：点击图标切换 overlay 准星的显示/隐藏。
-- shown 存在进程级 noctalia.state 里：设置变更会重建 widget runtime，
-- 用局部变量的话状态会丢失，导致图标与 overlay 不同步。

local function isShown()
  return noctalia.state.get("shown") == true
end

local function dotColor()
  return noctalia.getConfig("color") or "#00E676"
end

local function render()
  local shown = isShown()
  barWidget.setGlyph(shown and "circle-filled" or "circle")
  barWidget.setGlyphColor(if shown then dotColor() else "on_surface")
  barWidget.setTooltip(shown and "Crosshair: ON (click to hide)" or "Crosshair: OFF (click to show)")
end

-- runtime 重建后与 layer 实际状态对齐（show 是幂等的）。
if isShown() then
  noctalia.layer.show("overlay")
end

render()

function onClick()
  local shown = not isShown()
  noctalia.state.set("shown", shown)
  if shown then
    noctalia.layer.show("overlay")
  else
    noctalia.layer.hide("overlay")
  end
  render()
end

-- 改设置后 widget 会被重建，这里重新读取 color 同步图标颜色。
function onConfigChanged()
  render()
end
