local __FILE__=tostring(debugstack(1,2,0):match("(.*):1:")) -- Always check line number in regexp and file
local me,ns=...
--@debug@
--Postal_BlackBookButton
-- SendMailNameEditBox
LoadAddOn("Blizzard_DebugTools")
LoadAddOn("LibDebug")
if LibDebug then LibDebug() end
--@end-debug@
--[===[@non-debug@
local print=function() end
local DevTools_Dump=function() end
--@end-non-debug@]===]
local addon --#MailCommander
local LibInit,minor=LibStub("LibInit",true)
assert(LibInit,me .. ": Missing LibInit, please reinstall")
if minor >=21 then
	addon=LibStub("LibInit"):NewAddon(ns,me,{noswitch=true,profile=true},"AceHook-3.0","AceEvent-3.0","AceTimer-3.0","AceBucket-3.0")
else
	addon=LibStub("LibInit"):NewAddon(me,"AceHook-3.0","AceEvent-3.0","AceTimer-3.0","AceBucket-3.0")
end
local C=addon:GetColorTable()
local L=addon:GetLocale()
local I=LibStub("LibItemUpgradeInfo-1.0")
local fakeLdb={
	type = "data source",
	label = me,
	text=L["Nothing to send"],
	category = "Interface",
	icon="Interface\\MailFrame\\Mail-Icon",
	iconR=1,
	iconG=1,
	iconB=1,
}
local dbDefaults={
	global= {
		dbversion=1,
		toons={
			['*']= {}-- char name plus realm
		},
		requests={ -- what this toon need: requests[toon][itemid]){itemdata}
			['**']={}
		},
		disabled={
			['*']={   --itemId
				['*'] = { --sender
						--receiver toon
				}
			}
		},
		cap={ -- This receeiver will be deleted once received "cap" items
			['*']= { -- char name plus realm
				--itemId = number
			}

		},
		keep={ -- This toon will keep at least "keep" items
			['*']= { -- char name plus realm
				--itemId = number
				['*'] = 0
			}
		},
		ignored={},
		lastReceiver='NONE'
	}
}
local LDB=LibStub:GetLibrary("LibDataBroker-1.1",true)
local ldb= LDB:NewDataObject(me,fakeLdb) --#ldb
local icon = LibStub("LibDBIcon-1.0",true)

-- upvalues
local SetItemButtonTexture,UIDropDownMenu_AddButton=SetItemButtonTexture,UIDropDownMenu_AddButton
local GetProfessions,GetUnitName,UnitClass,GetProfessionInfo,UnitLevel=GetProfessions,GetUnitName,UnitClass,GetProfessionInfo,UnitLevel
local ClearCursor,CreateFrame,print,GetCursorInfo=ClearCursor,CreateFrame,print,GetCursorInfo
local ButtonFrameTemplate_HidePortrait,SendMailFrame,UIParent,InboxFrame=ButtonFrameTemplate_HidePortrait,SendMailFrame,UIParent,InboxFrame
local	UIDropDownMenu_CreateInfo,UIDropDownMenu_SetWidth=UIDropDownMenu_CreateInfo,UIDropDownMenu_SetWidth
local UIDropDownMenu_Initialize,UIDropDownMenu_SetText=UIDropDownMenu_Initialize,UIDropDownMenu_SetText
local PanelTemplates_SetNumTabs,PanelTemplates_SetTab=PanelTemplates_SetNumTabs,PanelTemplates_SetTab
local SetItemButtonDesaturated,SetItemButtonCount,SetItemButtonStock=SetItemButtonDesaturated,SetItemButtonCount,SetItemButtonStock
local GetItemCount=GetItemCount
local MailFrame=MailFrame
local wipe,tinsert,pairs,ipairs,strcmputf8i=wipe,tinsert,pairs,ipairs,strcmputf8i
local PanelTemplates_DisableTab,PanelTemplates_EnableTab=PanelTemplates_DisableTab,PanelTemplates_EnableTab
local minibag="Interface\\PaperDollInfoFrame\\UI-GearManager-ItemIntoBag"
local undo="Interface\\PaperDollInfoFrame\\UI-GearManager-Undo"
local ignore="Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Opaque"
local ignore2="Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent"
local KEY_BUTTON1 = "\124TInterface\\TutorialFrame\\UI-Tutorial-Frame:12:12:0:0:512:512:10:65:228:283\124t" -- left mouse button
local KEY_BUTTON2 = "\124TInterface\\TutorialFrame\\UI-Tutorial-Frame:12:12:0:0:512:512:10:65:330:385\124t" -- right mouse button
local CTRL_KEY_TEXT,SHIFT_KEY_TEXT=CTRL_KEY_TEXT,SHIFT_KEY_TEXT
local FILTER,SEND,NEED=FILTER,SEND_LABEL,NEED
local kpairs=addon:getKpairs()
-- locals
local slots=16
local db
local mcf
local INEED=1
local ISEND=2
local IFILTER=3
local currentRequester='NONE'
local currentReceiver='NONE'
local lastReceiver
local thisFaction
local thisRealm
local thisToon
local currentTab=0
local dirty=true
local shouldsend
local oldshouldsend
local sendable={} -- For each toon, it's true if the current one has at least one object to send
local toonTable={} -- precaculated toon table for initDropDown to avoid bursting memory
local toonIndex={}
local tobesent={}
local sending=setmetatable({},{__index=function() return 0 end})
-- ldb extension
function ldb:Update()
	if oldshouldsend ~= shouldsend then
		ldb.text=shouldsend and C(L["You have items to send"],"GREEN") or C(L["Nothing to send"],"SILVER")
		local button =icon:GetMinimapButton(me)
		if not button then return end
		if shouldsend then
			button.icon:SetVertexColor(0,1,0)
		else
			button.icon:SetVertexColor(1,1,1)
		end
	end
end
function ldb:OnClick(button)
	if button=="RightButton" then
		addon:Gui()
		return
	end
	if mcf:IsVisible() then
		mcf:Hide()
	else
		addon:OpenConfig()
	end
end
function ldb:OnTooltipShow(...)
	if not shouldsend then
		self:AddLine(L["Nothing to send"],C:Silver())
	else
		self:AddLine(L["Items available for:"],C:Green())
		for name,data in pairs(db.toons) do
			if sendable[name] and name~=thisToon and toonTable[name] then
				self:AddLine(toonTable[name].text)
				for _,d in pairs(db.requests[name]) do
					local c=GetItemCount(d.i)
					if c and c >0 then
						self:AddDoubleLine("   " .. d.l,c,nil,nil,nil,C:Green())
					end
				end
			end
		end
	end
	self:AddDoubleLine(KEY_BUTTON1,L['Open requester'],nil,nil,nil,C:Green())
	self:AddDoubleLine(KEY_BUTTON2,L['Open configuration'],nil,nil,nil,C:Green())
	if thisFaction=="Neutral" then
		self:AddLine(L["ATTENTION: Neutral characters cant use mail"],C:Orange())
	end
end
local function SetItemCounts(frame,cap,keep,stock)
		if not frame then return end
		if cap and cap >0 then
			--frame.Need:SetFormattedText(MERCHANT_STOCK, need)
			frame.Cap:SetText(cap)
			frame.Cap:Show()
		else
			frame.Cap:Hide()
		end
		if keep and keep >0 then
			--frame.Keep:SetFormattedText(MERCHANT_STOCK, keep)
			frame.Keep:SetText(keep)
			frame.Keep:Show()
		else
			frame.Keep:Hide()
		end
		if stock and stock > -1 then
			frame.Stock:SetText(stock>9999 and '*' or stock)
			frame.Stock:Show()
		else
			frame.Stock:Hide()
		end
	end
--addon:SetCustomEnvironment(ns)
function addon:SetDbDefaults(default)
	default.profile.ldb={hide=false}
	return true
end
local function IsDisabled(itemid)
	if not itemid then return false end
	if currentTab==INEED or currentTab ==ISEND then
		if db.disabled[itemid]['ALL'][currentRequester] then return 2 end
	end
	if currentTab ==ISEND then
		return db.disabled[itemid][thisToon][currentReceiver] and 1 or false
	end
	return false
end
local function IsIgnored(toon,ignorelevel)
	if not toon then return false end
	if toon == thisToon then return false end
	return db.ignored[toon] or (not ignorelevel and addon:GetNumber("MINLEVEL") > toonTable[toon].level)
end

local function AddButton(i,data,section)
	local hide=type(data)=='boolean' and not data
	if not mcf.Items[i] then
		if hide then return 1 end
		mcf.Items[i]=CreateFrame("Frame",nil,mcf,"MailCommanderItemTemplate")
	end
	local frame=mcf.Items[i]
	if hide then
		frame:Hide()
		return 1
	end
	if (i % 2) ==0 then --even
		frame:SetPoint("TOPLEFT",mcf.Items[i-1],"TOPRIGHT",10,0)
	elseif i>1 then -- odd
		frame:SetPoint("TOPLEFT",mcf.Items[i-2],"BOTTOMLEFT",0,20)
--	else -- first one
--		frame:SetPoint("TOPLEFT",mcf,"TOPLEFT",10,-60)
	end
	frame.ItemButton:SetAttribute("section",section)
	frame.ItemButton.MailCommanderDragTarget=true
	if section=="items" then
		if type(data)=='table'  then
			frame.ItemButton:SetAttribute("itemlink",data.l)
			SetItemButtonTexture(frame.ItemButton,data.t)
			frame.Name:SetText(data.l)
			if IsDisabled(data.i) then
				frame.ItemButton.Disabled:Show()
			else
				frame.ItemButton.Disabled:Hide()
			end
			addon:SetLimit(data.i)
			local count=GetItemCount(data.i)
			local cap=(db.cap[currentTab==INEED and currentRequester or currentReceiver][data.i])
			local keep=db.keep[thisToon][data.i] or 0
			count=count-keep-sending[data.i]
			if tobesent[data.i] then
				count=tobesent[data.i]-sending[data.i]
			end
			if cap and count >cap then
				count=cap
			elseif count <0 then
				count=0
			end
			SetItemCounts(frame.ItemButton,cap,keep,count)
			SetItemButtonDesaturated(frame.ItemButton,count and count < 1 and currentTab==ISEND)
		else
			frame.ItemButton:SetAttribute("itemlink",nil)
			SetItemButtonTexture(frame.ItemButton,nil)
			SetItemButtonDesaturated(frame.ItemButton,false)
			frame.ItemButton.Disabled:Hide()
			SetItemCounts(frame.ItemButton)
			if type(data) =='nil' then
				frame.Name:SetText(L["Drag here do add an item"])
				frame.ItemButton.MailCommanderDragTarget=true
			else
				frame:Hide()
				return 1
			end
		end
	elseif section=="toons" then
		local name=data
		data=toonTable[name]
		frame.ItemButton:SetAttribute('toon',name)
		if IsIgnored(name,true) then
			frame.ItemButton.Disabled:Show()
		else
			frame.ItemButton.Disabled:Hide()
		end
		frame.Name:SetText(data.text)
		SetItemButtonTexture(frame.ItemButton,"Interface\\ICONS\\ClassIcon_"..data.class)
		SetItemCounts(frame.ItemButton)
		frame:Show()
		return 1
	end
	frame:Show()
	return 1
end
function addon:CloseTip()
	if _G.GameTooltip then GameTooltip:Hide() end
end
local function loadSelf(level)
	local p1,p2=GetProfessions()
	thisFaction=UnitFactionGroup("player")
	thisRealm=GetRealmName()
	thisToon=GetUnitName("player")..'-'..thisRealm
	ns.localizedClass,ns.class=UnitClass("player")
	if p1 then
		local name,icon,level=GetProfessionInfo(p1)
		db.toons[thisToon].p1=name .. "(" .. level ..")\n"
	end
	if p2 then
		local name,icon,level=GetProfessionInfo(p2)
		db.toons[thisToon].p2=name .. "(" .. level ..")\n"
	end
	db.toons[thisToon].localizedClass=ns.localizedClass
	db.toons[thisToon].level=level or UnitLevel("player")
	db.toons[thisToon].class=ns.class
	db.toons[thisToon].faction=thisFaction
	db.toons[thisToon].realm=thisRealm
end
local function mkkey(realm,name)
	local r,k=pcall(strconcat,realm==thisRealm and ' ' or realm,name)
	return strlower(k)
end
local function toonSort(a,b)
	local k1=mkkey(toonTable[a].realm,a)
	local k2=mkkey(toonTable[b].realm,b)
	return strcmputf8i(k1,k2)<0
end
local function loadDropList()
	wipe(toonTable)
	wipe(toonIndex)
	for name,data in pairs(db.toons) do
		if not data.faction or data.faction==thisFaction then
			toonTable[name]={
				text=data.class and format("|c%s%s (%s %d)|r",_G.RAID_CLASS_COLORS[data.class].colorStr,name,data.localizedClass,data.level) or name,
				tooltip=(data.p1 and data.p1 .."\n" or "") .. (data.p2 and data.p2 .."\n" or ""),
				realm=data.realm,
				level=data.level,
				class=data.class
			}
			data.text=toonTable[name].text
			tinsert(toonIndex,name)
		end
	end
	table.sort(toonIndex,toonSort)
end
function addon:InitData()
	loadSelf()
	currentRequester=thisToon
	currentReceiver=db.lastReceiver or 'NONE'
	if  _G.DataStore then
		local d=_G.DataStore
		local delay=60*60*24*30 -- does not import old toons
		local realmList=_G.DataStore:GetRealmsConnectedWith(thisRealm)
		tinsert(realmList,thisRealm)
		for _,realm in pairs(realmList) do
			for name,key in pairs(d:GetCharacters(realm)) do
				name=name..'-'..realm
				if name~=thisToon then -- Do not overwrite current data with (possibly) stale data
					if d:IsEnabled("DataStore_Characters") then
						db.toons[name].faction=d:GetCharacterFaction(key)
						db.toons[name].localizedClass,db.toons[name].class=d:GetCharacterClass(key)
						db.toons[name].level=d:GetCharacterLevel(key)
						db.toons[name].realm=realm
						if d:IsEnabled("DataStore_Crafts") then
							local l,_,_,n=d:GetProfession1(key)
							if l and l>0 then
								db.toons[name].p1=format("%s (%d)",n,l)
							end
							local l,_,_,n=d:GetProfession2(key)
							if l and l>0 then
								db.toons[name].p2=format("%s (%d)",n,l)
							end
						end
					end
				end
			end
		end
	end
	loadDropList()
	--DevTools_Dump(toonTable)
	self:ScheduleRepeatingTimer("RefreshSendable",2)
end
function addon:ApplyMINIMAP(value)
	if value then
		icon:Hide(me)
	else
		icon:Show(me)
	end
	self.db.profile.ldb={hide=value}
end
function addon:ApplyMINLEVEL(value)
	loadDropList()
	if MailCommanderFrame:IsVisible() then self:UpdateMailCommanderFrame() end

end
local function dragStart(frame,button)
	print("DragStart",frame:GetName(),button)
	local fname=frame:GetName()
	if fname=="TradeSkillSkillIcon" then
	--@debug@
		print(GameTooltipTextLeft1:GetText(),TradeSkillFrame.selectedSkill,GetTradeSkillItemLink(TradeSkillFrame.selectedSkill))
	--@end-debug@
		PickupItem(addon:GetItemID(GetTradeSkillItemLink(TradeSkillFrame.selectedSkill)))
	elseif fname:find("TradeSkillReagent") then
--@debug@
		print(GameTooltipTextLeft1:GetText(),TradeSkillFrame.selectedSkill,GetTradeSkillReagentItemLink(TradeSkillFrame.selectedSkill, frame:GetID()))
--@end-debug@
		PickupItem(addon:GetItemID(GetTradeSkillReagentItemLink(TradeSkillFrame.selectedSkill, frame:GetID())))
	else
		local itemName, ItemLink = GameTooltip:GetItem();
		--@debug@
		print(GameTooltipTextLeft1:GetText(),itemName,ItemLink,GetItemInfo(GameTooltipTextLeft1:GetText()))
		--@end-debug@
	end
end
local function dragStop(frame)
--@debug@
	print("DragStop")
--@end-debug@
	frame:RegisterForDrag()
	frame:SetScript("OnDragStart",nil)
	frame:SetScript("OnDragStop",nil)
	local dest=GetMouseFocus()
--@debug@
	if type(dest)=="table"  and dest.GetName then
		print("Drag Stoppped on",dest:GetName())
	end
--@end-debug@
	if type(dest)=="table" and dest.MailCommanderDragTarget then
		return
	else
		ClearCursor()
	end

end
local function dragManage(tip)
	print("DragManage",tip)
	if CursorHasItem() then return end
	local frame=tip:GetOwner()
	if not frame:GetScript("OnDragStart") then
		if mcf:IsShown() and currentTab==INEED then
			frame:SetScript("OnDragStart",dragStart)
			frame:SetScript("OnDragStop",dragStop)
			frame:RegisterForDrag("LeftButton")
		end
	end
end
function addon:OnInitialized()
--@debug@
	local _,version=LibStub("LibInit")
	print("Using LibInit version",version)
--@end-debug@
	-- AceDb does not support connected realms, so I am using a namespace
	local realmkey=GetRealmName()
	local r=GetAutoCompleteRealms()
	if r then
		table.sort(r)
		realmkey=strconcat(unpack(r))
	end
	local newdb=self.db:GetNamespace(realmkey,true)
	if not newdb then
		db=self.db:RegisterNamespace(realmkey,dbDefaults).global
	else
		wipe(newdb)
		newdb:RegisterDefaults(dbDefaults)
		db=newdb.global
	end
	--DevTools_Dump(db.toons)
	local olddb=self.db.factionrealm
	if rawget(olddb,'toons') then
		self:Popup("MailCommander\n Data from beta were imported, but you need to check them",10)
		local realm=GetRealmName()
		-- Toons list
		if type(olddb.toons)=="table" then
			for name,data in pairs(olddb.toons) do
				db.toons[name..'-'..realm]=CopyTable(data)
			end
		end
		if type(olddb.requests)=="table" then
			-- Requests list
			for name,data in pairs(olddb.requests) do
				db.requests[name..'-'..realm]=CopyTable(data)
			end
		end
		olddb.toons=nil
		olddb.requests=nil
		olddb.disable=nil
	end
	self.namespace=db
	--DevTools_Dump(db.toons)
	if icon then
		icon:Register(me,ldb,self.db.profile.ldb)
	end
	self:AddBoolean("MAILBODY",false,L["Fill mail body"],L["Fill mail body with a detailed list of sent item"])
	self:AddBoolean("MINIMAP",false,L["Hide minimap icon"],L["If you hide minimap icon, use /mac gui to access configuration and /mac requests to open requests panel"])
	self:AddSlider("MINLEVEL",90,1,100,L["Characters minimum level"],L["Only consider characters above this level"])
	self:AddOpenCmd("reset","Reset",L["Erase all stored data"])
	self:AddOpenCmd("requests","OpenConfig",L["Open requests panel"])
	self:AddBoolean("ALLSEND",false,format(L["Show all characters in %s tab"],SEND),L["Show all toons regardless if they have items to send or not"])
--@debug@
	self:AddBoolean("DRY",false,"Disable mail sending")
--@end-debug@

	self:ScheduleTimer("InitData",2)
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:RegisterEvent("MAIL_SHOW","CheckTab")
	self:RegisterEvent("MAIL_CLOSED","CheckTab")
	self:RegisterEvent("MAIL_SEND_SUCCESS","MailEvent")
	self:RegisterEvent("MAIL_FAILED","MailEvent")
	self:RegisterEvent("MAIL_LOCK_SEND_ITEMS","MailEvent")
	self:RegisterEvent("MAIL_UNLOCK_SEND_ITEMS","MailEvent")
	self:RegisterEvent("MAIL_SEND_INFO_UPDATE","MailEvent")
	self:RegisterEvent("MAIL_SEND_COD_CHANGED","MailEvent")
	self:RegisterEvent("MAIL_SEND_MONEY_CHANGED","MailEvent")
	self:RegisterEvent("MAIL_LOCK_SEND_ITEMS","MailEvent")

	self:RegisterEvent("BAG_UPDATE_DELAYED",function(...) dirty=true end)
	self:RegisterBucketEvent({'PLAYER_SPECIALIZATION_CHANGED','TRADE_SKILL_UPDATE'},5,'TRADE_SKILL_UPDATE')
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:SecureHookScript(_G.SendMailFrame,"OnShow","OpenSender")
	self:HookScript(_G.SendMailFrame,"OnHide","CloseChooser")
	--@debug@
	self:RegisterEvent("MAIL_INBOX_UPDATE","MailEvent")
	self:RegisterEvent("UPDATE_PENDING_MAIL","MailEvent")
	self:SecureHookScript(_G.InboxFrame,"OnShow",print)
	self:HookScript(_G.InboxFrame,"OnHide",print)
	--@end-debug@
	mcf=CreateFrame("Frame","MailCommanderFrame",UIParent,"MailCommander")
	addon.xdb=db
	--@debug@
	do
		local OldHook=GameTooltip:GetScript("OnShow")
		if OldHook then
			GameTooltip:HookScript("OnShow",function(...) OldHook(...) dragManage(...) end)
		else
			GameTooltip:HookScript("OnShow",dragManage)
		end
	end
	--@end-debug@
	return true
end

function addon:PLAYER_LEVEL_UP(event,level)
	loadSelf(level)
	loadDropList()
	if MailCommanderFrame:IsVisible() then self:UpdateMailCommanderFrame() end
end
function addon:TRADE_SKILL_UPDATE()
	self:ScheduleTimer(loadSelf,5)
end
function addon:CheckTab(event)
	if event =="MAIL_SHOW" then
		--PanelTemplates_EnableTab(mcf,ISEND)
	else
		--PanelTemplates_DisableTab(mcf,ISEND)
		PanelTemplates_SetTab(mcf,INEED)
		StackSplitFrame:Hide()
		wipe(tobesent)
	end
end
function addon:OpenConfig(tab)
--@debug@
	print("Opening config")
--@end-debug@
	OpenAllBags(mcf)
	mcf:SetParent(UIParent)
	mcf:ClearAllPoints()
	mcf:SetPoint("CENTER")
	PanelTemplates_SetTab(mcf,INEED)
	currentTab=mcf.selectedTab
	addon:UpdateMailCommanderFrame()
	mcf:Show()
end
function addon:OpenSender(tab)
	if ( not SendMailFrame:IsVisible() ) then
		return;
	end
	mcf:ClearAllPoints()
	mcf:SetPoint("TOPLEFT",MailFrame,"TOPRIGHT",0,0)
	PanelTemplates_SetTab(mcf,2)
	PanelTemplates_SetTab(mcf,ISEND)
	currentTab=mcf.selectedTab
	addon:UpdateMailCommanderFrame()
	mcf:Show()
end
function addon:CloseChooser()
	mcf:Hide()
end
function addon:OnLoad(frame)
	mcf=frame
	frame:SetClampedToScreen()
	--MCF:EnableMouse(true)
	--MCF:SetMovable(true)
	frame.Send:SetText(L["Send All"])
	frame.Send.tooltip="tooltip"
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart",function(frame) frame:StartMoving() end)
	frame:SetScript("OnDragStop",function(frame) frame:StopMovingOrSizing() end)
	ButtonFrameTemplate_HidePortrait(frame)
	UIDropDownMenu_SetWidth(frame.Filter, 150);
	UIDropDownMenu_Initialize(frame.Filter, function(...) self:InitializeDropDown(...) end );
	UIDropDownMenu_SetText(frame.Filter,self:GetFilter())
	PanelTemplates_SetNumTabs(frame, 3);
	PanelTemplates_SetTab(frame, 1);
	mcf.tabNEED.tooltip=L["Configures REQUESTS.\n Set what each toon needs"]
	mcf.tabSEND.tooltip=L["Configures sendings.\n Manages what each toon will send to the others"]
	mcf.tabFILTER.tooltip=L["Manages which toon are considered as possible requesters"]
	local texture=mcf:CreateTexture(nil,"BACKGROUND")
	--texture:SetTexture("Interface\\QuestFrame\\QuestBG")
	texture:SetTexture("Interface\\MailFrame\\UI-MailFrameBG",false)
	texture:SetPoint("TOP",0,-20)
	texture:SetPoint("BOTTOM",0,33)
	texture:SetPoint("LEFT",0,0)
	texture:SetPoint("RIGHT",0,0)
	texture:SetTexCoord(0,0.6,0,0.7)
	MailCommanderFrameAllText:SetText(SHOW.."\n" ..ALL)

end
function addon:GetFilter()
	if currentTab==INEED then
		currentRequester = currentRequester or thisToon ..'-'..thisRealm
		return currentRequester
	else
		if not sendable[currentReceiver] then
			if sendable[currentRequester] then
				currentReceiver=currentRequester
			else
				currentReceiver=nil
			end
		end
		currentReceiver=currentReceiver or next(sendable) or  'NONE'
		if currentReceiver=='NONE' and self:GetBoolean("ALLSEND") then
			for name,data in pairs(toonTable) do
				if data.level >= self:GetNumber("MINLEVEL") then
					currentReceiver=name
					break
				end
			end
		end
		if not self:GetBoolean("ALLSEND") and not sendable[currentReceiver] then
			currentReceiver='NONE'
		else
			if currentReceiver==thisToon then currentReceiver='NONE' end
		end
		return currentReceiver
	end
end
function addon:SetFilter(info,name)
	if currentTab==INEED then
		currentRequester=name
	else
		lastReceiver=currentReceiver
		currentReceiver=name
	end
	UIDropDownMenu_SetText(mcf.Filter,name)
	self:UpdateMailCommanderFrame()
end
function addon:RefreshSendable()
	if dirty and not InCombatLockdown() then
		shouldsend=false
		wipe(sendable)
		for name,_ in pairs(db.requests) do
			if name ~= thisToon then
				if rawget(db.toons,name) then
					for _,d in ipairs(db.requests[name]) do
						local count=GetItemCount(d.i)
						if count and count > 0 then
							sendable[name]=true
							shouldsend=true
							break
						end
					end
				end
			end
		end
		dirty=false
		ldb:Update()
	end
end
function addon:InitializeDropDown(this,level,menulist)
	local mcf=MailCommanderFrame
	local info = UIDropDownMenu_CreateInfo();
	local current = addon:GetFilter();
	local function SetFilter(...)
		self:SetFilter(...)
	end
	UIDropDownMenu_SetText(mcf.Filter,current=='NONE' and NONE or current)
	local padding
	local realm=''
	info.notCheckable=nil
	info.func = SetFilter
	info.isTitle=nil
	info.disabled=nil
	for _,name in ipairs(toonIndex) do
		local data=toonTable[name]
		if not IsIgnored(name) and (currentTab==INEED or name~=thisToon) then
			if currentTab==INEED or sendable[name] or self:GetBoolean("ALLSEND") then
			-- Per realm header
				if realm~=data.realm then
					realm=data.realm
					info.text=realm
					info.isTitle=true
					info.notCheckable=true
					info.leftPadding=nil
					UIDropDownMenu_AddButton(info)
				end
				info.isTitle=nil
				info.notCheckable=nil
				info.disabled=nil
				info.leftPadding=15
				info.checked=strcmputf8i(current,name)==0
				if info.checked then
					UIDropDownMenu_SetText(mcf.Filter,name)
				end
				info.arg1=name
				info.tooltipTitle=TRADE_SKILLS
				info.tooltipOnButton=true
				info.text=data.text
				info.tooltipText=data.tooltip
				UIDropDownMenu_AddButton(info)
			end
		end
	end
end

function addon:RenderButtonList(store,page)
	--@debug@
	print("Refreshing view")
	--@end-debug@
	mcf.store=store
	if currentRequester==thisToon then mcf.Delete:Disable() else mcf.Delete:Enable() end
	local total=#store
	page=page or 0
	local nextpage=false
	local section =mcf:GetAttribute("section") or "items"
	local first=page*slots
	local last=(page+1)*slots
	local i=1
	for ix,data in pairs(store) do
		if currentTab==INEED or
			(currentTab==IFILTER and toonTable[data].level >= self:GetNumber("MINLEVEL")) or
			(currentTab==ISEND and (self:GetBoolean('ALLSEND') or tonumber(GetItemCount(data.i) or 0) >0)) then
			if i>first then
				if i > last then
					nextpage=true
					break
				else
					AddButton(i-page*slots,data,section)
				end
			end
			i=i+1
		end
	end
	if currentTab==INEED then
		if i-page*slots <=slots then
			i=i+AddButton(i-page*slots,nil,section)
		else
			nextpage=true
		end
	end
	i=i-page*slots
	if mcf.Items then
		while i<=#mcf.Items do
			i=i+AddButton(i,false,section)
		end
	end
	mcf.PageText:SetFormattedText(PAGE_NUMBER,page+1)
	if page>0 then
		mcf.PrevPageButton:SetID(page-1)
		mcf.PrevPageButton:Enable()
		mcf.PrevPageButton.Text:SetTextColor(C.Yellow())
	else
		mcf.PrevPageButton:Disable()
		mcf.PrevPageButton.Text:SetTextColor(C.Silver())
	end
	if nextpage then
		mcf.NextPageButton:SetID(page+1)
		mcf.NextPageButton:Enable()
		mcf.NextPageButton.Text:SetTextColor(C.Yellow())
	else
		mcf.NextPageButton:Disable()
		mcf.NextPageButton.Text:SetTextColor(C.Silver())
	end
end
function addon:RenderNeedBox()
	mcf.Send:Hide()
	mcf.All:Hide()
	mcf.Delete:Show()
	mcf.Filter:Show()
	mcf.Info:Hide()
	mcf.NameText:SetText(L["Items needed by selected toon"])
	local toon=self:GetFilter()
	mcf:SetAttribute("section","items")
	self:RenderButtonList(db.requests[toon])
	UIDropDownMenu_SetText(mcf.Filter,toon)
end
function addon:RenderFilterBox()
	mcf.Info:Show()
	mcf.Info:SetFormattedText(L["Characters under level |cffff9900%d|r are not shown"],self:GetNumber("MINLEVEL"))
	mcf.NameText:SetText(L["Enable or disable toons"])
	mcf.Send:Hide()
	mcf.All:Hide()
	mcf.Filter:Hide()
	mcf.Delete:Hide()
	mcf:SetAttribute("section","toons")
	self:RenderButtonList(toonIndex)
end
function addon:RenderSendBox()
	mcf.Send:Show()
	mcf.All:SetChecked(self:GetBoolean("ALLSEND"))
	mcf.All:Show()
	mcf.All.tooltip=L["Show all toons regardless if they have items to send or not"]
	mcf.Delete:Hide()
	mcf.Filter:Show()
	mcf.Info:Hide()
	mcf.NameText:SetText(L["Items you can send to selected toon"])
	local toon=self:GetFilter()
	mcf:SetAttribute("section","items")
	self:RenderButtonList(db.requests[toon])
	UIDropDownMenu_SetText(mcf.Filter,toon)
end
function addon:OnSendEnter(this)
	local tip=GameTooltip
	tip:SetOwner(this,"ANCHOR_CURSOR")
	tip:AddLine(L["Send all enabled items (no confirmation asked)"])
	tip:Show()
end
function addon:OnAllClick(this,value)
	self:SetBoolean("ALLSEND",value)
	return self:UpdateMailCommanderFrame()
end
function addon:OnDeleteEnter(this)
	local tip=GameTooltip
	tip:SetOwner(this,"ANCHOR_CURSOR")
	tip:AddLine(L["Remove the selected toon from the droplist"])
	tip:Show()
end
function addon:OnHelpEnter(this)
	local tip=GameTooltip
	tip:SetOwner(this,"ANCHOR_BOTTOMRIGHT")
	if currentTab==INEED then
		tip:AddLine(L["Mail Commander request configuration"],C:Orange())
		tip:AddLine(L["Drag items to define what the selected toon NEEDS"],C:Silver())
		tip:AddLine(L["You can drag items from: merchants,tradeskills and obviously your bags"])
	elseif currentTab==ISEND then
		tip:AddLine(L["Mail Commander bulk mail sending"],C:Orange())
		tip:AddLine(L["From this panel you can send requested items"],C:Silver())
		tip:AddLine(L["Items that you dont have are not shown"],C:Silver())
		tip:AddLine(format(L["Use \"%s\" button to send all items at once (max %d items at a time)"],L["Send All"],ATTACHMENTS_MAX_SEND),C:Silver())
	elseif currentTab==IFILTER then
		tip:AddLine(L["Mail Commander character selection"],C:Orange())
		tip:AddLine(L["You can selectively disable character"],C:Silver())
		tip:AddLine(L["Use gui (/mac gui) to change minimum level"],C:Silver())
	end
	if currentTab ~= IFILTER then
		tip:AddLine(L["Item buttons numbers:"],C:Orange())
		tip:AddDoubleLine(L["Top left corner"],L["Minimum stock you want to keep on "] .. thisToon,C.Silver.r,C.Silver.g,C.Silver.b,C:Yellow())
		if currentTab==INEED then tip:AddDoubleLine(L["Set it with"],CTRL_KEY_TEXT .. KEY_BUTTON1,C:Yellow()) end
		tip:AddDoubleLine(L["Top right corner"],L["Maximum amount you want to send to "] .. currentRequester,C.Silver.r,C.Silver.g,C.Silver.b,C:Green())
		if currentTab==INEED then tip:AddDoubleLine(L["Set it with"],SHIFT_KEY_TEXT .. KEY_BUTTON1,C:Yellow()) end
		tip:AddDoubleLine(L["Bottom right corner"],L["Sendable amount (after modifications)"],C.Silver.r,C.Silver.g,C.Silver.b,C:White())

	end
	if thisFaction=="Neutral" then
		tip:AddLine(L["ATTENTION: Neutral characters cant use mail"],C:Orange())
	end

	tip:Show()
end
function addon:SetLimit(itemInBag)
	if not itemInBag then return end
	local qt=0
	local keep=db.keep[thisToon][itemInBag] or 0
	local cap=db.cap[currentReceiver][itemInBag] or 9999
	local qt=GetItemCount(itemInBag,false)-keep
	if qt > cap then
		qt =cap
	elseif qt<0 then
		qt=0
	end
	tobesent[itemInBag]=qt
end
local function DeleteStore(popup,toon)
	local key=_G.DataStore:GetCharacter(toon)
	_G.DataStore:DeleteCharacter(toon)
	currentRequester='NONE'
	addon:UpdateMailCommanderFrame()
end
function addon:DeleteStore()
	if currentRequester then
		self:Popup(format(L["Do you want to delete %1$s\nfrom DataStore, too?"].."\n"..
					L["If you dont remove %1$s also from DataStore, it will be back"],currentRequester),
					DeleteStore,function() currentRequester='NONE' addon:UpdateMailCommanderFrame() end,currentRequester)
	end
end
local function DeleteToon(popup,toon)
	wipe(db.toons[toon])
	wipe(db.requests[toon])
	wipe(toonTable[toon])
	for itemid,_ in pairs(db.disabled) do
		wipe(db.disabled[itemid][toon])
	end
	local d=_G.DataStore
	if d and d:IsEnabled("DataStore_Character") then
		addon:ScheduleTimer("DeleteStore",0.5)
	else
		currentRequester='NONE'
		addon:UpdateMailCommanderFrame()
	end
end
function addon:OnDeleteClick(this,button)
	local info=rawget(db.toons,currentRequester)
	if info then
		self:Popup(format(L["Do you want to delete\n%s?"],info.text),DeleteToon,function() end,currentRequester)
	end
end
local FillMailSlot
FillMailSlot=function(bag,slot)
	local count,locked=select(2,GetContainerItemInfo(bag,slot))
	if locked or not count then
		addon:ScheduleTimer(FillMailSlot,0.01,bag,slot)
	else
		UseContainerItem(bag,slot)
	end
end
-- Da riscrivere
local sortable={}
function addon:SearchItem(itemId)
	if IsDisabled(itemId) then return false end
	wipe(sortable)
	for bagId=0,NUM_BAG_SLOTS do
		for slotId=1,GetContainerNumSlots(bagId) do
			local itemInBag=GetContainerItemID(bagId,slotId)
			if itemInBag and itemInBag==itemId then
				tinsert(sortable,format("%05d:%s:%s",10000-select(2,GetContainerItemInfo(bagId,slotId)),bagId,slotId))
			end
		end
	end
	if #sortable>0 then
		table.sort(sortable)
		for i=1,#sortable do
			local qt,bagId,slotId=strsplit(":",sortable[i])
			qt=10000-tonumber(qt)
			if qt==tobesent[itemId] then
				self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
				return
			end
		end
		for i=1,#sortable do
			local qt,bagId,slotId=strsplit(":",sortable[i])
			qt=10000-tonumber(qt)
			if qt>tobesent[itemId] then
				self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
				return
			end
		end
		for i=1,#sortable do
			local qt,bagId,slotId=strsplit(":",sortable[i])
			self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),10000-tonumber(qt))
		end
	end
end
function addon:Close(this)
	StackSplitFrame:Hide()
	CloseAllBags(this)
	wipe(sending)
	wipe(tobesent)

end
function addon:MoveItemToSendBox(itemId,bagId,slotId,qt)
	local needsplit
--@debug@
	print("From",bagId,slotId)
	print(itemId,tobesent[itemId],sending[itemId])
--@end-debug@
	local limit=tobesent[itemId]-sending[itemId]
	if limit==0 then return end
	if qt > limit then
		qt=limit
		needsplit=true
	else
		needsplit=false
	end
--@debug@
	local name=GetItemInfo(itemId)
	print('Sending',name,'(',itemId,')','x',qt)
--@end-debug@
	if needsplit then
		--@debug@
		print("Splitting attempt")
		--@end-debug@
		local freebag,freeslot=self:ScanBags(0,0)
		--@debug@
		print("Empty slot in ",freebag,freeslot)
		--@end-debug@
		if freebag and freeslot then
		--@debug@
			print("Split",bagId,slotId,qt)
		--@end-debug@
			SplitContainerItem(bagId,slotId,qt)
		--@debug@
			print("Pickup",freebag,freeslot)
		--@end-debug@
			PickupContainerItem(freebag,freeslot)
		--@debug@
			print("Using",freebag,freeslot,GetTime())
		--@end-debug@
			FillMailSlot(freebag,freeslot)
		else
			self:Print(L["Need at least one free slot in bags in order to send less than a full stack"])
			return
		end
	else
		UseContainerItem(bagId,slotId)
	end
end
function addon:FireMail(this)
	if self:GetBoolean('DRY') then return end
	if this then
		this:Disable()
	end
	local sent=0
	local body=""
	local header=L["Mail Commander Bulk Mail"]
	for i=1,ATTACHMENTS_MAX_SEND do
		local name,_,count=GetSendMailItem(i)
		if name then
			if self:GetBoolean("MAILBODY") then
				body=body..name .. " x " .. count .. "\n"
			end
			sent=sent+1
		end
	end
	if sent > 0 then
		SendMailNameEditBox:SetText(currentReceiver)
		if this then
			SendMail(currentReceiver,header,body)
			self:UpdateMailCommanderFrame()
		end
	end
	if this then
		this:Enable()
	end
end
function addon:OnSendClick(this,button)
	if not self:CanSendMail() then
		return
	end
	local sent=1
	for i=1,ATTACHMENTS_MAX_SEND do
		if GetSendMailItem(i) then sent=i end
	end
	for _,data in pairs(db.requests[currentReceiver]) do
		self:SearchItem(data.i)
	end
	self:ScheduleTimer("FireMail",0.05,this)
end
function addon:MailEvent(event,...)
	--@debug@
	print("Mail event ",event,...)
	--@end-debug@
	if event=="MAIL_SEND_SUCCESS" then
		mcf.Send:Enable()
		self:RefreshSendable()
		self:ScheduleTimer("UpdateMailCommanderFrame",0.01)
	elseif event=="MAIL_SEND_INFO_UPDATE" then
		wipe(sending)
		for i=1,ATTACHMENTS_MAX_SEND do
			local name,texture,count=GetSendMailItem(i)
			if name then
				local id=self:GetItemID(GetSendMailItemLink(i))
				sending[id]=sending[id]+count
			end
		end
		self:RefreshSendable()
		self:ScheduleTimer("UpdateMailCommanderFrame",0.01)
	end
end
function addon:CanSendMail()
	if not SendMailFrame:IsVisible() then
		self:Popup(L["Please, open mailbox before attempting to send"])
		return false
	end
	return true
end
function addon:OnItemClicked(itemButton,button)
	local section=itemButton:GetAttribute("section")
	if section=="items" then
		return self:ClickedOnItem(itemButton,button)
	elseif section=="toons" then
		return self:ClickedOnToon(itemButton,button)
	end
	--@debug@
	return self:Popup("Invalid section ".. tostring(section))
	--@end-debug@
end
function addon:ClickedOnToon(itemButton,button)
	local name=itemButton:GetAttribute("toon")
	if not name then return end
	if button=="LeftButton" then
		db.ignored[name]=not db.ignored[name]
		if db.ignored[name] then
			itemButton.Disabled:Show()
		else
			itemButton.Disabled:Hide()
		end
		return self:OnItemEnter(itemButton,button)
	elseif button=="RightButton" then
		return self:Popup(format(L["Do you want to delete\n%s?"],toonTable[name].text),DeleteToon,function() end,name)
	end

end
function addon:OnResetClick(this)
	StackSplitFrame:Hide()
	this.SplitStack(this,0)
end

local function AddCap(this,qt)
	local itemId=addon:GetItemID(this:GetAttribute("itemlink"))
	if qt==0 then qt=nil end
	db.cap[currentRequester][itemId]=qt
	addon:UpdateMailCommanderFrame()
end
local function AddKeep(this,qt)
	local itemId=addon:GetItemID(this:GetAttribute("itemlink"))
	db.keep[thisToon][itemId]=qt
	addon:UpdateMailCommanderFrame()
end
function addon:ClickedOnItem(itemButton,button)
	local shift,ctrl=IsShiftKeyDown(),IsControlKeyDown()
	local itemId=self:GetItemID(itemButton:GetAttribute("itemlink"))
	if not itemId or itemId==0 then
		if currentTab==INEED then
			--@debug@
			local type,itemID,itemLink=GetCursorInfo()
			print("click",type,itemID,itemLink)
			--@end-debug@
			if itemID then
				self:OnItemDropped(itemButton)
			end
		end
		return
	end
	--@debug@
	print ("Click",itemId,currentTab)
	--@end-debug@
	if shift then
		itemButton.SplitStack=AddCap
		StackSplitText:SetText(StackSplitFrame.split);
		OpenStackSplitFrame(1000,itemButton,"RIGHT","LEFT")
		StackSplitFrame.split = db.cap[currentRequester][itemId] or 0
		StackSplitText:SetText(StackSplitFrame.split);
		StackSplitText:SetTextColor(C:Green())
		if StackSplitFrame.split > 0 then StackSplitLeftButton:Enable() end
		MailCommanderSplitLabel.Text:SetTextColor(C:Green())
		MailCommanderSplitLabel.Text:SetText(L["Maximum sending"])
		MailCommanderSplitLabel:Show()
		return
	end
	if ctrl then
		itemButton.SplitStack=AddKeep
		OpenStackSplitFrame(1000,itemButton,"RIGHT","LEFT")
		StackSplitFrame.split = db.keep[thisToon][itemId]
		StackSplitText:SetText(StackSplitFrame.split);
		StackSplitText:SetTextColor(C:Yellow())
		if StackSplitFrame.split > 0 then StackSplitLeftButton:Enable() end
		MailCommanderSplitLabel.Text:SetTextColor(C:Yellow())
		MailCommanderSplitLabel.Text:SetText(L["Minimum Storage"])
		MailCommanderSplitLabel:Show()
		return
	end
	if currentTab==ISEND then
		if IsShiftKeyDown() or IsControlKeyDown() then return end
		if (button=="LeftButton") then
			db.disabled[itemId][thisToon][currentReceiver]=not db.disabled[itemId][thisToon][currentReceiver]
			if IsDisabled(itemId) then
				itemButton.Disabled:Show()
			else
				itemButton.Disabled:Hide()
			end
			return self:OnItemEnter(itemButton,button)
		elseif button=="RightButton" then
			if not self:CanSendMail() then
				return
			end
			self:SearchItem(itemId)
			self:ScheduleTimer("FireMail",0.05)
		end
	elseif currentTab==INEED then
		if button=="LeftButton" then
			if (itemId and currentRequester) then
				db.disabled[itemId]['ALL'][currentRequester]=not db.disabled[itemId]['ALL'][currentRequester]
				if IsDisabled(itemId) then
					itemButton.Disabled:Show()
				else
					itemButton.Disabled:Hide()
				end
				return self:OnItemEnter(itemButton,button)
			else
			--@debug@
			print("Error:",itemId,currentRequester)
			--@end-debug@
			end
		elseif button=="RightButton" then
			for i,d in ipairs(db.requests[currentRequester]) do
				if d.i==itemId then
					tremove(db.requests[currentRequester],i)
					dirty=true
					break
				end
			end
		end
	end
	self:UpdateMailCommanderFrame()
end
function addon:OnResetEnter(itemButton,motion)
	GameTooltip:SetOwner(itemButton,"ANCHOR_RIGHT")
	GameTooltip:AddLine(RESET .. " " .. itemButton.Text:GetText())
	GameTooltip:Show()
end
function addon:OnItemEnter(itemButton,motion)
	GameTooltip:SetOwner(itemButton,"ANCHOR_RIGHT")
	if itemButton:GetAttribute("section")=="items" then
		local itemlink=itemButton:GetAttribute('itemlink')
		if itemlink then
			GameTooltip:SetHyperlink(itemlink)
			local itemId=self:GetItemID(itemButton:GetAttribute("itemlink"))
			local disabled=IsDisabled(itemId)
			local color1=C.White
			local color2=disabled and GREEN_FONT_COLOR or RED_FONT_COLOR
			GameTooltip:AddLine(me)
			GameTooltip:AddDoubleLine(KEY_BUTTON1,disabled and ENABLE or DISABLE,color1.r,color1.g,color1.b,color2.r,color2.g,color2.b)
			if currentTab==INEED then
				if disabled then
					GameTooltip:AddLine(L["This item has been disabled for ALL toons"],C:Orange())
				else
					GameTooltip:AddLine(L["Disabling an item here will disable it for ALL toons"],C:Orange())
				end
				GameTooltip:AddDoubleLine(KEY_BUTTON2,REMOVE,color1.r,color1.g,color1.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
			else
				if disabled then GameTooltip:AddLine(format(L["Disabled items are not sent with \"%s\" button"],L["Send All"]),C:Orange()) end
				GameTooltip:AddDoubleLine(KEY_BUTTON2,L["Add to sendmail panel"],color1.r,color1.g,color1.b,GREEN_FONT_COLOR.r,GREEN_FONT_COLOR.g,GREEN_FONT_COLOR.b)
			end
			GameTooltip:AddDoubleLine(CTRL_KEY_TEXT .. ' - ' .. KEY_BUTTON1,L["Set minimum amount to keep on "] ..  thisToon,color1.r,color1.g,color1.b,C:Yellow())
			GameTooltip:AddDoubleLine(SHIFT_KEY_TEXT .. ' - ' .. KEY_BUTTON1,L["Set maximum sendable amount for "] .. (currentTab==INEED and currentRequester or currentReceiver),color1.r,color1.g,color1.b,C:Green())
--@debug@
			GameTooltip:AddDoubleLine("Id:",itemId)
--@end-debug@
		else
			GameTooltip:SetText(L["Dragging an item here will add it to the list"])
		end
	elseif itemButton:GetAttribute("section")=="toons" then
		local name=itemButton:GetAttribute('toon')
		if name then
			local enabled=not IsIgnored(name)
			local color1=C.White
			local color2=enabled and GREEN_FONT_COLOR or RED_FONT_COLOR
			GameTooltip:AddLine(toonTable[name].text)
			GameTooltip:AddLine(toonTable[name].tooltip)
			GameTooltip:AddDoubleLine(KEY_BUTTON1,enabled and DISABLE or ENABLE,color1.r,color1.g,color1.b,color2.r,color2.g,color2.b)
			GameTooltip:AddLine(L["Disabled toons will not appear in any list"],C:Orange())
			GameTooltip:AddDoubleLine(KEY_BUTTON2,REMOVE,color1.r,color1.g,color1.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
			GameTooltip:AddLine(L["Use to remove deleted toons"],C:Orange())
		end

	end
	GameTooltip:Show()
end
function addon:OnArrowsClick(this)
	--@debug@
	print("Arrow",this:GetID())
	--@end-debug@
	self:RenderButtonList(mcf.store,this:GetID())
end
function addon:OnTabClick(tab)
--@debug@
	print(tab,tab:GetID(),mcf.selectedTab)
--@end-debug@
	if mcf.selectedTab==tab:GetID() then return end
	PanelTemplates_SetTab(mcf, tab:GetID())
	currentTab=mcf.selectedTab
	self:UpdateMailCommanderFrame()
end
function addon:UpdateMailCommanderFrame()
	if mcf.selectedTab==INEED then
		addon:RenderNeedBox(mcf)
	elseif mcf.selectedTab==ISEND then
		addon:RenderSendBox(mcf)
	elseif mcf.selectedTab==IFILTER then
		addon:RenderFilterBox(mcf)
	else
--@debug@
		print("Invalid tab",mcf.selectedTab)
--@end-debug@
		return
	end
	self:InitializeDropDown(mcf.filter)

end
function addon:OnItemDropped(frame)
	local type,itemID,itemLink=GetCursorInfo()
--@debug@
	print("drop",type,itemID,itemLink)
--@end-debug@
	ClearCursor()
	if currentTab==ISEND then return end
	local toon=self:GetFilter()
	if toon=='NONE' then return end
	if mcf.selectedTab==INEED then
		local itemLink
		--local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID)
		if type=="item" then
			itemLink = select(2,GetItemInfo(itemID))
		elseif type=="merchant" then
			itemLink = GetMerchantItemLink(itemID)
		else
			return
		end
		if (not I:IsBop(itemLink)) then
			local itemID=self:GetItemID(itemLink)
			--@debug@
			print(toon,itemID)
			--@end-debug@
			for _,d in ipairs(db.requests[toon]) do
				if d.i==itemID then
					return
				end
			end
			local itemTexture=GetItemIcon(itemID)
			tinsert(db.requests[toon],{t=itemTexture,l=itemLink,i=itemID})
			dirty=true
		else
			self:Popup(L["You cant mail soulbound items"])
		end
	end
	self:UpdateMailCommanderFrame()
end
function addon:Reset(input,...)
	local message="MailCommander\n" .. L["Are you sure you want to erase all data?"]
	self:Popup(message,0,
			function(this)
				wipe(db)
			end,
			function() end
		)
end

--[[
local addon = LibStub("AceAddon-3.0"):NewAddon("Bunnies", "AceConsole-3.0")
local bunnyLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Bunnies!", {
	type = "data source",
	text = "Bunnies!",
	icon = "Interface\\Icons\\INV_Chest_Cloth_17",
	OnClick = function() print("BUNNIES ARE TAKING OVER THE WORLD") end,
})

function addon:OnInitialize()
	-- Obviously you'll need a ## SavedVariables: BunniesDB line in your TOC, duh!
	self.db = LibStub("AceDB-3.0"):New("BunniesDB", {
		profile = {
			minimap = {
				hide = false,
			},
		},
	})
	icon:Register("Bunnies!", bunnyLDB, self.db.profile.minimap)
	self:RegisterChatCommand("bunnies", "CommandTheBunnies")
end

function addon:CommandTheBunnies()
	self.db.profile.minimap.hide = not self.db.profile.minimap.hide
	if self.db.profile.minimap.hide then
		icon:Hide("Bunnies!")
	else
		icon:Show("Bunnies!")
	end
end
--]]
_G.MailCommander=addon
--@debug@
_G.MAC=addon
_G.MAC.sendable=sendable
_G.MAC.toonTable=toonTable

--@end-debug@

-- Key Bindings Names
_G.BINDING_HEADER_MAILCOMMANDER="MailCommander"
_G.BINDING_NAME_MCConfig=L["Requests Configuration"]