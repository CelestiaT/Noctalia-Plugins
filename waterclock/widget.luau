--!nonstrict
-- WaterClock 栏组件：点击启动/停止计时；未启动时滚轮微调本次时长。
-- 计时状态存进程级 noctalia.state（widget 重建、layer 轮询都读同一份）。

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function durSec()
  local d = noctalia.state.get("wc_dur")
  if type(d) == "number" then
    return d
  end
  return (noctalia.getConfig("duration_min") or 25) * 60
end

local function fmt(s)
  s = math.max(0, math.floor(s + 0.5))
  return string.format("%02d:%02d", s // 60, s % 60)
end

local function render()
  local running = noctalia.state.get("wc_running") == true
  barWidget.setGlyph("droplet")
  barWidget.setGlyphColor(running and "#3ec6e0" or "on_surface")
  if running then
    local start = noctalia.state.get("wc_start")
    local remain = durSec()
    if type(start) == "number" then
      remain = durSec() - (noctalia.nowMs() - start) / 1000
    end
    if remain <= 0 then
      barWidget.setTooltip("WaterClock · done! (click to reset)")
    else
      barWidget.setTooltip("WaterClock · " .. fmt(remain) .. " left (click to stop)")
    end
  else
    barWidget.setTooltip("WaterClock · click to start " .. fmt(durSec()) .. " (scroll to adjust)")
  end
end

-- runtime 重建后与计时状态对齐（show 幂等）
if noctalia.state.get("wc_running") == true then
  noctalia.layer.show("water")
end

render()

local function startTimer()
  if noctalia.state.get("wc_running") == true then
    return
  end
  noctalia.state.set("wc_start", noctalia.nowMs())
  noctalia.state.set("wc_running", true)
  noctalia.layer.show("water")
  render()
end

local function stopTimer()
  noctalia.state.set("wc_running", false)
  noctalia.layer.hide("water")
  render()
end

function onClick()
  if noctalia.state.get("wc_running") == true then
    stopTimer()
  else
    startTimer()
  end
end

-- noctalia msg plugin celestiat/waterclock:toggle all start|stop|set <minutes>
function onIpc(event, payload)
  if event == "start" then
    startTimer()
  elseif event == "stop" then
    stopTimer()
  elseif event == "set" then
    local m = tonumber(payload)
    if m then
      noctalia.state.set("wc_dur", clamp(m * 60, 60, 10800))
      render()
    end
  end
end

function onScroll(axis, steps)
  if axis ~= "vertical" or noctalia.state.get("wc_running") == true then
    return
  end
  -- 向上滚增加时长，一格一分钟
  noctalia.state.set("wc_dur", clamp(durSec() - steps * 60, 60, 10800))
  render()
end

-- 每秒 tick：刷新倒计时 tooltip；计时结束（layer 端已清 state）后图标自动复位
function update()
  render()
end
