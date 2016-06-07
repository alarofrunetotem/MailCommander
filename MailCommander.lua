local __FILE__=tostring(debugstack(1,2,0):match("(.*):1:")) -- Always check line number in regexp and file
local me,ns=...
local pp=print
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
local print=function() end
assert(LibInit,me .. ": Missing LibInit, please reinstall")
addon=LibStub("LibInit"):NewAddon(ns,me,{noswitch=false,profile=true,enhancedProfile=true},"AceHook-3.0","AceEvent-3.0","AceTimer-3.0","AceBucket-3.0")
local C=addon:GetColorTable()
local L=addon:GetLocale()
local I=LibStub("LibItemUpgradeInfo-1.0")
local GetItemInfo=I:GetCachingGetItemInfo()
local math=math
local db
local bagCache={}
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
		dbversion=2,
		toons={
			['*']= {}-- char name plus realm
		},
		requests={ -- what this toon need: requests[toon]{itemdata(table)}
			['**']={}
		},
		disabled={
			['*']={   --itemId
				['*'] = { --sender
						--receiver toon
				}
			}
		},
		cap={ -- This receeiver will not be allowed to  have more than "cap" items
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
		stock={ -- Storage data
			['*']= { -- char name plus realm
				--itemId = number
				['*'] = 0
			}
		},
		categories={
		},
		updateStock={
		},
		ignored={},
		lastReceiver='NONE'
	}
}
-- locals
local presets
--local pseudolink="|cff9d9d9d|Hitem:%s:0:0:0:0:0:0:0:80:0|h[%s]|h|r"
local pseudolink="|cffffd200|Hitem:%s:0:0:0:0:0:0:0:80:0|h[%s]|h|r"
local mailRecipient
local slots=16
local mcf
local INEED=1
local ISEND=2
local IFILTER=3
local ICATEGORIES=4
local currentRequester='NONE'
local currentReceiver='NONE'
local lastReceiver
local thisFaction
local thisRealm
local thisToon=NONE
local currentTab=0
local dirty=true
local shouldsend
local oldshouldsend
local sendable={} -- For each toon, it's true if the current one has at least one object to send
local toonTable={} -- precaculated toon table for initDropDown to avoid bursting memory
local toonIndex={}
local i2s={
	__index=function(table,key)
		return rawget(table,tostring(key))
	end,
	__newindex=function(table,key,value)
		return rawset(table,tostring(key),value)
	end
}
local tobesent=setmetatable({},i2s)
local sending=setmetatable({},{__index=function(table,key)
	if type(key)=="string" and type(presets[key])=="table" then
		if key=="gold" then return tonumber(SendMailMoneyGold:GetText()) or 0 end
		local list=presets[key].list
		if type (list)=="table" then
			local c=0
			for k,v in pairs(table) do
				if tContains(list,k) then c=c+v end
			end
			return c
		end
	end
	return 0
	end})
local bags=setmetatable({},{__index=function() return 0 end})
local KCAP=999
local STARCAP=9999
local CAP=999999
local MERCHANT_STOCK=MERCHANT_STOCK:gsub('%%d','%%s')
local MONEY=MONEY
local ITEM_BNETACCOUNTBOUND=ITEM_BNETACCOUNTBOUND
local tostring=tostring
local bit=bit
local function Bags()
	local bags={}
	local bag=0
	local slot=0
	return function()
		if not bags[bag] then
			bags[bag]=GetContainerNumSlots(bag)
		end
		slot=slot+1
		if slot>bags[bag] then
			slot=1
			bag=bag+1
		end
		if bag<=NUM_BAG_SLOTS then
			return bag,slot
		end
	end
end
local function currentToon()
	return currentTab==INEED and currentRequester or currentReceiver
end
--Counter object

local Count={cache={}} --#Count
function Count:Sending(id,toon)
	return sending[id]
end
function Count:Total(id,toon)
	if not toon then toon=currentToon() end
	if type(presets[id].count)=="function" then
		return presets[id].count(id,toon) or 0
	else
		return GetItemCount(id) or 0
	end
end
function Count:Reserved(id)
	if id=="boe" then return 0 else return db.keep[thisToon][id] end
end
function Count:Keep(id,toon)
	if not toon then toon=currentToon() end
	if id=="boe" then return 0 else return db.keep[toon][id] end
end
function Count:Cap(id,toon)
	if not toon then toon=currentToon() end
	return db.cap[toon][id] or CAP
end
function Count:Stock(id,toon)
	if not toon then toon=currentToon() end
	if type(presets[id].stock)=="function" then
		return presets[id].stock(id,toon)
	else
		return db.stock[toon][id] or CAP
	end
end
function Count:Sendable(id,toon)
	if not toon then toon=currentToon() end

	return math.min(Count:Total(id,toon)-Count:Reserved(id)+Count:Sending(id),Count:Cap(id,toon))
end
function Count:IsSendable(id,idInBag,toon,bagId,slotId)
	if not toon then toon=currentToon() end
	if type(presets[id].validate)=="function" then
		return presets[id].validate(id,idInBag,toon,bagId,slotId)
	else
		return id==idInBag
	end
end

local function SendGold()
	local toon=currentToon()
	if toon and toon~='NONE' then
		for _,d in ipairs(db.requests[toon]) do
			if d.i=='gold' then
				local g=Count:Sendable('gold')
				if g >0 then
					SendMailMoneyGold:SetText(g)
					break
				end
			end
		end
	end
end

local function nop(rc) return rc end
local function CountGroup(name)
	local group=name
	if type(group)=="string" then group=presets[group] end
	local list=group.list
	if type(list)=="function" then
		return list()
	elseif type(list)=="table" then
		local c=0
		for _,id in ipairs(list) do
			local t=Count:Total(id)
			if t>0 then
				c=c+t
			end
		end
		return c
	elseif type(list)=="number" then
		return list
	end
	return 0
end
presets={ --#presets
	boatoken={
		t="Interface/ICONS/INV_Guild_Standard_Alliance_C",i='boatoken',
		l=pseudolink:format('boatoken',ITEM_BNETACCOUNTBOUND),
		count=function(dummy,toon)
			local c=0
			for _,id in ipairs(presets.boatoken.list) do
				if presets.boatoken.validate(nil,id,toon) then
					c=c+Count:Total(id,toon)
				end
			end
			return c
		end ,
		validate=function (_,bagItemId,toon,bagId,slotId)
			if db.toons[toon] then
					local toonClass=db.toons[toon].class
					local itemMask=ns.classBoa[tostring(bagItemId)] or 0
					local toonMask=ns.classes[toonClass] and ns.classes[toonClass].mask or 0
					return bit.band(toonMask,itemMask) >0
			end
			return false
		end,
		list={},
		nosplit=true
	},
	gold={
		t="Interface/ICONS/INV_Misc_Coin_01",i='gold',
		l=pseudolink:format('gold',MONEY),
		count=function() return 	math.floor(GetMoney()/10000) end
	},
	trainingstones={
		t="Interface\\ICONS\\Icon_UpgradeStone_legendary",
		i=116429,
		l=pseudolink:format('trainingstones',L["Battle-Training Stone"]),
		count=function() return CountGroup('trainingstones') end ,
		list=ns.trainingstones,
		validate=function(_,bagItemId) return tContains(ns.trainingstones,bagItemId) end,
		nosplit=true
	},
	battlestones={
		t="INTERFACE\\ICONS\\Icon_UpgradeStone_Rare",
		l=pseudolink:format('battlestones',L["Battle-Stone"]),
		i=98715,
		count=function() return CountGroup('battlestones') end ,
		list=ns.battlestones,
		validate=function(_,bagItemId) return tContains(ns.battlestones,bagItemId) end,
		nosplit=true
	},
	boe={
		t="INTERFACE\\ICONS\\INV_Sword_39",
		l=pseudolink:format("boe",ITEM_BIND_ON_EQUIP),
		count=function()
			local count=0
			if not db then return count end
			local toon=currentToon()
			if not toon then return count end
			if not db.keep then return count end
			if not db.cap then return count end
			if not db.keep[toon] then return count end
			if not db.cap[toon] then return count end
			local min=db.keep[toon].boe or 0
			local max=db.cap[toon].boe or 9999
			for bag,slot in Bags() do
				local itemlink=GetContainerItemLink(bag,slot)
				if itemlink and I:IsBoe(itemlink) then
					local level=I:GetUpgradedItemLevel(itemlink)
					if level>=min and level<=max then
						count=count+1
					end
				end
			end
			return count
		end,
		validate=function(_,_,_,bagId,slotId)
			local itemlink=GetContainerItemLink(bagId,slotId)
			if itemlink and I:IsBoe(itemlink) then
				return true
			end
			return false
		end,
		res=false,
		cap=L['Maximum Level'],
		keep=L['Minimum Level']
	}
}
local fake={
	count=false,
	f=false,
	validate=false,
	res=true,
	cap=L["Maximum Storage"],
	keep=L["Minimum Storage"],
}
setmetatable(presets,{__index=function(t,k) return fake end})
_G.MC=presets
for k,_ in pairs(ns.classBoa) do
	if tonumber(k) then tinsert(presets.boatoken.list,tonumber(k)) end
end
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
local MailFrame=MailFrame
local wipe,tinsert,pairs,ipairs,strcmputf8i=wipe,tinsert,pairs,ipairs,strcmputf8i
local PanelTemplates_DisableTab,PanelTemplates_EnableTab=PanelTemplates_DisableTab,PanelTemplates_EnableTab
local minibag="Interface\\PaperDollInfoFrame\\UI-GearManager-ItemIntoBag"
local undo="Interface\\PaperDollInfoFrame\\UI-GearManager-Undo"
local ignore="Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Opaque"
local ignore2="Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent"
local KEY_BUTTON1 = "\124TInterface\\TutorialFrame\\UI-Tutorial-Frame:12:12:0:0:512:512:10:65:228:283\124t" -- left mouse button
local KEY_BUTTON2 = "\124TInterface\\TutorialFrame\\UI-Tutorial-Frame:12:12:0:0:512:512:10:65:330:385\124t" -- right mouse button
--local HELP_ICON = "\124TInterface\AddOns\MailCommander\helpItems.tga:256:64\124t"
local HELP_ICON = "\124TInterface\\AddOns\\MailCommander\\helpItems.tga:64:256\124t"
local CTRL_KEY_TEXT,SHIFT_KEY_TEXT=CTRL_KEY_TEXT,SHIFT_KEY_TEXT
local FILTER,SEND,NEED=FILTER,SEND_LABEL,NEED
local kpairs=addon:getKpairs()
local GameTooltip=CreateFrame("GameTooltip","MailCommanderTooltip",UIParent,"GameTooltipTemplate")

local function checkBags()
	wipe(bags)
	for i=1,4 do
		local item=GetInventoryItemID("PLAYER",CONTAINER_BAG_OFFSET+i)
		if item then
			bags[item]=bags[item]+1
		end
	end
end
local function parseLink(itemLink)
	if (type(itemLink)=='number') then
		return itemLink
	elseif (type(itemLink)=="string") then
		local id=GetItemInfoFromHyperlink(itemLink)
		if id and id > 0 then return id end
		return itemLink:match("|Hitem:(.-):")
	end
end
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
		addon:InitData()
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
					local c=Count:Sendable(d.i,name)
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
local function SetItemCounts(frame,cap,keep,stock,total)
		if not frame then return end
		local button=frame.ItemButton
		if not button then return end
		if type(cap) == "boolean" then
			frame.Cap:Hide()
			frame.Keep:Hide()
			button.Stock:Hide()
			button.ModifiedStock:Hide()
			return
		end
		if not cap or cap == 0 then
			cap =CAP
		end
		if cap==CAP then
			cap=UNLIMITED
		elseif cap > KCAP then
			cap=math.floor(cap/1000) ..'K'
		end
		if keep then
			if keep >KCAP then
				keep=math.floor(keep/1000) ..'K'
			end
		else
			keep=0
		end
		frame.Cap:SetFormattedText("Max:%s",cap)
		frame.Cap:SetWidth(60)
		frame.Cap:Show()
		if not keep then keep=0 end
		--frame.Keep:SetFormattedText(MERCHANT_STOCK, keep)
		frame.Keep:SetFormattedText("Min:%s",keep)
		frame.Keep:SetWidth(60)
		frame.Keep:Show()
		if stock and stock > -1 then
			total = total or stock
			button.ModifiedStock:SetText(stock>STARCAP and '*' or stock)
			button.Stock:SetFormattedText(MERCHANT_STOCK,total>STARCAP and '*' or total)
			button.Stock:Show()
			button.ModifiedStock:Show()
		else
			button.Stock:Hide()
			button.ModifiedStock:Hide()
		end
	end
function addon:BAG_UPDATE_DELAYED(event,...)
--@debug@
	print(event)
--@end-debug@
	self:InitData()
	addon:RefreshSendable()
	if mcf:IsVisible() then self:UpdateMailCommanderFrame() end
	self:UpdateMailCommanderFrame()
end
function addon:PLAYER_MONEY(event,...)
--@debug@
	print(event)
--@end-debug@
	if mcf:IsVisible() then self:UpdateMailCommanderFrame() end
end
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
	if section=="items" then
		frame.ItemButton.MailCommanderDragTarget=true
		if type(data)=='table'  then
			frame.ItemButton:SetAttribute("itemlink",data.l)
			SetItemButtonTexture(frame.ItemButton,data.t)
			frame.Name:SetText(data.l:gsub('[%]%[]',''))
			if IsDisabled(data.i) then
				frame.ItemButton.Disabled:Show()
			else
				frame.ItemButton.Disabled:Hide()
			end
			addon:SetLimit(data.i)
			local toon=currentToon()
			local totalcount=Count:Total(data.i,toon)
			local cap=Count:Cap(data.i,toon)
			local keep=currentTab==ISEND and Count:Reserved(data.i) or Count:Keep(data.i,toon)
			local sending=Count:Sending(data.i,toon)
			local count=totalcount-keep-sending
			if tobesent[data.i] then
				count=tobesent[data.i]-sending
			end
			if cap and count >cap then
				count=cap
			elseif count <0 then
				count=0
			end
			SetItemCounts(frame,cap,keep,count,totalcount)
			SetItemButtonDesaturated(frame.ItemButton,count and count < 1 and currentTab==ISEND)
		else
			frame.ItemButton:SetAttribute("itemlink",nil)
			SetItemButtonTexture(frame.ItemButton,nil)
			SetItemButtonDesaturated(frame.ItemButton,false)
			frame.ItemButton.Disabled:Hide()
			SetItemCounts(frame,false)
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
		frame.ItemButton.MailCommanderDragTarget=false
		frame.ItemButton:SetAttribute('toon',name)
		SetItemButtonDesaturated(frame.ItemButton,false)
		if IsIgnored(name,true) then
			frame.ItemButton.Disabled:Show()
		else
			frame.ItemButton.Disabled:Hide()
		end
		frame.Name:SetText(data.text)
		SetItemButtonTexture(frame.ItemButton,"Interface\\ICONS\\ClassIcon_"..data.class)
		SetItemCounts(frame,false)
		frame:Show()
		return 1
	end
	frame:Show()
	return 1
end
function addon:CloseTip()
	if _G.GameTooltip then _G.GameTooltip:Hide() end
	if GameTooltip then GameTooltip:Hide() end
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
	--if db.locale~=GetLocale() then
		addon:RefreshItemlinks()
		db.locale=GetLocale()
	--end
	self.InitData=function() end -- Get rid of this
end
function addon:ApplyMINIMAP(value)
	if value then
		icon:Hide(me)
	else
		icon:Show(me)
		self:RefreshSendable()
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
	elseif fname and fname:find("TradeSkillReagent") then
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
function addon:OnEnabled()
	if (_G.ViragDevTool_AddData) then
		ViragDevTool_AddData(sending, "MC sending")
		ViragDevTool_AddData(tobesent, "MC tobesent")
		ViragDevTool_AddData(sendable, "MC sendable")
	end
end
function addon:OnInitialized()
	checkBags()
	-- AceDb does not support connected realms, so I am using a namespace
	local realmkey=GetRealmName()
	local r=GetAutoCompleteRealms()
	if r then
		table.sort(r)
		realmkey=strconcat(unpack(r))
	end
	self.Count=Count
	self.db.RegisterCallback(self,'OnDatabaseShutdown')
	self.namespace=self.db:RegisterNamespace(realmkey,dbDefaults)
	db=self.db:GetNamespace(realmkey).global
--@debug@
	local _,version=LibStub("LibInit")
	self:Print("Using LibInit version",version)
	self:Print("Using db version",db.dbversion)
--@end-debug@
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
	self:AddBoolean("BAGS",true,format(L["Switch bags with MailCommander"],SEND),L["Automatically opens and closes bags with MailCommander frame"])
--@debug@
	self:AddBoolean("DRY",false,"Disable mail sending")
--@end-debug@

	self:ScheduleTimer("InitData",0.2)
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
	self:RegisterEvent("BAG_UPDATE_DELAYED")
	self:RegisterEvent("PLAYER_MONEY")
	self:RegisterBucketEvent({'PLAYER_SPECIALIZATION_CHANGED','TRADE_SKILL_UPDATE'},5,'TRADE_SKILL_UPDATE')
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:SecureHookScript(_G.SendMailFrame,"OnShow","OpenSender")
	self:SecureHookScript(_G.SendMailFrame,"OnHide","CloseChooser")
	SendMailMailButton:SetScript("PreClick",function()
		mailRecipient=SendMailNameEditBox:GetText()
		--@debug@
		print(mailRecipient)
		--@end-debug@
	end)
	--@debug@
	self:RegisterEvent("MAIL_INBOX_UPDATE","MailEvent")
	self:RegisterEvent("UPDATE_PENDING_MAIL","MailEvent")
	self:SecureHookScript(_G.InboxFrame,"OnShow",print)
	self:SecureHookScript(_G.InboxFrame,"OnHide",print)
	--@end-debug@
	mcf=CreateFrame("Frame","MailCommanderFrame",UIParent,"MailCommander")
	self.xdb=db
	MailCommanderFrameAdditional.Name:SetText(L["Temporary slot"])
	MailCommanderFrameAdditional.MailCommanderDragTarget=true
	--@debug@
	db.dbversion=db.dbversion -- Forcing Ace to save it
	do
		local OldHook=_G.GameTooltip:GetScript("OnShow")
		if OldHook then
			_G.GameTooltip:HookScript("OnShow",function(...) OldHook(...) dragManage(...) end)
		else
			_G.GameTooltip:HookScript("OnShow",dragManage)
		end
	end
	--@end-debug@
	return --true
end
function addon:OnDatabaseShutdown()
	checkBags()
	db.updateStock[thisToon]=date("%Y-%m-%d %H:%M:%S",time())
	for bag,slot in Bags() do
		local itemId=select(10,GetContainerItemInfo(bag,slot))
		if itemId then
			db.stock[thisToon][itemId]=GetItemCount(itemId,true)-bags[itemId]
		end
	end
	db.stock['gold']=Count:Total("gold",thisToon)
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
		wipe(sending)
		SendMailMoneyGold:SetText('')
	end
end
function addon:OpenConfig(tab)
--@debug@
	print("Opening config")
--@end-debug@
	if self:GetBoolean("BAGS") then OpenAllBags(mcf) end
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
	PanelTemplates_SetNumTabs(frame, 4);
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
	self:RenderPresets()

end
function addon:GetFilter()
	if currentTab==INEED then
		currentRequester = currentRequester or thisToon ..'-'..thisRealm
		return currentRequester
	else

		if not sendable[currentReceiver] and not self:GetBoolean("ALLSEND") then
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
--@debug@
	print("Called setfilter with",name,info)
--@end-debug@
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
	shouldsend=false
	wipe(sendable)
	for name,_ in pairs(db.requests) do
		if name ~= thisToon then
			if rawget(db.toons,name) then
				for _,d in ipairs(db.requests[name]) do
					if Count:Sendable(d.i,name) > 0 then
						print(name,"sendable due to",d.i)
						sendable[name]=true
						shouldsend=true
						break
					end
				end
			end
		end
	end
	ldb:Update()
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
function addon:RenderPresets()
	local i=1
	for k,data in pairs(presets) do
		i=i+1
		local frame=mcf.Additional[i]
		if not frame then
			mcf.Additional[i]=CreateFrame("Frame",nil,mcf,"MailCommanderItemTemplate")
			frame=mcf.Additional[i]
			frame:SetPoint("TOPLEFT",mcf.Additional[i-1],"BOTTOMLEFT",0,20)
			frame.ItemButton:SetAttribute("section","presets")
		end
		local itemButton=frame.ItemButton
		if not data.l then data.l="[Loading]" end
		itemButton:SetAttribute("itemlink",k)
		SetItemButtonTexture(itemButton,data.t)
		itemButton:GetParent().Name:SetText(data.l:gsub('[%]%[]',''))

	end
end
function addon:RenderButtonList(store,page)
	--@debug@
	print("Refreshing view")
	--@end-debug@
	mcf.store=store
	if currentRequester==thisToon then mcf.Delete:Disable() else mcf.Delete:Enable() end
	--local total=#store
	page=page or 0
	local nextpage=false
	local section =mcf:GetAttribute("section") or "items"
	local first=page*slots
	local last=(page+1)*slots
	local i=1
	if store then
		checkBags()
		for _,data in pairs(store) do
			if currentTab==INEED or
				currentTab==ICATEGORIES or
				(currentTab==IFILTER and toonTable[data].level >= self:GetNumber("MINLEVEL")) or
				(currentTab==ISEND and (self:GetBoolean('ALLSEND') or Count:Sendable(data.i) >0)) then
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
	end
	if currentTab==INEED then
		if i-page*slots <=slots then
			i=i+AddButton(i-page*slots,nil,section)
		else
			nextpage=true
		end
	elseif currentTab == ISEND then
		mcf.Send:Enable()
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
function addon:RenderCategoryBox()
	mcf.Send:Hide()
	mcf.All:Hide()
	mcf.Delete:Hide()
	mcf.Filter:Hide()
	mcf.Info:Show()
	mcf.Info:SetText("Coming soon!")
	mcf.Info:SetTextColor(C:Orane())
	mcf.NameText:SetText(L["Items categories"])
	mcf:SetAttribute("section","categories")
	--@debug@
	DevTools_Dump(db.categories)
	--@end-debug@
	self:RenderButtonList(db.categories)
end
function addon:RenderNeedBox()
	self:RefreshSendable()
	mcf.Send:Hide()
	mcf.All:Hide()
	mcf.Delete:Show()
	mcf.Filter:Show()
	mcf.Info:Hide()
	mcf.NameText:SetText(L["Items needed by selected toon"])
	local toon=self:GetFilter()
	mcf:SetAttribute("section","items")
	if (_G.ViragDevTool_AddData) then
		ViragDevTool_AddData(db.requests[toon], toon)
	end
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
	self:RefreshSendable()
	mcf.Send:Show()
	mcf.All:SetChecked(self:GetBoolean("ALLSEND"))
	mcf.All:Show()
	mcf.All.tooltip=L["Show all toons regardless if they have items to send or not"]
	mcf.Delete:Hide()
	mcf.Filter:Show()
	mcf.Info:Hide()
	mcf.NameText:SetText(L["Items you can send to selected toon"])
	local toon=self:GetFilter()
	print("Sendbox",toon)
	mcf:SetAttribute("section","items")
	if (_G.ViragDevTool_AddData) then
		ViragDevTool_AddData(db.requests[toon], toon)
	end
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
		tip:AddLine(L["Drag items to define what the selected toon NEEDS"],C:Green())
		tip:AddLine(L["You can drag items from merchants,tradeskills and obviously your bags"],C:Green())
	elseif currentTab==ISEND then
		tip:AddLine(L["Mail Commander bulk mail sending"],C:Orange())
		tip:AddLine(L["From this panel you can send requested items"],C:Green())
		tip:AddLine(L["Items that you dont have are not shown"],C:Green())
		tip:AddLine(format(L["Use \"%s\" button to send all items at once (max %d items at a time)"],L["Send All"],ATTACHMENTS_MAX_SEND),C:Silver())
	elseif currentTab==IFILTER then
		tip:AddLine(L["Mail Commander character selection"],C:Orange())
		tip:AddLine(L["You can selectively disable character"],C:Green())
		tip:AddLine(L["Use gui (/mac gui) to change minimum level"],C:Silver())
	end
	if currentTab ~= IFILTER then
		tip:AddLine(L["Item buttons:"],C:Orange())
		--tip:AddLine(HELP_ICON)
		tip:AddLine(L["Definitions"])
		tip:AddDoubleLine("Min",L["Minimun storage for the selected toon"],C:Yellow())
		tip:AddDoubleLine("Max",L["Maximum storage for the selected toon"],C:Green())
		tip:AddDoubleLine("Reserved",format(L['Like "%s" but for the logged in toon'],"Keep"),C:Cyan())

	end
	if thisFaction=="Neutral" then
		tip:AddLine(L["ATTENTION: Neutral characters cant use mail"],C:Orange())
	end

	tip:Show()
end
function addon:SetLimit(itemInBag,dbg)
	if true then return end
	if not itemInBag then return end
	local qt=0
	local toon=currentTab==INEED and currentRequester or currentReceiver
	local stock=db.stock[toon][itemInBag] or 0
	local keep=db.keep[thisToon][itemInBag] or 0
	local cap=(db.cap[toon][itemInBag] or CAP)-stock
	local qt=GetItemCount(itemInBag,false)-keep-bags[itemInBag]
	if dbg then
		print("stock",stock)
		print("keep",keep,thisToon)
		print("cap",cap,toon)
		print("qt",qt)
	end
	if qt > cap then
		qt =cap
	end
	if qt<0 then
		qt=0
	end
	if dbg then
		print("qt2",qt)
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

local function FillMailSlot(bag,slot)
	local count,locked=select(2,GetContainerItemInfo(bag,slot))
	if locked or not count then
		addon:ScheduleTimer(FillMailSlot,0.01,bag,slot)
	else
		UseContainerItem(bag,slot)
	end
end
function addon:Mail(itemId)
	checkBags()
	--@debug@
	print("Mailing",itemId,tobesent[itemId])
	--@end-debug@
	if not itemId then
		SendMailMoneyGold:SetText('')
	end
	return self:SearchItem(itemId)
end
local sortable={}
local function standardCheck(itemInBag,itemId,bag,slot)
	return itemInBag and itemInBag==itemId or false
end
function addon:SearchItem(itemId)
	if IsDisabled(itemId) then return false end
	wipe(sortable)
	local toon=currentReceiver
	for bagId,slotId in Bags() do
		local bagItemId=GetContainerItemID(bagId,slotId)
		if bagItemId then
			if itemId then
				if Count:IsSendable(itemId,bagItemId,toon,bagId,slotId) then
					local n=select(2,GetContainerItemInfo(bagId,slotId))
					tobesent[bagItemId]=Count:Sendable(itemId,toon)
					tinsert(sortable,format("%05d:%s:%s:%s",10000+bags[bagItemId]-n,bagItemId,bagId,slotId))
				end
			else
				for _,data in pairs(db.requests[currentReceiver]) do
					if not IsDisabled(data.i) then
						if Count:IsSendable(data.i,bagItemId,toon,bagId,slotId) then
							local n=select(2,GetContainerItemInfo(bagId,slotId))
							tobesent[bagItemId]=Count:Sendable(data.i,toon)
							tinsert(sortable,format("%05d:%s:%s:%s",10000+bags[bagItemId]-n,bagItemId,bagId,slotId))
						end
					end
				end
			end
		end
	end
	if Count:Sendable('gold',toon) then
		SendGold()
	end
	if #sortable>0 then
		table.sort(sortable)
		for i=1,#sortable do
			local qt,itemId,bagId,slotId=strsplit(":",sortable[i])
			if tobesent[itemId]>0 then
				qt=10000-tonumber(qt)
				if qt==tobesent[itemId] then
					self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
					tobesent[itemId]=0
				end
			end
		end
		for i=1,#sortable do
			local qt,itemId,bagId,slotId=strsplit(":",sortable[i])
			if tobesent[itemId]>0 then
				qt=10000-tonumber(qt)
				if qt>tobesent[itemId] then
					self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
					tobesent[itemId]=0
				end
			end
		end
		for i=1,#sortable do
			local qt,itemId,bagId,slotId=strsplit(":",sortable[i])
			if tobesent[itemId]>0 then
				qt=10000-tonumber(qt)
				self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
				tobesent[itemId]=tobesent[itemId]-qt
			end
		end
	end
end
function addon:xSearchItem(itemId)
	if IsDisabled(itemId) then return false end
	if not tobesent[itemId] then tobesent[itemId]=9999 end
	wipe(sortable)
	local f=standardCheck
	if type(itemId)=="string" then
		local preset=presets[itemId] or db.categories[itemId]
		if type(preset.f)=="function" then
			f=preset.f
		elseif type(preset.f)=='table' then
			local v=type(preset.v)=="function" and preset.v or nop
			for _,id in ipairs(preset.f) do
				if v(id) then
					self:SearchItem(id)
				end
			end
		else
		end
	end
	for bagId,slotId in Bags() do
		local itemInBag=GetContainerItemID(bagId,slotId)
		local rc=f(itemInBag,itemId,bagId,slotId)
		if rc then
			tinsert(sortable,format("%05d:%s:%s",10000+bags[itemInBag]-select(2,GetContainerItemInfo(bagId,slotId)),bagId,slotId))
		elseif type(rc)=='nil' then
			return true
		end
	end
	if #sortable>0 then
	--@debug@
		print("Sortable")
		DevTools_Dump(sortable)
	--@end-debug@
		table.sort(sortable)
		for i=1,#sortable do
			local qt,bagId,slotId=strsplit(":",sortable[i])
			qt=10000-tonumber(qt)
			if qt==tobesent[itemId] then
				self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
				return true
			end
		end
		for i=1,#sortable do
			local qt,bagId,slotId=strsplit(":",sortable[i])
			qt=10000-tonumber(qt)
			if qt>tobesent[itemId] then
				self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
				return true
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
--@debug@
	print("Firemail",this and "Send all" or "Send single")
--@end-debug@
	if this then
		this:Disable()
	end
	local sent=0
	local body=""
	local header=SendMailSubjectEditBox:GetText()
	if this or not header or header=="" then
		header=L["Mail Commander Bulk Mail"]
	end
	for i=1,ATTACHMENTS_MAX_SEND do
		local name,_,count=GetSendMailItem(i)
		if name then
			body=body..name .. " x " .. count .. "\n"
			sent=sent+1
		end
	end
	local sentGold=tonumber(SendMailMoneyGold:GetText()) or 0
--@debug@
	print("Money",sentGold)
--@end-debug@
	if sent +sentGold > 0 then
		SendMailSubjectEditBox:SetText(header)
		SendMailNameEditBox:SetText(currentReceiver)
		mailRecipient=currentReceiver
		if this then
			if not self:GetBoolean('DRY') then
				if sentGold>0 then
					SendMailMailButton_OnClick(SendMailMailButton)
				else
					self:Print("Mail sent:\n",body)
					if self:GetBoolean("MAILBODY") then
						body=nil
					end
					SendMail(mailRecipient,header,body)
				end
				self:UpdateMailCommanderFrame()
			end
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
	checkBags()
	for i=1,ATTACHMENTS_MAX_SEND do
		if GetSendMailItem(i) then sent=i end
	end
	self:Mail()
	self:ScheduleTimer("FireMail",1,this)
end
function addon:MailEvent(event,...)
	--@debug@
	print("Mail event ",event,...)
	--@end-debug@
	if event=="MAIL_SEND_SUCCESS" then
		mcf.Send:Enable()
		local receiver=SendMailNameEditBox:GetText() or mailRecipient
		if #sending then
			--@debug@
			print("Receivers:",receiver,mailRecipient)
			--@end-debug@
			if not receiver or receiver=='' then receiver=mailRecipient end
			if receiver=='' then receiver=nil end
			--@debug@
			if not receiver or receiver=='' then error("Merda") end
			--@end-debug@
			local flagId
			if receiver then
				for id,qt in pairs(sending) do
					db.stock[receiver][id]=db.stock[receiver][id]+qt
					if type(id)=="number" then flagId=id end
				end
			end
		end
		wipe(sending)
		wipe(tobesent)
	elseif event=="MAIL_SEND_INFO_UPDATE" then
		wipe(sending)
		mailRecipient=SendMailNameEditBox:GetText()
		for i=1,ATTACHMENTS_MAX_SEND do
			local name,texture,count=GetSendMailItem(i)
			if name then
				local id=self:GetItemID(GetSendMailItemLink(i))
				sending[id]=sending[id]+count
			end
		end
		self:RefreshSendable()
		self:ScheduleTimer("UpdateMailCommanderFrame",0.5)
	end
end
function addon:DumpToon(toon,id)
	if id then
		print("Monitoring",GetItemInfo(id),GetItemCount(id),math.floor(GetMoney()/10000))
	else
		print("Monitoring",math.floor(GetMoney()/10000))
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
	elseif section=="presets" then
		if currentTab==INEED then
			local key=itemButton:GetAttribute('itemlink')
			local preset=presets[key]
--@debug@
			print(currentRequester)
			DevTools_Dump(preset)
--@end-debug@
			for _,d in ipairs(db.requests[currentRequester]) do
				if d.i==key then
					return
				end
			end
			tinsert(db.requests[currentRequester],{t=preset.t,l=preset.l,i=key})
			self:RefreshSendable()
			self:UpdateMailCommanderFrame()
			return
		end
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
function addon:RefreshItemlinks(...)
	local refresher
	refresher=coroutine.wrap(function()
			for i,toon in pairs(db.requests) do
				for _,data in ipairs(toon) do
					if type(data.i)=="number" then -- Ignoring alphanumeric key, which are NOT itemiId
						while true do
							local link=GetItemInfo(data.i,2)
							if link then
								data.l=link
								break
							else
								C_Timer.After(0.1,refresher)
								coroutine.yield(true)
							end
						end
					end
					C_Timer.After(0.01,refresher)
					coroutine.yield(true)
				end
			end
			refresher=nil
		end
		)
	refresher()
end

local function SplitFunc(this,qt)
	local itemId=parseLink(this:GetAttribute("itemlink"))
	local toon=this.toon
	local key=this.key
	if key=="cap" and qt==0 then qt=nil end
	db[key][toon][itemId]=qt
	addon:SetLimit(itemId)
	addon:UpdateMailCommanderFrame()
end
local function ShowSplitter(key,toon,itemButton,itemId,r,g,b)
	local msg
	local data=key=="res" and "keep" or key
	if type(itemId)=="string" then
		local tab=presets[itemId]
		if tab.nosplit then return end
		msg=tab[key]
		if msg==false then return end
	end
	if not msg then
		if key=='res' then
			msg=L['Reserved']
		elseif key=='cap' then
			msg=L['Maximum Storage']
		else
			msg=L['Minimum Storage']
		end
	end
	itemButton.SplitStack=SplitFunc
	itemButton.toon=toon
	itemButton.key=data
	StackSplitText:SetText(StackSplitFrame.split);
	OpenStackSplitFrame(99999,itemButton,"RIGHT","LEFT")
	StackSplitFrame.split = db[data][toon][itemId] or 0
	StackSplitText:SetText(StackSplitFrame.split);
	StackSplitText:SetTextColor(r,g,b)
	if StackSplitFrame.split > 0 then StackSplitLeftButton:Enable() end
	MailCommanderSplitLabel.Text:SetTextColor(r,g,b)
	MailCommanderSplitLabel.Text:SetText(toon .. "\n" .. msg)
	MailCommanderSplitLabel:Show()
	return
end
function addon:ClickedOnItem(itemButton,button,section)
	local shift,ctrl=IsShiftKeyDown(),IsControlKeyDown()
	local itemLink=itemButton:GetAttribute("itemlink")
	local itemId=parseLink(itemLink)
	local toon=currentTab==INEED and currentRequester or currentReceiver
	dirty=true
	--@debug@
	print ("Click",itemId,itemLink,currentTab==INEED and "NEED" or "SEND",itemButton:GetAttribute("itemlink"))

	if shift and ctrl then
		self:Print("---",toon,"---\n",
			"Sending:",sending[itemId],"\n",
			"Tobesent:",tobesent[itemId],"\n",
			"Stock:",db.stock[toon][itemId],"\n",
			"Keep:",db.keep[toon][itemId],"\n",
			"Cap:",db.cap[toon][itemId]
		)
	end
	--@end-debug@
	if not itemLink then
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
	if shift and ctrl then
		return ShowSplitter('res',thisToon,itemButton,itemId,C:Cyan())
	end
	if shift then
		return ShowSplitter('cap',toon,itemButton,itemId,C:Green())
	end
	if ctrl then
		return ShowSplitter('keep',toon,itemButton,itemId,C:Yellow())
	end
	if currentTab==ISEND then
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
--@debug@
			print("tobesent",itemId,tobesent[itemId])
--@end-debug@
			self:Mail(itemId)
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
			for i,d in pairs(db.requests[currentRequester]) do
				print(i,d.i,d.l)
				if i==itemId then
					db.requests[currentRequester][i]=nil
					break
				elseif d.i==itemId then
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
function addon:OnDescEnter(frame)
	GameTooltip:SetOwner(frame,"ANCHOR_RIGHT")
	GameTooltip:AddLine("Prova")
end
function addon:OnItemEnter(itemButton,motion)
	local section=itemButton:GetAttribute("section")
--@debug@
print("Hovering on",itemButton:GetObjectType(),itemButton:GetName(),section)
--@end-debug@
	GameTooltip:SetOwner(itemButton,"ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip:SetWidth(256)
	if  section =="items" then
		local itemlink=itemButton:GetAttribute('itemlink')
		if itemlink then
			--GameTooltip:SetHyperlink(itemlink)
			GameTooltip:AddLine(itemlink:gsub('[%]%[]',''))
			local itemId=parseLink(itemlink)
			local disabled=IsDisabled(itemId)
			local color1=C.White
			local color2=disabled and GREEN_FONT_COLOR or RED_FONT_COLOR
			local toon=currentTab==INEED and currentRequester or currentReceiver
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
			GameTooltip:AddLine("Settings for " .. toon,C:Orange())
			if itemId=="boe" then
				GameTooltip:AddDoubleLine(CTRL_KEY_TEXT .. ' - ' .. KEY_BUTTON1,L["Set min level"]..' (Min)' ,color1.r,color1.g,color1.b,C:Yellow())
				GameTooltip:AddDoubleLine(SHIFT_KEY_TEXT .. ' - ' .. KEY_BUTTON1,L["Set max level"]..' (Max)' ,color1.r,color1.g,color1.b,C:Green())
			else
				GameTooltip:AddDoubleLine(CTRL_KEY_TEXT .. ' - ' .. KEY_BUTTON1,L["Set min storage"]..' (Min)' ,color1.r,color1.g,color1.b,C:Yellow())
				GameTooltip:AddDoubleLine(SHIFT_KEY_TEXT .. ' - ' .. KEY_BUTTON1,L["Set max storage"]..' (Max)' ,color1.r,color1.g,color1.b,C:Green())
			end
			GameTooltip:AddDoubleLine("Min:",db.keep[toon][itemId],C.White.r,C.White.g,C.White.b,C:Yellow())
			GameTooltip:AddDoubleLine("Max:",db.cap[toon][itemId] and db.cap[toon][itemId] or 'N/A',C.White.r,C.White.g,C.White.b,C:Green())
			GameTooltip:AddDoubleLine("Stock:",db.stock[toon][itemId])
			local qt=GetItemCount(itemId)-bags[itemId]
			GameTooltip:AddLine("Availability on " .. C(thisToon,'Green'),C:Orange())
			if itemId~="boe" then
				GameTooltip:AddDoubleLine(CTRL_KEY_TEXT .. ' - ' .. SHIFT_KEY_TEXT .. '-' .. KEY_BUTTON1,L["Set reserved"] ,color1.r,color1.g,color1.b,C:Cyan())
			end
			GameTooltip:AddDoubleLine("Total:",qt,nil,nil,nil,C:Silver())
			if itemId~="boe" then
				GameTooltip:AddDoubleLine("Reserved:",db.keep[thisToon][itemId],nil,nil,nil,C:Cyan())
				GameTooltip:AddDoubleLine("Sendable:",math.max(0,qt-db.keep[thisToon][itemId]),nil,nil,nil,C:White())
			else
				GameTooltip:AddDoubleLine("Sendable:",qt,nil,nil,nil,C:White())
			end

--@debug@
			GameTooltip:AddDoubleLine("Id:",itemId)
			GameTooltip:AddDoubleLine("Sending:",sending[itemId])
			GameTooltip:AddDoubleLine("Tobesent:",tobesent[itemId])
--@end-debug@
		else
			GameTooltip:SetText(L["Dragging an item here will add it to the list"])
		end
	elseif section=="toons" then
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
	elseif section=="drop" then
		GameTooltip:AddLine(L["Temporary item slot"],C:Green())
		local itemlink=itemButton:GetAttribute('itemlink')
		if itemlink then
			GameTooltip:SetHyperlink(itemlink)
		end
		GameTooltip:AddLine(L["Items dropped here can be redropped everywhere"])
	elseif section=="presets" then
		local itemlink=itemButton:GetAttribute('itemlink')
		GameTooltip:AddLine(L["Click to add to current toon"],C:Green())
		GameTooltip:AddLine(presets[itemlink].l)
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
	print(tab:GetName(),tab:GetID(),mcf.selectedTab)
--@end-debug@
	PanelTemplates_SetTab(mcf, tab:GetID())
	currentTab=mcf.selectedTab
	self:UpdateMailCommanderFrame()
end
function addon:UpdateMailCommanderFrame()
--@debug@
	print("UpdateMailCommanderFrame",self:GetFilter(),currentToon(),sendable[currentToon()])
--@end-debug@
	if mcf.selectedTab==INEED then
		addon:RenderNeedBox(mcf)
	elseif mcf.selectedTab==ISEND then
		addon:RenderSendBox(mcf)
	elseif mcf.selectedTab==IFILTER then
		addon:RenderFilterBox(mcf)
	elseif mcf.selectedTab==ICATEGORIES then
		addon:RenderCategoryBox(mcf)
	else
--@debug@
		print("Invalid tab",mcf.selectedTab)
--@end-debug@
		return
	end
	self:InitializeDropDown(mcf.filter)
end
function addon:OnItemDropped(itemButton)
	dirty=true
	local type,itemID,itemLink=GetCursorInfo()
	ClearCursor()
	if itemButton:GetName()=="MailCommanderFrameAdditionalItemButton" then
		itemButton.MailCommanderDragTarget=true
		itemButton:SetAttribute("itemlink",itemLink)
		SetItemButtonTexture(itemButton,GetItemIcon(itemID))
		itemButton:GetParent().Name:SetText(itemLink:gsub('[%]%[]',''))
		return
	end
--@debug@
	print("Dropped on ",itemButton:GetName(),type,itemID,itemLink)
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
			self:RefreshSendable()
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

_G.MailCommander=addon
--@debug@
_G.MCOM=addon
_G.MCOM.sendable=sendable
_G.MCOM.toonTable=toonTable

--@end-debug@

-- Key Bindings Names
_G.BINDING_HEADER_MAILCOMMANDER="MailCommander"
_G.BINDING_NAME_MCConfig=L["Requests Configuration"]