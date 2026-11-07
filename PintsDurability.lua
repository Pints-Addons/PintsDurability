-- Pint's Durability: a flashing warning when your gear wears down.
--   Your most-worn piece of gear is watched. When it drops to 50%, to 25%, and when something breaks (0%), the screen
--   edges flash (yellow, orange, red), a big warning names the item, and a warning sound plays - once per step.
--   Repairing re-arms the warnings. Option: warn for each piece of gear separately (every item gets its own
--   50% / 25% / broken warnings). /pdur opens the settings; /pdur test shows the three warnings.
local ADDON = ...
local PD = {}
_G.PintsDurability = PD
local GOLD = "|cffd4a017"
local function Print(m) print(GOLD .. "Pint's Durability:|r " .. m) end

local DEFAULTS = { enabled = true, sound = true, flash = true, text = true, loginReminder = true, perItem = false }
-- the steps: at or below this percent (0 = broken), colour of the flash and text, wording
local STEPS = {
	{ at = 50, r = 1.00, g = 0.85, b = 0.10, word = "worn to 50%",  tail = "repair when you can" },
	{ at = 25, r = 1.00, g = 0.50, b = 0.10, word = "down to 25%",  tail = "repair soon" },
	{ at = 0,  r = 1.00, g = 0.15, b = 0.10, word = "BROKEN",       tail = "it gives no stats until repaired" },
}
local db

---------------------------------------------------------------- reading the gear
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }   -- the slots that wear down
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) end
-- lowest percent, the item it's on, and the average
function PD.Scan()
	local low, lowLink, sum, n = nil, nil, 0, 0
	for _, slot in ipairs(SLOTS) do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and not Secret(cur) and not Secret(max) and max > 0 then
			local pct = cur / max * 100
			sum, n = sum + pct, n + 1
			if not low or pct < low then low, lowLink = pct, GetInventoryItemLink("player", slot) end
		end
	end
	return low, lowLink, n > 0 and (sum / n) or nil
end

---------------------------------------------------------------- the warning
local flash, text
local function Build()
	-- screen edges: the game's own low-health glow, tinted
	flash = CreateFrame("Frame", "PintsDurabilityFlash", UIParent)
	flash:SetAllPoints(UIParent); flash:SetFrameStrata("FULLSCREEN_DIALOG"); flash:EnableMouse(false); flash:Hide()
	flash.tex = flash:CreateTexture(nil, "BACKGROUND"); flash.tex:SetAllPoints()
	flash.tex:SetTexture("Interface\\FullScreenTextures\\LowHealth"); flash.tex:SetBlendMode("ADD")
	local ag = flash:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(0.15); a:SetToAlpha(1); a:SetDuration(0.45); a:SetSmoothing("IN_OUT")
	flash.ag = ag
	-- the words, high in the middle
	text = CreateFrame("Frame", "PintsDurabilityText", UIParent)
	text:SetSize(900, 80); text:SetPoint("TOP", UIParent, "TOP", 0, -170); text:SetFrameStrata("FULLSCREEN_DIALOG"); text:Hide()
	text.line1 = text:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); text.line1:SetPoint("TOP")
	local f, _, fl = text.line1:GetFont(); text.line1:SetFont(f, 30, "OUTLINE")
	text.line2 = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); text.line2:SetPoint("TOP", text.line1, "BOTTOM", 0, -6)
	local f2 = text.line2:GetFont(); text.line2:SetFont(f2, 18, "OUTLINE")
end

local hideAt
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self)
	if hideAt and GetTime() >= hideAt then
		hideAt = nil
		if flash then flash.ag:Stop(); flash:Hide() end
		if text then text:Hide() end
		self:Hide()
	end
end)
ticker:Hide()

-- link: one item link, or a list of them (several pieces reaching the same step at once)
function PD.Warn(step, link, quiet)
	local list = type(link) == "table" and link or nil
	if list then
		if #list == 1 then link = list[1]
		elseif #list == 2 then link = list[1] .. " and " .. list[2]
		else link = list[1] .. ", " .. list[2] .. (#list == 3 and (" and " .. list[3]) or (" and " .. (#list - 2) .. " more")) end
	end
	if not flash then Build() end
	local s = STEPS[step]
	if db.flash then
		flash.tex:SetVertexColor(s.r, s.g, s.b, 1)
		flash:SetAlpha(1); flash:Show(); flash.ag:Stop(); flash.ag:Play()
	end
	if db.text then
		local hex = ("|cff%02x%02x%02x"):format(s.r * 255, s.g * 255, s.b * 255)
		text.line1:SetText(hex .. (s.at == 0 and "Gear broken!" or ("Gear " .. s.word)) .. "|r")
		local are = list and #list > 1
		text.line2:SetText((link or "Your gear") .. (s.at == 0 and ((are and " are" or " is") .. " broken - ") or ((are and " are " or " is ") .. s.word .. " - ")) .. s.tail)
		text:Show()
	end
	if db.sound and not quiet then
		PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
		if s.at == 0 then C_Timer.After(0.6, function() PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end) end
	end
	if list and #list > 1 then
		Print(table.concat(list, ", ") .. (s.at == 0 and " are |cffff3020broken|r." or (" are " .. s.word .. ".")))
	else
		Print((link or "your gear") .. (s.at == 0 and " is |cffff3020broken|r." or (" is " .. s.word .. ".")))
	end
	hideAt = GetTime() + (s.at == 0 and 6 or 4)
	ticker:Show()
end

---------------------------------------------------------------- watching
-- warned[i] = true once step i has been shown; cleared again when the gear is above that step (you repaired)
-- each piece separately: { slot, percent, link }
local function ScanEach()
	local out = {}
	for _, slot in ipairs(SLOTS) do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and not Secret(cur) and not Secret(max) and max > 0 then
			out[#out + 1] = { slot, cur / max * 100, GetInventoryItemLink("player", slot) }
		end
	end
	return out
end
local function StepFor(pct)
	local hit = 0
	for i, s in ipairs(STEPS) do if (s.at == 0 and pct <= 0) or (s.at > 0 and pct <= s.at) then hit = i end end
	return hit
end
-- per item: each slot remembers the deepest step it has warned about (and which item it was, so a swap starts fresh)
local function CheckEach(fromLogin)
	db.warnedSlots = db.warnedSlots or {}
	local newHits = {}           -- step -> { links }
	local deepest, worn = 0, 0
	for _, e in ipairs(ScanEach()) do
		local slot, pct, link = e[1], e[2], e[3]
		local rec = db.warnedSlots[slot]
		if rec and rec.link ~= link then rec = nil end
		local step = StepFor(pct)
		local shown = rec and rec.step or 0
		if step < shown then shown = step end          -- repaired: re-armed down to where it is now
		if step > shown then
			newHits[step] = newHits[step] or {}
			table.insert(newHits[step], link or "?")
			if step > deepest then deepest = step end
			shown = step
		end
		if pct <= 50 then worn = worn + 1 end
		db.warnedSlots[slot] = (shown > 0) and { step = shown, link = link } or nil
	end
	if deepest > 0 then
		PD.Warn(deepest, newHits[deepest])
		-- shallower steps reached at the same moment: a line in chat each
		for i = deepest - 1, 1, -1 do if newHits[i] then PD.Warn(i, newHits[i], true) end end
	elseif fromLogin and db.loginReminder and worn > 0 then
		Print(("%d piece%s of gear at 50%% or less - repair when you can."):format(worn, worn == 1 and "" or "s"))
	end
end

local function Check(fromLogin)
	if not db.enabled then return end
	if db.perItem then return CheckEach(fromLogin) end
	local low, link = PD.Scan()
	if not low then return end
	db.warned = db.warned or {}
	-- re-arm the steps you're back above
	for i, s in ipairs(STEPS) do
		local above = (s.at == 0) and (low > 0) or (low > s.at)
		if above then db.warned[i] = nil end
	end
	-- the deepest step reached and not yet shown
	local hit
	for i, s in ipairs(STEPS) do
		local reached = (s.at == 0) and (low <= 0) or (low <= s.at)
		if reached and not db.warned[i] then hit = i end
	end
	if hit then
		for i = 1, hit do db.warned[i] = true end     -- (passing 25% also counts as having passed 50%)
		PD.Warn(hit, link)
	elseif fromLogin and db.loginReminder and low <= 50 then
		-- logging in already worn: a quiet note in chat, no flash
		Print(("your most-worn gear is at %d%% (%s) - repair when you can."):format(math.floor(low + 0.5), link or "?"))
	end
end
PD.Check = Check

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, e, a1)
	if e == "ADDON_LOADED" then
		if a1 ~= ADDON then return end
		PintsDurabilityDB = PintsDurabilityDB or {}
		db = PintsDurabilityDB
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
		self:UnregisterEvent("ADDON_LOADED")
		for _, x in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_CLOSED" }) do
			pcall(self.RegisterEvent, self, x)
		end
	elseif e == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(4, function() Check(true) end)
	else
		-- (durability changes come in bursts; look once it settles)
		if self.pending then return end
		self.pending = true
		C_Timer.After(0.5, function() self.pending = nil; Check(false) end)
	end
end)

---------------------------------------------------------------- settings window
local OPTIONS = {
	{ "enabled",       "Warnings on" },
	{ "perItem",       "Warn for each piece of gear separately",
	  "Every item gets its own 50%, 25% and broken warnings.\nOff: one warning when your most-worn item reaches each step." },
	{ "flash",         "Screen flash" },
	{ "text",          "Big text" },
	{ "sound",         "Sound" },
	{ "loginReminder", "Reminder in chat when you log in" },
}
local opt
local function ResetWarned() db.warned = {}; db.warnedSlots = {} end
function PD.RefreshOptions()
	if not opt then return end
	local on = db.enabled and true or false
	for _, cb in ipairs(opt.checks) do
		cb:SetChecked(db[cb.key] and true or false)
		if cb.key ~= "enabled" then
			cb:SetEnabled(on)
			local c = on and 1 or 0.5
			cb.label:SetTextColor(c, c, c)
		end
	end
end
function PD.Options()
	if opt then opt:SetShown(not opt:IsShown()); return end
	opt = CreateFrame("Frame", "PintsDurabilityOptions", UIParent, "BasicFrameTemplateWithInset")
	opt:SetSize(340, 30 + #OPTIONS * 28 + 50)
	opt:SetPoint("CENTER")
	opt:SetFrameStrata("DIALOG")
	opt:SetMovable(true); opt:EnableMouse(true); opt:SetClampedToScreen(true)
	opt:RegisterForDrag("LeftButton")
	opt:SetScript("OnDragStart", opt.StartMoving)
	opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PintsDurabilityOptions")      -- Escape closes it
	local title = opt.TitleText
	if not title then title = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); title:SetPoint("TOP", 0, -5) end
	title:SetText(GOLD .. "Pint's|r Durability")
	opt.checks = {}
	for i, o in ipairs(OPTIONS) do
		local key, label, tip = o[1], o[2], o[3]
		local cb = CreateFrame("CheckButton", nil, opt, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", (i > 1) and 30 or 16, -30 - (i - 1) * 28)
		local fs = cb.Text or cb.text
		if not fs then fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("LEFT", cb, "RIGHT", 2, 0) end
		fs:SetFontObject("GameFontHighlight")
		fs:SetText(label)
		cb:SetScript("OnClick", function(self)
			db[key] = self:GetChecked() and true or false
			if key == "perItem" or key == "enabled" then
				ResetWarned(); PD.RefreshOptions()
				if db.enabled then Check(false) end
			end
		end)
		if tip then
			cb:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(label, 1, 1, 1)
				GameTooltip:AddLine(tip, nil, nil, nil, true)
				GameTooltip:Show()
			end)
			cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		cb.key, cb.label = key, fs
		opt.checks[i] = cb
	end
	local test = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
	test:SetSize(130, 22); test:SetPoint("BOTTOMLEFT", 16, 12); test:SetText("Test warnings")
	test:SetScript("OnClick", function() SlashCmdList.PINTSDURABILITY("test") end)
	local state = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
	state:SetSize(130, 22); state:SetPoint("BOTTOMRIGHT", -16, 12); state:SetText("Gear status")
	state:SetScript("OnClick", function() SlashCmdList.PINTSDURABILITY("status") end)
	opt:SetScript("OnShow", PD.RefreshOptions)
	PD.RefreshOptions()
	opt:Show()
end

---------------------------------------------------------------- /pdur
SLASH_PINTSDURABILITY1, SLASH_PINTSDURABILITY2 = "/pdur", "/durability"
SlashCmdList.PINTSDURABILITY = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "test" then
		PD.Warn(1, nil, true)
		C_Timer.After(5, function() PD.Warn(2) end)
		C_Timer.After(10, function() PD.Warn(3) end)
		Print("showing the 50%, 25% and broken warnings, five seconds apart.")
	elseif msg == "on" or msg == "off" then
		db.enabled = (msg == "on"); Print("warnings " .. (db.enabled and "on." or "off.")); PD.RefreshOptions()
		if db.enabled then Check(false) end
	elseif msg == "sound" or msg == "flash" or msg == "text" then
		db[msg] = not db[msg]; Print(msg .. " " .. (db[msg] and "on." or "off.")); PD.RefreshOptions()
	elseif msg == "each" or msg == "peritem" then
		db.perItem = not db.perItem; ResetWarned(); PD.RefreshOptions()
		Print("warnings for each piece separately " .. (db.perItem and "on." or "off.")); Check(false)
	elseif msg == "" or msg == "options" or msg == "config" then
		PD.Options()
	else
		local low, link, avg = PD.Scan()
		if not low then Print("no gear that wears down is equipped.") else
			Print(("most-worn: %s at %d%%, average %d%%."):format(link or "?", math.floor(low + 0.5), math.floor((avg or 0) + 0.5)))
		end
		Print("/pdur - settings  |  /pdur test - see the warnings  |  /pdur status  |  /pdur on / off  |  /pdur each")
	end
end

---------------------------------------------------------------- Esc > Options > AddOns, and the add-on menu (WoW Forever)
do
	local panel = CreateFrame("Frame")
	panel.name = "Pint's Durability"
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(GOLD .. "Pint's|r Durability")
	local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetWidth(560); sub:SetJustifyH("LEFT")
	sub:SetText("A flashing warning when your gear wears down to 50%, to 25%, and when something breaks - naming the item.")
	local function Close()
		if HideUIPanel and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		if HideUIPanel and InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
		if HideUIPanel and GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
	end
	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); open:SetSize(180, 24)
	open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20); open:SetText("Open the settings (/pdur)")
	open:SetScript("OnClick", function() Close(); if db then PD.Options() end end)
	local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); test:SetSize(140, 24)
	test:SetPoint("LEFT", open, "RIGHT", 10, 0); test:SetText("Test the warnings")
	test:SetScript("OnClick", function() Close(); if db then SlashCmdList.PINTSDURABILITY("test") end end)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		Settings.RegisterAddOnCategory(cat)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end
-- the add-on menu on the minimap (WoW Forever): click for the settings
function PintsDurability_OnAddonCompartmentClick() if db then PD.Options() end end
function PintsDurability_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
	GameTooltip:AddLine(GOLD .. "Pint's|r Durability")
	local low, link = PD.Scan()
	if low then GameTooltip:AddLine(("Most-worn: %s at %d%%"):format(link or "?", math.floor(low + 0.5)), 1, 1, 1) end
	GameTooltip:AddLine("Click: settings", 0.6, 0.8, 1)
	GameTooltip:Show()
end
function PintsDurability_OnAddonCompartmentLeave() GameTooltip:Hide() end
