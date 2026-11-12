-- Debug ESP (people + high-value items, event-driven, no per-frame updates)
-- GUI: [Rescan] [ESP: ON/OFF] [Items: ON/OFF]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------- CONFIG
local PLAYER_COLOR = Color3.fromRGB(255, 60, 60)    -- normal players
local NPC_COLOR    = Color3.fromRGB(255, 200, 0)    -- normal NPCs
local LAW_COLOR    = Color3.fromRGB(40, 120, 255)   -- police / guards
local ITEM_COLOR   = Color3.fromRGB(255, 215, 0)    -- valuable items
local LAW_KEYWORDS = { "police", "guard", "cop", "sheriff", "swat", "security", "officer" }

local MIN_ITEM_VALUE = 5000   -- only show items worth MORE than this
-- Attribute names or IntValue/NumberValue child names that hold an item's value
local VALUE_NAMES = { "Value", "Price", "Worth", "Cost", "Cash" }
----------------------------------------------------------------

local ENABLED = true
local ITEMS_ENABLED = true
local tracked = {}  -- people: [model] = { hl, bb, label, conns }
local items = {}    -- items:  [inst]  = { bb, label, conns }
local espFolder

local function makeFolder()
	if espFolder then espFolder:Destroy() end
	espFolder = Instance.new("Folder")
	espFolder.Name = "DebugESP"
	espFolder.Parent = workspace.CurrentCamera
end

local function isLaw(text)
	if not text then return false end
	text = string.lower(text)
	for _, kw in ipairs(LAW_KEYWORDS) do
		if string.find(text, kw, 1, true) then return true end
	end
	return false
end

local function getColor(model, plr)
	if plr then
		if plr.Team and isLaw(plr.Team.Name) then return LAW_COLOR end
		return PLAYER_COLOR
	end
	return isLaw(model.Name) and LAW_COLOR or NPC_COLOR
end

local function commas(n)
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (s:gsub("^,", ""))
end

local function makeTag(adornee, color, offsetY, width, textSize)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(width, 32)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = adornee
	bb.Parent = espFolder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.Parent = bb
	return bb, label
end

local function isInCharacter(inst)
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then return true end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

---------------------------------------------------------------- PEOPLE
local function untrack(model)
	local t = tracked[model]
	if not t then return end
	for _, c in ipairs(t.conns) do c:Disconnect() end
	t.hl:Destroy()
	t.bb:Destroy()
	tracked[model] = nil
end

local function track(model)
	if tracked[model] or not model:IsA("Model") then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local plr = Players:GetPlayerFromCharacter(model)
	if plr == LocalPlayer then return end

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.6
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = model
	hl.Enabled = ENABLED
	hl.Parent = espFolder

	local adornee = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local bb, label = makeTag(adornee, PLAYER_COLOR, 3, 220, 14)
	bb.Enabled = ENABLED

	local t = { hl = hl, bb = bb, label = label, conns = {} }
	tracked[model] = t

	local function refresh()
		local color = getColor(model, plr)
		hl.FillColor = color
		hl.OutlineColor = color
		label.TextColor3 = color
		local name = plr and plr.DisplayName or model.Name
		local team = (plr and plr.Team) and (" (" .. plr.Team.Name .. ")") or ""
		label.Text = string.format("%s%s  [%d HP]", name, team, math.floor(hum.Health))
	end
	refresh()

	table.insert(t.conns, hum.HealthChanged:Connect(refresh))
	if plr then
		table.insert(t.conns, plr:GetPropertyChangedSignal("Team"):Connect(refresh))
	end
	table.insert(t.conns, model.AncestryChanged:Connect(function(_, parent)
		if not parent then untrack(model) end
	end))
	table.insert(t.conns, hum.AncestryChanged:Connect(function(_, parent)
		if not parent then untrack(model) end
	end))
end

local function hookPlayer(plr)
	if plr == LocalPlayer then return end
	plr.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid", 10)
		track(char)
	end)
	if plr.Character then track(plr.Character) end
end

for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(plr)
	if plr.Character then untrack(plr.Character) end
end)

---------------------------------------------------------------- ITEMS
local function getItemValue(inst)
	for _, n in ipairs(VALUE_NAMES) do
		local a = inst:GetAttribute(n)
		if type(a) == "number" then return a end
		local v = inst:FindFirstChild(n)
		if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then return v.Value end
	end
	return nil
end

local function getItemPart(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Tool") then return inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart", true) end
	if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
	return nil
end

local function hasTrackedAncestor(inst)
	local p = inst.Parent
	while p and p ~= workspace do
		if items[p] then return true end
		p = p.Parent
	end
	return false
end

local function untrackItem(inst)
	local t = items[inst]
	if not t then return end
	for _, c in ipairs(t.conns) do c:Disconnect() end
	t.bb:Destroy()
	items[inst] = nil
end

local function trackItem(inst)
	if items[inst] then return end
	if not (inst:IsA("Tool") or inst:IsA("Model") or inst:IsA("BasePart")) then return end
	if inst:FindFirstChildOfClass("Humanoid") or isInCharacter(inst) then return end
	if hasTrackedAncestor(inst) then return end

	local value = getItemValue(inst)
	if not value or value <= MIN_ITEM_VALUE then return end
	local part = getItemPart(inst)
	if not part then return end

	local bb, label = makeTag(part, ITEM_COLOR, 1.5, 200, 12)
	bb.Enabled = ENABLED and ITEMS_ENABLED
	label.Text = string.format("◆ %s  $%s", inst.Name, commas(value))

	local t = { bb = bb, label = label, conns = {} }
	items[inst] = t

	-- picked up / destroyed -> remove tag
	table.insert(t.conns, inst.AncestryChanged:Connect(function(_, parent)
		if not parent or not inst:IsDescendantOf(workspace) or isInCharacter(inst) then
			untrackItem(inst)
		end
	end))
	-- value changed -> update or remove
	local function onValueChanged()
		local v = getItemValue(inst)
		if not v or v <= MIN_ITEM_VALUE then
			untrackItem(inst)
		else
			label.Text = string.format("◆ %s  $%s", inst.Name, commas(v))
		end
	end
	table.insert(t.conns, inst.AttributeChanged:Connect(onValueChanged))
	for _, n in ipairs(VALUE_NAMES) do
		local v = inst:FindFirstChild(n)
		if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
			table.insert(t.conns, v.Changed:Connect(onValueChanged))
		end
	end
end

---------------------------------------------------------------- RESCAN (manual only)
local function rescan()
	for m in pairs(tracked) do untrack(m) end
	for i in pairs(items) do untrackItem(i) end
	makeFolder()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Humanoid") then
			if d.Parent then track(d.Parent) end
		else
			trackItem(d)
		end
	end
	local people, valuables = 0, 0
	for _ in pairs(tracked) do people += 1 end
	for _ in pairs(items) do valuables += 1 end
	return people, valuables
end

makeFolder()
rescan()

---------------------------------------------------------------- GUI
local gui = Instance.new("ScreenGui")
gui.Name = "DebugESP_GUI"
gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(170, 112)
frame.Position = UDim2.new(0, 12, 0.4, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
frame.BackgroundTransparency = 0.15
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local layout = Instance.new("UIListLayout", frame)
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder

local ON_COLOR = Color3.fromRGB(40, 160, 80)
local OFF_COLOR = Color3.fromRGB(160, 50, 50)

local function makeButton(text, color, order)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(150, 28)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.LayoutOrder = order
	b.Parent = frame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local rescanBtn = makeButton("Rescan", Color3.fromRGB(60, 100, 200), 1)
local espBtn    = makeButton("ESP: ON", ON_COLOR, 2)
local itemBtn   = makeButton("Items: ON", ON_COLOR, 3)

local function applyVisibility()
	for _, t in pairs(tracked) do
		t.hl.Enabled = ENABLED
		t.bb.Enabled = ENABLED
	end
	for _, t in pairs(items) do
		t.bb.Enabled = ENABLED and ITEMS_ENABLED
	end
end

rescanBtn.MouseButton1Click:Connect(function()
	local p, v = rescan()
	applyVisibility()
	rescanBtn.Text = string.format("%d people, %d items", p, v)
	task.delay(1.5, function() rescanBtn.Text = "Rescan" end)
end)

espBtn.MouseButton1Click:Connect(function()
	ENABLED = not ENABLED
	espBtn.Text = ENABLED and "ESP: ON" or "ESP: OFF"
	espBtn.BackgroundColor3 = ENABLED and ON_COLOR or OFF_COLOR
	applyVisibility()
end)

itemBtn.MouseButton1Click:Connect(function()
	ITEMS_ENABLED = not ITEMS_ENABLED
	itemBtn.Text = ITEMS_ENABLED and "Items: ON" or "Items: OFF"
	itemBtn.BackgroundColor3 = ITEMS_ENABLED and ON_COLOR or OFF_COLOR
	applyVisibility()
end)
