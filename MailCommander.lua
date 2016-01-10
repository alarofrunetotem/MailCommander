local me,ns=...
--@debug@
--Postal_BlackBookButton
-- SendMailNameEditBox
local GameTooltip
LoadAddOn("Blizzard_DebugTools")
LoadAddOn("LibDebug")
if LibDebug then LibDebug() end
--@end-debug@
--[===[@non-debug@
local print=function() end
--@end-non-debug@]===]
local addon=LibStub("LibInit"):NewAddon("MailCommander","AceHook-3.0","AceEvent-3.0","AceTimer-3.0") --#MailCommander
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
local LDB=LibStub:GetLibrary("LibDataBroker-1.1",true)
local ldb= LDB:NewDataObject(me,fakeLdb) --#ldb
local icon = LibStub("LibDBIcon-1.0",true)

-- upvalues
local SetItemButtonTexture,UIDropDownMenu_AddButton=SetItemButtonTexture,UIDropDownMenu_AddButton
local GetProfessions,GetUnitName,UnitClass,GetProfessionInfo,UnitLevel=GetProfessions,GetUnitName,UnitClass,GetProfessionInfo,UnitLevel
local ClearCursor,CreateFrame,print,pairs,GetCursorInfo=ClearCursor,CreateFrame,print,pairs,GetCursorInfo
local ButtonFrameTemplate_HidePortrait,SendMailFrame,UIParent,InboxFrame=ButtonFrameTemplate_HidePortrait,SendMailFrame,UIParent,InboxFrame
local	UIDropDownMenu_CreateInfo,UIDropDownMenu_SetWidth=UIDropDownMenu_CreateInfo,UIDropDownMenu_SetWidth
local UIDropDownMenu_Initialize,UIDropDownMenu_SetText=UIDropDownMenu_Initialize,UIDropDownMenu_SetText
local PanelTemplates_SetNumTabs,PanelTemplates_SetTab=PanelTemplates_SetNumTabs,PanelTemplates_SetTab
local SetItemButtonDesaturated,SetItemButtonCount=SetItemButtonDesaturated,SetItemButtonCount
local GetItemCount=GetItemCount
local MailFrame=MailFrame
local PanelTemplates_DisableTab,PanelTemplates_EnableTab=PanelTemplates_DisableTab,PanelTemplates_EnableTab
local minibag="Interface\\PaperDollInfoFrame\\UI-GearManager-ItemIntoBag"
local undo="Interface\\PaperDollInfoFrame\\UI-GearManager-Undo"
local ignore="Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Opaque"
local ignore2="Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent"
-- locals
local slots=16
local db
local mcf
local INEED=1
local ISEND=2
local currentRequester
local currentReceiver
local lastReceiver
local currentTab=0
local dirty=true
local shouldsend
local sendable={} -- For each toon, it's true if the current one has at least one object to send
-- ldb extension
function ldb:Update()
	local oldshouldsend
	for name,data in pairs(db.toons) do
		if sendable[name] then
			shouldsend=true
			break
		end
	end
	if oldshouldsend ~= shouldsend then
		ldb.text=shouldsend and L["You have items to send"] or L["Nothing to send"]
		local button =icon:GetMinimapButton(me)
		if shouldsend then
			button.icon:SetVertexColor(0,1,0)
		else
			button.icon:SetVertexColor(1,0,0)
		end
	end
end
function ldb:OnClick(button)
	addon:OpenConfig()
end
function ldb:OnTooltipShow(...)
	if not shouldsend then
		self:AddLine(L["Nothing to send"])
	else
		self:AddLine(L["Items ready for:"])
		for name,data in pairs(db.toons) do
			if sendable[name] and name~=ns.me then
				self:AddLine(name,1,1,1)
			end
		end
	end
end

--addon:SetCustomEnvironment(ns)
function addon:SetDbDefaults(default)
	default.factionrealm={
		toons={
			['**']={}
		},
		friends={
			['**']={}
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
		lastReceiver=NONE
	}
	default.profile.ldb={hide=false}
end
local function IsDisabled(itemid)
	if not itemid then return false end
	if currentTab==INEED then
		--@debug@
		print(itemid,db.disabled[itemid]['ALL'][currentRequester])
		--@end-debug@
		return db.disabled[itemid]['ALL'][currentRequester] or false
	else
		--@debug@
		print(itemid,db.disabled[itemid]['ALL'][currentReceiver] , db.disabled[itemid][ns.me][currentReceiver])
		--@end-debug@
		return db.disabled[itemid]['ALL'][currentReceiver] or db.disabled[itemid][ns.me][currentReceiver] or false
	end
	return false
end
local function AddButton(i,data)
		if not mcf.Items[i] then
			print("Created item",i)
			mcf.Items[i]=CreateFrame("Frame",nil,mcf,"MailCommanderItemTemplate")
			mcf.Items[i].ItemButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
			mcf.Items[i].ItemButton.isBag=true
		end
		local frame=mcf.Items[i]
		if (i % 2) ==0 then --even
			frame:SetPoint("TOPLEFT",mcf.Items[i-1],"TOPRIGHT",10,0)
		elseif i>1 then -- odd
			frame:SetPoint("TOPLEFT",mcf.Items[i-2],"BOTTOMLEFT",0,20)
		else -- first one
			frame:SetPoint("TOPLEFT",mcf,"TOPLEFT",10,-60)
		end
		if type(data)=='table' then
			print("Loading",data.l,i)
			frame.ItemButton:SetAttribute("itemlink",data.l)
			SetItemButtonTexture(frame.ItemButton,data.t)
			frame.Name:SetText(data.l)
			SetItemButtonDesaturated(frame.ItemButton,IsDisabled(data.i))
			if currentTab==ISEND then
				local count=GetItemCount(data.i,false,false)
				SetItemButtonCount(frame.ItemButton,count)
			else
				SetItemButtonCount(frame.ItemButton)
			end
		else
			frame.ItemButton:SetAttribute("itemlink",nil)
			SetItemButtonTexture(frame.ItemButton,nil)
			SetItemButtonDesaturated(frame.ItemButton,false)
			SetItemButtonCount(frame.ItemButton)
			if type(data) =='nil' then
				frame.Name:SetText(L["Drag here do add an item"])
			else
				frame:Hide()
				return
			end

		end
		frame:Show()
end
function addon:CloseTip()
	if GameTooltip then GameTooltip:Hide() end
end
function addon:StoreData()
	local p1,p2=GetProfessions()
	ns.me=GetUnitName("player")
	ns.localizedClass,ns.class=UnitClass("player")
	if p1 then
		local name,icon,level=GetProfessionInfo(p1)
		db.toons[ns.me][1]=name .. "(" .. level ..")"
	end
	if p2 then
		local name,icon,level=GetProfessionInfo(p2)
		db.toons[ns.me][2]=name .. "(" .. level ..")"
	end
	db.toons[ns.me][ns.class]=ns.localizedClass .. "(" .. UnitLevel("player") ..")"
	currentRequester=GetUnitName("player")
	currentReceiver=db.lastReceiver or NONE
	print(icon)
	if icon then
		icon:Register(me,ldb,self.db.profile.ldb)
	end
end
function addon:OnInitialized()
	--AltoholicDB.profileKeys
	self:Popup("MailCommander\n EARLY BETA version for internal use...\nUse at your risk")
	if not GameTooltip then GameTooltip=CreateFrame("GameTooltip", "MailCommanderTooltip", UIParent, "GameTooltipTemplate") end
	print("Running oninit")
	db=self.db.factionrealm
	self:AddOpenCmd("reset","Reset",L["Erase all stored data"])
	self:AddOpenCmd("config","OpenConfig",L["Open configuration view"])
	self:ScheduleTimer("StoreData",2)
	self:RegisterEvent("MAIL_SHOW","CheckTab")
	self:RegisterEvent("MAIL_CLOSED","CheckTab")
	self:RegisterEvent("MAIL_INBOX_UPDATE",print)
	self:RegisterEvent("MAIL_SEND_SUCCESS","MailEvent")
	self:RegisterEvent("MAIL_FAILED","MailEvent")
	self:RegisterEvent("BAG_UPDATE_DELAYED",function(...) dirty=true end)
	self:SecureHookScript(_G.SendMailFrame,"OnShow","OpenSender")
	self:SecureHookScript(_G.InboxFrame,"OnShow",print)
	self:HookScript(_G.SendMailFrame,"OnHide","CloseChooser")
	self:HookScript(_G.InboxFrame,"OnHide",print)
	mcf=CreateFrame("Frame","MailCommanderFrame",UIParent,"MailCommander")
	--@debug@
	self:ScheduleTimer("OpenConfig",3)
	--@end-debug@
	self:ScheduleRepeatingTimer("RefreshSendable",10)
end
function addon:CheckTab(event)
	if event =="MAIL_SHOW" then
		PanelTemplates_EnableTab(mcf,ISEND)
	else
		PanelTemplates_DisableTab(mcf,ISEND)
		PanelTemplates_SetTab(mcf,INEED)
	end
end
function addon:OpenConfig(tab)
--@debug@
	print("Opening config")
--@end-debug@
	OpenAllBags()
	mcf:SetParent(UIParent)
	mcf:ClearAllPoints()
	mcf:SetPoint("CENTER")
	PanelTemplates_SetTab(mcf,INEED)
	currentTab=mcf.selectedTab
	addon:UpdateMailCommanderFrame()
	mcf:Show()
end
function addon:OpenSender(tab)
	ShowUIPanel(MailFrame);
	MailFrameTab_OnClick(MailFrame,2)
	if ( not SendMailFrame:IsShown() ) then
		CloseMail();
		return;
	end
	mcf:ClearAllPoints()
	mcf:SetPoint("TOPLEFT",MailFrame,"TOPRIGHT",0,0)
	mcf:SetHeight(MailFrame:GetHeight())
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
	print("Running frame onload")
	--MCF:EnableMouse(true)
	--MCF:SetMovable(true)
	frame.Send:SetText(L["Send All"])
	frame.Send.tooltip="tooltip"
	frame:RegisterForDrag("LeftButton")
	frame.Items[1].ItemButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
	frame:SetScript("OnDragStart",function(frame) frame:StartMoving() end)
	frame:SetScript("OnDragStop",function(frame) frame:StopMovingOrSizing() end)
	ButtonFrameTemplate_HidePortrait(frame)
	UIDropDownMenu_SetWidth(frame.Filter, 150);
	UIDropDownMenu_Initialize(frame.Filter, self.InitializeDropDown);
	UIDropDownMenu_SetText(frame.Filter,self:GetFilter())
	--@debug@
	print("Initial filter",self:GetFilter())
	--@end-debug@
	PanelTemplates_SetNumTabs(frame, 2);
	PanelTemplates_SetTab(frame, 1);
	local texture=mcf:CreateTexture(nil,"BACKGROUND")
	--texture:SetTexture("Interface\\QuestFrame\\QuestBG")
	texture:SetTexture("Interface\\MailFrame\\UI-MailFrameBG",false)
	texture:SetPoint("TOP",0,-20)
	texture:SetPoint("BOTTOM",0,33)
	texture:SetPoint("LEFT",0,0)
	texture:SetPoint("RIGHT",0,0)
	texture:SetTexCoord(0,0.6,0,0.7)

end
function addon:GetFilter()
	if currentTab==INEED then
		currentRequester = currentRequester or GetUnitName("player")
		return currentRequester
	else
		currentReceiver= currentReceiver or currentRequester or NONE
		if currentReceiver==GetUnitName("player") then currentReceiver=NONE end
		return currentReceiver
	end
end
function addon:SetFilter(info,name)
	if currentTab==INEED then
		currentRequester=name
	else
		currentReceiver=name
		lastReceiver=currentReceiver
	end
	UIDropDownMenu_SetText(mcf.Filter,name)
	self:UpdateMailCommanderFrame()
end
function addon:RefreshSendable()
	if dirty and not InCombatLockdown() then
		wipe(sendable)
		for name,_ in pairs(db.requests) do
			for _,d in ipairs(db.requests[name]) do
				local count=GetItemCount(d.i)
				if count and count > 0 then
					sendable[name]=true
					break
				end
			end
		end
		for name,_ in pairs(db.friends) do
			for _,d in ipairs(db.requests[name]) do
				local count=GetItemCount(d.i)
				if count and count > 0 then
					sendable[name]=true
					break
				end
			end
		end
		dirty=false
		ldb:Update()
	end
end
function addon:InitializeDropDown()
	local mcf=MailCommanderFrame
	local info = UIDropDownMenu_CreateInfo();
	local current = addon:GetFilter();
	local function SetFilter(...)
		addon:SetFilter(...)
	end
	UIDropDownMenu_SetText(mcf.Filter,current)
	local padding
	if currentTab==ISEND then
		addon:RefreshSendable()
		info.text="Alts"
		info.isTitle=true
		info.notCheckable=true
		UIDropDownMenu_AddButton(info);
		padding=10
	end
	info.notCheckable=nil
	info.func = SetFilter
	info.isTitle=nil
	info.disabled=nil
	for name,data in pairs(db.toons) do
		if currentTab==INEED or name~=ns.me then
			if next(data)~=nil then
				if currentTab==INEED or sendable[name] then
					info.checked=current == name
					info.arg1=name
					info.tooltipTitle=TRADE_SKILLS
					info.tooltipText=""
					info.tooltipOnButton=true
					info.leftPadding=padding
					info.text=name
					for n,l in pairs(data) do
						if tonumber(n) then
							info.tooltipText=info.tooltipText .. l .. "\n"
						else
							info.colorCode="|c".._G.RAID_CLASS_COLORS[n].colorStr
							info.text=name .. " " .. l
						end
					end
					UIDropDownMenu_AddButton(info);
				end
			end
		end
	end
	if currentTab==ISEND then
		info.leftPadding=nil
		info.text="Friends"
		info.isTitle=true
		info.notCheckable=true
		info.checked=nil
		UIDropDownMenu_AddButton(info);
		info.notCheckable=nil
		info.isTitle=nil
		info.disabled=nil
		for name,data in pairs(db.friends) do
			if sendable[name] then
				info.checked=current == name
				info.arg1=name
				info.tooltipTitle="Professions"
				info.tooltipText=""
				info.tooltipOnButton=true
				info.leftPadding=padding
				for n,l in pairs(professions) do
					info.tooltipText=info.tooltipText .. n .. " (" .. l ..")\n"
				end
				info.text=name
				info.colorCode="|cff808000",
				UIDropDownMenu_AddButton(info);
			end
		end
	end
end

function addon:RenderButtonList(store,page)
	mcf.store=store
	local total=#store
	page=page or 0
	local nextpage=false
	--@debug@
	print("Refreshing button list for",currentTab)
	--@end-debug@
	for i=1,#mcf.Items do
		AddButton(i,false)
	end
	local first=page*slots
	local last=(page+1)*slots
	local i=1
	for ix,data in ipairs(store) do
		if currentTab==INEED or (tonumber(GetItemCount(data.i)) or 0) >0 then
			print(i,page*slots,(page+1)*slots)
			if i>first then
				if i > last then
					nextpage=true
					break
				else
					AddButton(i-page*slots,data)
				end
			end
			i=i+1
		end
	end
	if currentTab==INEED then
		--@debug@
		print("Devo mettere add e sono con i=",i," e page*slots=",page*slots," e slots =",slots)
		--@end-debug@
		if i-page*slots <=slots then
			AddButton(i-page*slots)
		else
			nextpage=true
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
	local toon=self:GetFilter()
	print("Filter is",toon)
	self:RenderButtonList(db.requests[toon])
	UIDropDownMenu_SetText(mcf.Filter,toon)
end
function addon:RenderSendBox()
	mcf.Send:Show()
	local toon=self:GetFilter()
	self:RenderButtonList(db.requests[toon])
	UIDropDownMenu_SetText(mcf.Filter,toon)
end
function addon:OnHelpEnter(this)
	local tip=GameTooltip
	tip:SetOwner(this,"ANCHOR_BOTTOMRIGHT")
	if currentTab==INEED then
		tip:AddLine(L["Mail Commandee request configuration"])
		tip:AddLine(L["Drag items to define what the selected toon NEEDS"])
	else
		tip:AddLine(L["Mail Commander bulk mail sending"])
		tip:AddLine(L["From this panel you can send requested items"])
		tip:AddLine(L["Items that you dont have are not shown"])
		tip:AddLine(format(L["Use \"%s\" button to send all items at once (max %d items at a time)"],L["Send All"],ATTACHMENTS_MAX_SEND))
	end

	tip:Show()

end
local function compare(itemInBag,itemRequest)
	if type(itemRequest)=='table' then
		for _,d in pairs(itemRequest) do
			if tonumber(itemInBag)==tonumber(d.i) then return true end
		end
	else
		return tonumber(itemInBag)==tonumber(itemRequest)
	end
	return false
end
function addon:OnSendClick(this,button)
	local sent=1
	for i=1,ATTACHMENTS_MAX_SEND do
		if GetSendMailItem(i) then sent=i end
	end
	if not self:CanSendMail() then
		return
	end
	for bagId=0,NUM_BAG_SLOTS do
		for slotId=1,GetContainerNumSlots(bagId) do
			if compare(GetContainerItemID(bagId,slotId),db.requests[currentReceiver]) then
				SendMailNameEditBox:SetText(currentReceiver)
				UseContainerItem(bagId,slotId)
				sent=sent+1
				if sent > ATTACHMENTS_MAX_SEND then
					bagId=999
					break
				end
			end
		end
	end
	local body=""
	local header=L["Mail Commander Bulk Mail"]
	for i=1,ATTACHMENTS_MAX_SEND do
		local name,_,count=GetSendMailItem(i)
		if name then
			body=body..name .. " x " .. count .. "\n"
		else
			break
		end
	end
	if body ~= "" then
		SendMail(currentReceiver,header,body)
		this:Disable()
	end
end
function addon:MailEvent(event)
	mcf.Send:Enable()
	self:UpdateMailCommanderFrame()
end
function addon:CanSendMail()
	if not SendMailFrame:IsVisible() then
		self:Popup(L["Please, open mailbox before attempting to send"])
		return false
	end
	return true
end
function addon:OnItemClicked(itemButton,button)
	local itemId=self:GetItemID(itemButton:GetAttribute("itemlink"))
	if not itemId then return end
	if currentTab==ISEND then
		if (button=="LeftButton") then
			db.disabled[itemId][ns.me][currentReceiver]=not db.disabled[itemId][ns.me][currentReceiver]
		elseif button=="RightButton" then
			if not self:CanSendMail() then
				return
			end
			for bagId=0,NUM_BAG_SLOTS do
				for slotId=1,GetContainerNumSlots(bagId) do
					if compare(GetContainerItemID(bagId,slotId),itemId) then
						MailFrameTab_OnClick(MailFrame,2)
						SendMailNameEditBox:SetText(currentReceiver)
						UseContainerItem(bagId,slotId)
						bagId=999
						break
					end
				end
			end
			--PickupContainerItem(1,4)
			--ClickSendMailItemButton(1)
		end
	else
		if button=="LeftButton" then
			if (itemId and currentRequester) then
				db.disabled[itemId]['ALL'][currentRequester]=not db.disabled[itemId]['ALL'][currentRequester]
			else
			--@debug@
			print("Error:",itemId,currentRequester)
			--@end-debug@
			end
		elseif button=="RightButton" then
			for i,d in ipairs(db.requests[currentRequester]) do
				if d.i==itemId then
					tremove(db.requests[currentRequester],i)
					break
				end
			end
		end
	end
	self:UpdateMailCommanderFrame()
end
function addon:OnItemEnter(itemButton,motion)
	GameTooltip:SetOwner(itemButton,"ANCHOR_CURSOR")
	local itemlink=itemButton:GetAttribute('itemlink')
	if itemlink then
		GameTooltip:SetHyperlink(itemlink)
		local itemId=self:GetItemID(itemButton:GetAttribute("itemlink"))
		local enabled=not IsDisabled(itemId)
		local color1=C.Azure
		local color2=enabled and RED_FONT_COLOR or GREEN_FONT_COLOR
		GameTooltip:AddDoubleLine(KEY_BUTTON1,enabled and DISABLE or ENABLE,color1.r,color1.g,color1.b,color2.r,color2.g,color2.b)
		if currentTab==INEED then
			GameTooltip:AddDoubleLine("",L["Disabled items will not appear in send window"])
			GameTooltip:AddDoubleLine(KEY_BUTTON2,REMOVE,color1.r,color1.g,color1.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
		else
			GameTooltip:AddDoubleLine("",format(L["Disabled items are not sent with \"%s\" button"],L["Send All"]))
			GameTooltip:AddDoubleLine(KEY_BUTTON2,"Remove",color1.r,color1.g,color1.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
		end
		GameTooltip:AddDoubleLine("Id:",itemId)

	else
		GameTooltip:SetText(L["Dragging an item here will add it to the list"])
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
	if mcf.selectedTab==1 then
		addon:RenderNeedBox(mcf)
	elseif mcf.selectedTab==2 then
		addon:RenderSendBox(mcf)
	else
--@debug@
		print("Invalid tab",mcf.selectedTab)
--@end-debug@
	end

end
function addon:OnItemDropped(frame)
	local type,itemID,itemLink=GetCursorInfo()
	ClearCursor()
	if currentTab==ISEND then return end
	local toon=self:GetFilter()
	if toon==NONE then return end
	if (type=="item" and mcf.selectedTab==INEED) then
		local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID)
		if (not I:IsBop(itemLink)) then
			--@debug@
			print(toon,itemID)
			--@end-debug@
			for _,d in ipairs(db.requests[toon]) do
				if d.i==itemID then
					return
				end
			end
			tinsert(db.requests[toon],{t=itemTexture,l=itemLink,i=itemID})
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
-- Key Bindings Names
_G.BINDING_HEADER_MAILCOMMANDER="MailCommander"
_G.BINDING_NAME_MCConfig=L["Requests Configuration"]