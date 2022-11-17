local __FILE__=tostring(debugstack(1,2,0):match("(.*):1:")) -- Always check line number in regexp and file
local me,ns=...
local pp=print
--@debug@
--Postal_BlackBookButton
-- SendMailNameEditBox
LoadAddOn("Blizzard_DebugTools")
LoadAddOn("LibDebug")
if LibDebug then LibDebug() end
local print=_G.LibDebug and print or function(...) print("MCom",...) end
--@end-debug@
--[===[@non-debug@
local print=function() end
local DevTools_Dump=function() end
--@end-non-debug@]===]
local addon --#MailCommander
local LibInit,minor=LibStub("LibInit",true)
assert(LibInit,me .. ": Missing LibInit, please reinstall")
addon=LibStub("LibInit"):NewAddon(ns,me,{noswitch=false,profile=true,enhancedProfile=true},"AceHook-3.0","AceEvent-3.0","AceTimer-3.0","AceBucket-3.0")
--@debug@
addon.debug=true
addon:Debug("Started with debug enabled")
--@end-debug@
local C=addon:GetColorTable()
local L=addon:GetLocale()
local I=LibStub("LibItemUpgradeInfo-1.0")
local GetContainerNumSlots=C_Container.GetContainerNumSlots
local GetContainerItemLink=C_Container.GetContainerItemLink
local GetContainerItemInfo=C_Container.GetContainerItemInfo
local UseContainerItem=C_Container.UseContainerItem
local math=math
local tContains=tContains
local toc=select(4,GetBuildInfo())
local allFactions
local allRealms
local db
local dbcategory
local legacy
local maxLevel
local currentID
local bagCache={}
local fullyEnabled
local pseudolink="|cffffd200|Hitem:%s:0:0:0:0:0:0:0:80:0|h[%s]|h|r"
local QUESTIONMARK_ICON="Interface\\ICONS\\inv_misc_questionmark"
local NONAME='NONE'
local KCAP=999
local STARCAP=9999
local CAP=999999
local MERCHANT_STOCK=MERCHANT_STOCK:gsub('%%d','%%s')
local MONEY=MONEY
local ITEM_BNETACCOUNTBOUND=ITEM_BNETACCOUNTBOUND
local toc=select(4,GetBuildInfo())
local ISCLASSIC=toc < 90000
local function keep(toon,id)
  if not toon then return 0 end
  return (legacy and db.keep[toon][id] or db.toons[toon].keep[id]) or 0
end
local function cap(toon,id)
  if not toon then return CAP end
  return (legacy and db.cap[toon][id] or db.toons[toon].cap[id]) or CAP
end
local function stock(toon,id)
  if not toon then return 0 end
  return (legacy and db.stock[toon][id] or db.toons[toon].stock[id]) or 0
end
local dbDefaults={
	global= {
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
		lastReceiver=NONAME
	}
}
local toonMeta={
  __index=function(t,k)
    if (k=="keep") then t.keep={} return t.keep end
    if (k=="requests") then t.requests={} return t.requests end
    if (k=="cap") then t.cap={} return t.cap end
    if (k=="keep") then t.keep={} return t.keep end
  end
}

-- locals
local mailRecipient
local slots=16
local mcf
local INEED=1
local ISEND=2
local IFILTER=3
local ICATEGORIES=4
local currentRequester
local currentReceiver
local currentCategory
local lastReceiver
local thisFaction
local thisRealm
local thisToon=NONE
local realmkey
local currentTab=0
local dirty=true
local shouldsend
local oldshouldsend
local DontSendNow={}
local sendable={} -- For each toon, it's true if the current one has at least one object to send
local toonTable={} -- precaculated toon table for initDropDown to avoid bursting memory
local toonIndex={}
local presets={}
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
local function parseLink(itemLink)
  if (type(itemLink)=='number') then
    return itemLink
  elseif (type(itemLink)=="string") then
    local id=GetItemInfoFromHyperlink(itemLink)
    if id and id > 0 then return id end
    return itemLink:match("|Hitem:(.-):")
  end
end
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

local Count={cache={},
	samefaction=setmetatable({},
		{__index=function(table,key)
		  if type(key)=="number" then error("Non doveva essere un numero") end
		  table[key]=toonTable[key] and toonTable[key].faction==thisFaction or false
		  return table[key]
		  end
		}
  ),
  connectedRealm=setmetatable({},
    {__index=function(table,key)
      table[key]=toonTable[key] and realmkey:find(toonTable[key].realm or NONE,1,true) or false
      return table[key]
      end
    }
  )
} --#Count
function Count:Sending(id,toon)
	return sending[id]
end
function Count:CanSendMail(toon)
	return toon and self.samefaction[toon] and thisRealm:find(db.toons[toon].realm or NONE,1,true)
end
function Count:Total(id,toon,bank)
	if not toon then toon=currentToon() end
	if type(id)=="string" and presets[id] then
		return presets[id]:count(id,toon,bank) or 0
	else
		return GetItemCount(id,bank) - bags[id] or 0
	end
end
function Count:Reserved(id)
	if id=="boe" then return 0 else return self:Keep(id,thisToon) end
end
function Count:Keep(id,toon)
	if not toon then toon=currentToon() end
	if id=="boe" then return 0 else return keep(toon,id) end
end
function Count:Cap(id,toon)
	if not toon then toon=currentToon() end
	return cap(toon,id)
end
function Count:Stock(id,toon)
	if not toon then toon=currentToon() end
	if type(presets[id].stock)=="function" then
		return presets[id]:stock(id,toon)
	else
	 return stock(toon,id)
	end
end
function Count:Sendable(id,toon)
  local testid=-1
  if id==testid then
    DevTools_Dump{"Sendable",db.items[id]}
  end
	if not toon then toon=currentToon() end
	if not Count:CanSendMail(toon) then
		local boa = (id=='boatoken') or (db.items[id].boa)
		if not boa then return 0 end
	end
	local totalWB=Count:Total(id,toon,true)
  local total=Count:Total(id,toon)
	local reserved=Count:Reserved(id)
  local sending=Count:Sending(id)
  local cap=Count:Cap(id,toon)
	if id==testid then
    print('totalwithbank',totalWB)
    addon:Debug('total',total)
    addon:Debug('reserved',reserved)
    addon:Debug('sending',sending)
    addon:Debug('cap',cap)
  end
	return math.min(totalWB-reserved+sending,math.min(total,cap))
end
function Count:IsSendable(id,idInBag,toon,bagId,slotId)
	if not toon then toon=currentToon() end
	if presets[id] and  type(presets[id].validate)=="function" then
  		return presets[id]:validate(idInBag,toon,bagId,slotId)
	else
		local boa=I:IsBoa(GetContainerItemLink(bagId,slotId))
		if not Count:CanSendMail(toon) and not boa then return false end
		return id==idInBag
	end
end

local function SendGold()
	local toon=currentToon()
	if toon and toon~=NONAME then
	 if legacy then
      for _,d in ipairs(db.requests[toon]) do
      	if d.i=='gold' then
      		local g=Count:Sendable('gold')
      		if g >0 then
      			SendMailMoneyGold:SetText(g)
      			break
      		end
      	end
      end
    else
      for id,_ in pairs(db.toons[toon].requests) do
        if id=='gold' then
          local g=Count:Sendable('gold')
          if g >0 then
            SendMailMoneyGold:SetText(g)
            break
          end
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
		for k,v in pairs(list) do
		  local id=type(v)=="number" and v or k
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
local function getProperty(key,toon,itemId,default)
  if legacy then
    return db.toons[toon][key][itemId] or default
   else
  	local rc,val=pcall(function(toon,itemId) return db[key][toon][itemId] end)
  	if rc then return val or default else return default end
	end
end
local basepresets={ --#basepresets
	boatoken={
		t="Interface/ICONS/INV_Guild_Standard_Alliance_C",i='boatoken',
		l=pseudolink:format('boatoken',ITEM_BNETACCOUNTBOUND),
		count=function(self,dummy,toon,bank)
			local c=0
			for _,id in ipairs(self.list) do
				if presets.boatoken:validate(id,toon) then
					c=c+Count:Total(id,thisToon,bank)
				end
			end
			return c
		end ,
		validate=function (self,bagItemId,toon,bagId,slotId)
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
		list=ns.trainingstones,
    nosplit=true,
		validate=function (self,bagItemId,toon) return tContains(self.list,bagItemId)end,
--]]
	},
	battlestones={
		t="INTERFACE\\ICONS\\Icon_UpgradeStone_Rare",
		l=pseudolink:format('battlestones',L["Battle-Stone"]),
		i=98715,
		list=ns.battlestones,
		nosplit=true,
    validate=function (self,bagItemId,toon) return tContains(self.list,bagItemId)end,
	},
	boe={
		t="INTERFACE\\ICONS\\INV_Sword_39",
		l=pseudolink:format("boe",ITEM_BIND_ON_EQUIP),
		count=function(self,key,toon)
			local count=0
			for bag,slot in Bags() do
			 if self:validate(nil,toon,bag,slot) then
						count=count+1
				end
			end
			return count
		end,
		validate=function (self,_,toon,bag,slot)
        local itemlink=GetContainerItemLink(bag,slot)
        if itemlink then
          local id=parseLink(itemlink)
          if not id then
            self:Print(C("Invalid item ","Orange"),itemlink)
            return
          end
          local min=getProperty('keep',toon,id,0)
          local max=getProperty('cap',toon,id,CAP)
          local level=GetDetailedItemLevelInfo(itemlink)
          local itemType,itemSubType=select(6,GetItemInfoInstant(id))
          if db.items[id].boe and IsEquippableItem(itemlink) and level>=min and level<=max then
          if itemType~=LE_ITEM_CLASS_WEAPON and itemType~=LE_ITEM_CLASS_WEAPON then return false end
            local rc,alreadybound=pcall(C_Item.IsBound,ItemLocation:CreateFromBagAndSlot(bag,slot))
            return not alreadybound
          end
        end
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
setmetatable(basepresets,{__index=function(t,k) return fake end})
_G.MC=basepresets
for k,_ in pairs(ns.classBoa) do
	if tonumber(k) then tinsert(basepresets.boatoken.list,tonumber(k)) end
end

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
local FILTER,SEND,NEED,CATEGORIES,CATEGORY,MISSING=FILTER,SEND_LABEL,NEED,CATEGORIES,CATEGORY,ADDON_MISSING
local kpairs=addon:getKpairs()
local GameTooltip=CreateFrame("GameTooltip","MailCommanderTooltip",UIParent,"GameTooltipTemplate")

local function checkBags()
	wipe(bags)
	for i=1,NUM_BAG_SLOTS do
		local item=GetInventoryItemID("PLAYER",CONTAINER_BAG_OFFSET+i)
		if item then
			bags[item]=bags[item]+1
		end
	end
end

local ldb
local icon

function addon:InitLdb()
-- ldb extension
  local LDB=LibStub:GetLibrary("LibDataBroker-1.1",true)
  icon = LibStub("LibDBIcon-1.0",true)
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
  ldb = LDB:NewDataObject(me,fakeLdb) --#ldb
  ldb.Update=function(self)
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
  ldb.OnClick=function(self,button)
  	if button=="RightButton" then
  		addon:Gui()
  		return
  	end
  	if mcf:IsVisible() then
  		HideUIPanel(mcf)
  	else
  		addon:InitData()
  		addon:OpenConfig()
  	end
  end
  ldb.OnTooltipShow=function(self,...)
  	if not shouldsend then
  		self:AddLine(L["Nothing to send"],C:Silver())
  	else
  		self:AddLine(L["Items available for:"],C:Green())
  		for name,data in pairs(db.toons) do
  			if sendable[name] and name~=thisToon and toonTable[name] then
  				self:AddLine(toonTable[name].text)
  				if legacy then
    				for _,d in pairs(db.requests[name]) do
    					local c=Count:Sendable(d.i,name)
    					if c and c >0 then
    						self:AddDoubleLine("   " .. d.l,c,nil,nil,nil,C:Green())
    					end
    				end
  				else
            for itemId,data in pairs(db.toons[name].requests) do
              local c=Count:Sendable(itemId,name)
              if c and c >0 then
                self:AddDoubleLine("   " .. db.items[itemId].l,c,nil,nil,nil,C:Green())
              end
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
  if icon then
    icon:Register(me,ldb,self.db.profile.ldb)
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
  --self:Debug(event)
	self:InitData()
	addon:RefreshSendable()
	if mcf:IsVisible() then self:UpdateMailCommanderFrame() end
	--self:UpdateMailCommanderFrame()
end
function addon:LOOT_OPENED(event,...)
  print(event,...)
end
function addon:CHAT_MSG_LOOT(event,...)
  print(event,...)
end
function addon:CHAT_MSG_CURRENCY(event,...)
  print(event,...)
end
function addon:LOOT_CLOSED(event,...)
  print(event,...)
end
function addon:PLAYER_MONEY(event,...)
  print(event,...)
  if mcf:IsVisible() then self:UpdateMailCommanderFrame() end
end
function addon:SetDbDefaults(default)
  pp("Db defaults set")
  default.global={
    categories={},
    items={
      ['*']={
        l=pseudolink:format(MISSING,MISSING),
        t=QUESTIONMARK_ICON,
        boa=false,
        boe=false,
        bop=false,
      }
    },
    toons={
      ['*']= {
        requests={
          ['*']=false
        },
        cap={
          ['*']=CAP
        },
        keep={
          ['*']=0
        },
        stock={
          ['*']=0
        },
        disabled=false,
      },
    },
  }
	default.profile.ldb={hide=false}
	return true
end
function addon:IsDisabled(itemid,to,from)
  if not itemid then return false end
  if currentTab==ICATEGORIES then return false end
  if not from then from = thisToon end
  if not to then to = currentTab==INEED and currentRequester or currentReceiver end
  --self:Debug("IsDisabled",itemid,from,to,currentRequester,currentReceiver)
  local disabled=db.toons[to].requests[itemid]
  if type(disabled)~="table" then
    db.toons[to].requests[itemid]={}
    return false,false,false
  else
    return disabled['ALL'] or disabled[from]  or DontSendNow[itemid],disabled['ALL'],disabled[from]
  end
  return false
end
function addon:IsIgnored(toon,ignorelevel)
  if not toon then return false end
  if toon == thisToon then return false end
  return db.toons[toon].ignored or (not ignorelevel and self:GetNumber("MINLEVEL") > toonTable[toon].level)
end
function addon:ToggleIgnored(toon)
  if not toon then return false end
  if toon == thisToon then return false end
  db.toons[toon].ignored = not db.toons[toon].ignored
end
function addon:AddButton(i,data,section)
  if i < 1 then return 1 end
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
	  local id=data
	  data=db.items[id]
		frame.ItemButton.MailCommanderDragTarget=true
		if type(data)=='table'  then
			frame.ItemButton:SetAttribute("itemlink",data.l)
			SetItemButtonTexture(frame.ItemButton,data.t)
			frame.Name:SetText(data.l:gsub('[%]%[]',''))
			if addon:IsDisabled(id) then
				frame.ItemButton.Disabled:Show()
			else
				frame.ItemButton.Disabled:Hide()
			end
			addon:SetLimit(id)
			local toon=currentToon()
			local totalcount=Count:Total(id,toon,true)
			local cap=Count:Cap(id,toon)
			local keep=currentTab==ISEND and Count:Reserved(id) or Count:Keep(id,toon)
			local sending=Count:Sending(id,toon)
			local count=totalcount-keep-sending
			if tobesent[id] then
				count=tobesent[id]-sending
			end
			if cap and count >cap then
				count=cap
			elseif count <0 then
				count=0
			end
			local count=math.min(count,Count:Total(id,toon)) -- count can never be more than the actual quantity in bags
			SetItemCounts(frame,cap,keep,count,totalcount)
			SetItemButtonDesaturated(frame.ItemButton,count and count < 1 and currentTab==ISEND)
		else
			frame.ItemButton:SetAttribute("itemlink",nil)
			SetItemButtonTexture(frame.ItemButton,nil)
			SetItemButtonDesaturated(frame.ItemButton,false)
			frame.ItemButton.Disabled:Hide()
			SetItemCounts(frame,false)
			if type(data) =='nil' then
				frame.Name:SetText(L["Drag here to add an item"])
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
		if self:IsIgnored(name,true) then
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
function addon:loadSelf(level)

	local p1,p2=ISCLASSIC and nil,nil or GetProfessions()
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
	db.toons[thisToon].updated=date("%Y-%m-%d %H:%M:%S",time())

end
local function mkkey(realm,faction,name)
  local prefix=9
  if not realm then addon:Debug("realm is nuil for ",name) end
  if realm==thisRealm then
    prefix=0
  elseif realmkey:find(realm or NONE,1,true) then
    prefix=5
  end
	local r,k=pcall(strconcat,prefix,realm,faction==thisFaction and ' ' or faction,name)
	return strlower(k)
end
local function toonSort(a,b)
	local k1=mkkey(toonTable[a].realm,toonTable[a].faction,a)
	local k2=mkkey(toonTable[b].realm,toonTable[b].faction,b)
	return strcmputf8i(k1,k2)<0
end
function addon:loadToonList()
  self:Debug("LoadToonList")
	wipe(toonTable)
	wipe(toonIndex)
	allRealms=self:GetBoolean('ALLREALMS')
  allFactions=self:GetBoolean('ALLFACTIONS')
	for name,data in pairs(db.toons) do
	 if name:find('-') then
  	 if allRealms or realmkey:find(data.realm or NONE,1,true) then
  		if allFactions or not data.faction or data.faction==thisFaction then
  		  data.class=data.class or UNKNOWN
  		  data.localizedClass=data.localizedClass or UNKNOWN
  		  data.level=data.level or maxLevel
  		  local classcolor=C_ClassColor.GetClassColor(data.class)
        if classcolor then
  		    classcolor=classcolor:GenerateHexColorMarkup()
  		  else
          classcolor="|cff"..C.Gray
  		  end
  		  local pattern="%s%s (%s %d)|r"
  			toonTable[name]={
  				-- text=data.class and format("|c%s%s (%s %d)|r",_G.RAID_CLASS_COLORS[data.class].colorStr,name,data.localizedClass,data.level) or name,
          text=pattern:format(classcolor,name,data.localizedClass,data.level),
  				tooltip=(data.p1 and data.p1 .."\n" or "") .. (data.p2 and data.p2 .."\n" or ""),
  				realm=data.realm,
  				level=data.level,
  				class=data.class,
  				faction=data.faction
  			}
  			data.text=toonTable[name].text
  			tinsert(toonIndex,name)
  		end
  	 end
	 else
	   addon:Debug("Found and ignore toon with no realm: " ..  name)
	   db.toons[name]=nil
	 end
	end
--	db.toonTable=nil
	table.sort(toonIndex,toonSort)
  db.toonIndex=toonIndex
end
function addon:InitData()
  self.InitData=function() end -- Get rid of this
  local start=GetTime()
  self:Debug("Background initialization started",start)
	self:loadSelf()
	currentRequester=thisToon
	currentReceiver=db.lastReceiver
	-- Sorry, I no longer truyst datastore
	if  false and _G.DataStore  then
		local d=_G.DataStore
		local delay=60*60*24*30 -- does not import old toons
		local realmList=_G.DataStore:GetRealmsConnectedWith(thisRealm)
		tinsert(realmList,thisRealm)
		for _,realm in pairs(realmList) do
			for name,key in pairs(d:GetCharacters(realm)) do
				name=name..'-'..realm
				if name~=thisToon then -- Do not overwrite current data with (possibly) stale data
					if d:IsEnabled("DataStore_Characters") then
            local faction=d:GetCharacterFaction(key)
            local level=d:GetCharacterLevel(key)
            local localizedClass,class=d:GetCharacterClass(key)
            local p1,p2
            if d:IsEnabled("DataStore_Crafts") then
            	local l,_,_,n=d:GetProfession1(key)
            	if l and l>0 then
            		p1=format("%s (%d)",n,l)
            	end
            	local l,_,_,n=d:GetProfession2(key)
            	if l and l>0 then
                p2=format("%s (%d)",n,l)
            	end
            end
            if not db.toons[name] then db.toons[name]={} end
            if faction then db.toons[name].faction=faction end
            if localizedClass then db.toons[name].localizedClass=localizedClass end
            if class then db.toons[name].class=class end
            if level then db.toons[name].level=level end
            if p1 then db.toons[name].p1=p1 end
            if p2 then db.toons[name].p2=p2 end
            db.toons[name].realm=realm
            if coroutine.running() then coroutine.yield() end
					end
				end
			end
		end
	end
	self:loadToonList()
	addon:RefreshItemlinks()
	db.locale=GetLocale()
  self:RegisterEvent("PLAYER_LEVEL_UP")
  self:RegisterEvent("MAIL_SHOW","CheckTab")
  self:RegisterEvent("MAIL_CLOSED","CheckTab")
  self:RegisterEvent("MAIL_SEND_SUCCESS","MailEvent")
  self:RegisterEvent("MAIL_FAILED","MailEvent")
  self:RegisterEvent("MAIL_LOCK_SEND_ITEMS","MailEvent")
  self:RegisterEvent("MAIL_UNLOCK_SEND_ITEMS","MailEvent")
  self:RegisterEvent("MAIL_SEND_INFO_UPDATE","MailEvent")
  --self:RegisterEvent("MAIL_SEND_COD_CHANGED","MailEvent")
  --self:RegisterEvent("MAIL_SEND_MONEY_CHANGED","MailEvent")
  self:RegisterEvent("MAIL_LOCK_SEND_ITEMS","MailEvent")
  self:RegisterEvent("BAG_UPDATE_DELAYED")
  self:RegisterEvent("LOOT_OPENED")
  self:RegisterEvent("LOOT_CLOSED")
  self:RegisterEvent("CHAT_MSG_CURRENCY")
  self:RegisterEvent("CHAT_MSG_LOOT")
  self:RegisterEvent("PLAYER_MONEY")
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  -- ,'TRADE_SKILL_UPDATE'
  self:RegisterBucketEvent({'PLAYER_SPECIALIZATION_CHANGED'},5,'TRADE_SKILL_UPDATE')
  self:RegisterEvent("PLAYER_LEVEL_UP")
  self:SecureHookScript(_G.SendMailFrame,"OnShow","OpenSender")
  self:SecureHookScript(_G.SendMailFrame,"OnHide","CloseChooser")
  SendMailMailButton:SetScript("PreClick",function()
    mailRecipient=SendMailNameEditBox:GetText()
  end)
  --@debug@
  self:RegisterEvent("MAIL_INBOX_UPDATE","MailEvent")
  self:RegisterEvent("UPDATE_PENDING_MAIL","MailEvent")
  --@end-debug@
  mcf=CreateFrame("Frame","MailCommanderFrame",UIParent,"MailCommander")
  mcf.HookOpenAllBags=function(self,...) print("MCFHOOK",self,...) end
  self:SetAdditional()
  self.xdb=db
  self:loadHelp()
  SetBinding("SHIFT-P","MCPickup")
  if self:GetNumber("MINLEVEL")> GetMaxLevelForPlayerExpansion() then
     self:SetVar("MINLEVEL",GetMaxLevelForPlayerExpansion()-10)
  end
  self:InitLdb()
  local terminated=GetTime()
  self:Debug("Background initialization terminated",terminated,terminated-start)
end
function addon:ApplyALLFACTIONS(value)
	self:loadToonList()
	if MailCommanderFrame:IsVisible() then self:UpdateMailCommanderFrame() end
end
function addon:ApplyALLREALMS(value)
  self:loadToonList()
  if MailCommanderFrame:IsVisible() then self:UpdateMailCommanderFrame() end
end
function addon:ApplyMINIMAP(value)
	if value then
		icon:Hide(me)
	else
		icon:Show(me)
		self:RefreshSendable(true)
	end
	self.db.profile.ldb={hide=value}
end
function addon:ApplyMINLEVEL(value)
	self:loadToonList()
	if MailCommanderFrame:IsVisible() then self:UpdateMailCommanderFrame() end

end
function addon:OnEnabled()
  self:Notice("Called OnEnable")
end
local presetsMeta= {__index={
    count=function(self) return CountGroup(self) end ,
    validate=function (self,id,bagItemId,toon,bagId,slotId)
      if self.list[bagItemId] then
        if Count:CanSendMail(toon) or (db.toons[toon].boa and db.items[bagItemId].boa) then
          return true
        end
      end
    end,
}
}
function addon:RefreshPresets()
  self:Debug("Refreshing presets")
  wipe(presets)
  for i,k in pairs(basepresets) do
    presets[i]=setmetatable(k,presetsMeta)
    db.items[i].t=k.t
    db.items[i].l=k.l
  end
  for i,k in pairs(dbcategory) do
    presets[i]=setmetatable(k,presetsMeta)
    db.items[i].t=k.t
    db.items[i].l=k.l
  end
  for _,data in pairs(presets) do
    if type(data.list)=="table" then
      for k,v in pairs(data.list) do
          if type(v) == "boolean" then v=k end
          db.items[v].t=GetItemIcon(v)
      end
    end
  end
end
function addon:OnInitialized()
  --@alpha@
  local dbversion=self.db.global.dbversion or 1
  if dbversion > 1 then return self:OnInitializedContinue() end
  self:Popup(C("Mailcommander","Orange").. "\n\n" .. C("ALPHA VERSION","Yellow") .. "\n\n" ..
  [[
  Before allowing this version to run, please make a backup of your saved variables file.
  Your old data "should" not be changed by this version but "better safe than sorry".
  Click on 'Cancel' and restore MailCommander 1.0 if you want to keep the old version
  ]],
  0,function(this)  C_Timer.After(0.5,addon.InitContinue) end,function() C_Timer.After(0.5,addon.InitDisabled) end,self)

end
function addon:InitDisabled()
  addon:Popup(C("Mailcommander","Orange").. "\n\n" .. "MailCommander has been disabled")
end
function addon:InitContinue()
  addon:OnInitializedContinue()
end
function addon:OnInitializedContinue()
  --@end-alpha@
  --@debug@
  self.db.debug=true
  --@end-debug@
  realmkey=GetRealmName()
  local r=GetAutoCompleteRealms()
  if #r then
    table.sort(r)
    realmkey=strconcat(unpack(r))
  end
  self:Debug("Realmkey",realmkey)
  local dbversion=self.db.global.dbversion or 1
  if dbversion==1 then
    if self:MigrateDatabase() then
      self:Popup(C("Mailcommander","Orange").. "\n" .. L["Mailcommander just migrated its database and will reload Wow"],0,ReloadUI)
      return
    end
  end
  self:Print("Current database Version",self.db.global.version or 1)

  self:LoadProfessions()
  maxLevel=ISCLASSIC and 60 or GetMaxLevelForLatestExpansion()
  dbcategory=self.db.global.categories
	-- AceDb does not support connected realms, so I am using a namespace
	self.Count=Count
	self.db.RegisterCallback(self,'OnDatabaseShutdown')
	if dbversion==2 then
	 db=self.db.global
	 db.toons[NONE]=nil
	 db.toons[NONAME]=nil
	else
    error("Databse migration failed. Try reloading or reinstall MailCommander 1")
  end
  self:RefreshPresets()
  checkBags()
	--DevTools_Dump(db.toons)
	self:AddLabel(L["Appearance"])
  if self:GetNumber("MINLEVEL")> maxLevel then
     self:SetVar("MINLEVEL",math.floor(maxLevel/10*8))
  end
	self:AddBoolean("MINIMAP",false,L["Hide minimap icon"],L["If you hide minimap icon, use /mac gui to access configuration and /mac requests to open requests panel"])
	self:AddBoolean("MAILBODY",false,L["Fill mail body"],L["Fill mail body with a detailed list of sent item"])
	self:AddBoolean("BAGS",true,L["Switch bags with MailCommander"],L["Automatically opens and closes bags with MailCommander frame"])
	self:AddLabel(L["Character selection"])
	self:AddSlider("MINLEVEL",30,1,maxLevel,L["Characters minimum level"],L["Only consider characters above this level"])
	--self:AddOpenCmd("requests","OpenConfig",L["Open requests panel"])
	self:AddBoolean("ALLSEND",false,format(L["Show all characters in %s tab"],SEND),L["Show all toons regardless if they have items to send or not"])
	self:AddBoolean("ALLFACTIONS",false,L["Show characters from both factions"],L["Show all toons fromj all factions"])
	self:AddBoolean("ALLREALMS",false,L["Show characters from all realms"],L["Show all toons from all realms"])
	self:AddLabel(L["Data management"])
	self:AddAction("Reset",L["Erase all stored data. Think twice"])
--@debug@
  self:AddLabel(L["Debug Options"])
	self:AddBoolean("DRY",false,"Disable mail sending")
  self:AddBoolean("DEBUG",false,"Shows debug messages")
--@end-debug@
  if false then
    self:coroutineExecute(0.001,"InitData",true)
  else
    self:InitData()
  end
	--return --true
end
function addon:applyDEBUG(value)
  self.debug=value

end
function addon:MigrateDatabase()
  local DBVAR=GetAddOnMetadata("MailCommander","X-Database")
  self:Debug("Raw db var:",DBVAR)
  local rawdb=_G[DBVAR]
  local todb=self.db.global
  local fromdb
  local toonUpdated={}
  local toonSource={}
  local empty={}
  if self.db.global.failedUpdate then
    self:Popup(C("Mailcommander","Orange").. "\n" ..
    L["Was not able to migrate your database."] .. "\n" ..
    L["Should I erase your old data?"],
    function(this) C_Timer.After(0.5,addon.Reset) end,function() end
    )
    return
  end
  self.db.global.failedUpdate=true
  if true then
    self.db.global.toons[NONE]=nil
    self.db.global.toons[NONAME]=nil
--    return true
  end
  -- For fresh install namespaces do not exists
  if type(rawdb.namespaces) == 'table' then
    for namespace,_ in pairs(rawdb.namespaces) do
      self.db:RegisterNamespace(namespace,dbDefaults)
      local original=rawdb.namespaces[namespace].global
      -- Found the most up to date data for the toon
      for toon,update in pairs(original.updateStock) do
        if toon~=NONAME then
          if toonUpdated[toon] and toonUpdated[toon] > update then
          else
            toonUpdated[toon]=update
            toonSource[toon]=namespace
          end
        end
      end
    end
    for toon,namespace in pairs(toonSource) do
      -- Loading base toon data
      fromdb=self.db:GetNamespace(namespace).global
      for k,v in pairs(fromdb.toons[toon]) do
        todb.toons[toon][k]=v
      end
      -- setting ignored flag
      if fromdb.ignored then
        todb.toons[toon].ignored=fromdb.ignored[toon]
      end
      todb.toons[toon].updated=toonUpdated[toon]
      -- Loading request data

      for _,data in pairs(fromdb.requests[toon] or empty) do
        print(data.i, data.l)

        -- storing general item
        todb.items[data.i]={
          t=data.t or QUESTIONMARK_ICON,
          l=data.l or pseudolink:format(data.i,MISSING)
        }
        -- now on toon we just store id with forbidden guys (as a concatenated string)
        todb.toons[toon].requests[data.i]=true
        print(toon,data.i,todb.toons[toon].requests[data.i])
      end
      -- Loading caps
      for id,qt in pairs(fromdb.cap[toon] or empty) do
        todb.toons[toon].cap[id]=qt
      end
      for id,qt in pairs(fromdb.keep[toon] or empty) do
        todb.toons[toon].keep[id]=qt
      end
      for id,qt in pairs(fromdb.stock[toon] or empty) do
        todb.toons[toon].stock[id]=qt
      end
    end
    for item,toons in pairs(fromdb.disabled or empty) do
      for sender,receivers in pairs(toons or empty) do
        for receiver,forbidden in pairs(receivers or empty) do
          if forbidden then
            if type(todb.toons[receiver].requests[item]) ~="table" then todb.toons[receiver].requests[item]={}
              todb.toons[receiver].requests[item][sender]=true
            end
          end
        end
      end
    end
  end
  self.db.global.failedUpdate=false
  self.db.global.dbversion=2
  return true
end
function addon:SetAdditional(itemLink,texture)
	local f=MailCommanderFrameAdditional
	local itemButton=f.ItemButton
	if itemLink then
		itemButton.MailCommanderDragTarget=false
		itemButton:SetAttribute("itemlink",itemLink)
		SetItemButtonTexture(itemButton,texture)
		f.Name:SetText(itemLink:gsub('[%]%[]',''))
	else
		itemButton:SetAttribute("itemlink",nil)
		SetItemButtonTexture(itemButton,nil)
		f.Name:SetText(L["Temporary slot"])
		f.MailCommanderDragTarget=true
    f.NameFrame:Hide()
    f.Name:Hide()
    f.Keep:Hide()
    f.Cap:Hide()
    f.Bg:Hide()
	end
end
local hooked
function addon:CloseDrag()
	currentID=nil
end
function addon:StartTooltips()
	if hooked then return end
	self:SecureHookScript(_G.GameTooltip,"OnHide","CloseDrag")
--	self:SecureHookScript(_G.GameTooltip,"OnTooltipSetItem", "attachItemTooltip")
--	self:SecureHookScript(_G.ItemRefTooltip,"OnTooltipSetItem", "a2")
--	self:SecureHookScript(_G.ItemRefShoppingTooltip1,"OnTooltipSetItem", "a3")
--	self:SecureHookScript(_G.ItemRefShoppingTooltip2,"OnTooltipSetItem", "a4")
--	self:SecureHookScript(_G.ShoppingTooltip1,"OnTooltipSetItem", "a5")
--	self:SecureHookScript(_G.ShoppingTooltip2,"OnTooltipSetItem", "a6")
--	self:SecureHook(_G.ItemRefTooltip, "SetHyperlink", "a7")
--	self:SecureHook(_G.GameTooltip, "SetHyperlink", "a8")
	hooked=true
end
function addon:StopTooltips()
	self:Unhook(_G.GameTooltip,"OnHide")
--	self:Unhook(_G.GameTooltip,"OnTooltipSetItem")
--	self:Unhook(_G.ItemRefTooltip,"OnTooltipSetItem")
--	self:Unhook(_G.ItemRefShoppingTooltip1,"OnTooltipSetItem")
--	self:Unhook(_G.ItemRefShoppingTooltip2,"OnTooltipSetItem")
--	self:Unhook(_G.ShoppingTooltip1,"OnTooltipSetItem")
--	self:Unhook(_G.ShoppingTooltip2,"OnTooltipSetItem")
--	self:Unhook(_G.ItemRefTooltip, "SetHyperlink")
--	self:Unhook(_G.GameTooltip, "SetHyperlink")
	hooked=false
end
function addon:OnDatabaseShutdown()
  if not legacy then return end
	checkBags()
	if type(db.updateStock)~="table" then db.updateStock={} end
	db.updateStock[thisToon]=date("%Y-%m-%d %H:%M:%S",time())
	for bag,slot in Bags() do
		local containerInfo = GetContainerItemInfo(bag,slot)
		local itemId = containerInfo.itemID
		if itemId then
			db.stock[thisToon][itemId]=GetItemCount(itemId,true)-bags[itemId]
		end
	end
	db.stock[thisToon]['gold']=Count:Total("gold",thisToon)
end
function addon:PLAYER_LEVEL_UP(event,level)
	self:loadSelf(level)
	self:loadToonList()
	if MailCommanderFrame:IsVisible() then self:UpdateMailCommanderFrame() end
end
function addon:TRADE_SKILL_UPDATE()
	C_Timer.After(5,self.loadSelf)
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
	if self:GetBoolean("BAGS") then
	 OpenAllBags(mcf)
  end
	mcf:SetParent(UIParent)
	mcf:ClearAllPoints()
  --mcf:SetPoint("CENTER")
	PanelTemplates_SetTab(mcf,INEED)
	currentTab=mcf.selectedTab
	addon:UpdateMailCommanderFrame()
	ShowUIPanel(mcf)
	--mcf:Show()
end
function addon:OpenSender(tab)
  if SendMailFrame:IsVisible() then
    PanelTemplates_EnableTab(mcf,ISEND)
  else
    PanelTemplates_DisableTab(mcf,ISEND)
    return
	end
	PanelTemplates_SetTab(mcf,ISEND)
	currentTab=mcf.selectedTab
	addon:UpdateMailCommanderFrame()
  ShowUIPanel(mcf)
end
function addon:CloseChooser()
	HideUIPanel(mcf)
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
	mcf.tabSEND.tooltip=L["Opens send mail interface"]
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
		currentReceiver=currentReceiver or next(sendable)
		if not currentReceiver and self:GetBoolean("ALLSEND") then
			for name,data in pairs(toonTable) do
				if data.level >= self:GetNumber("MINLEVEL") then
					currentReceiver=name
					break
				end
			end
		end
		if not self:GetBoolean("ALLSEND") and not sendable[currentReceiver] then
			currentReceiver=nil
		else
			if currentReceiver==thisToon then currentReceiver=nil end
		end
		return currentReceiver
	end
end
function addon:SetFilter(info,name)
  if name and toonTable[name] then
    if currentTab==INEED then
      currentRequester=name
    else
      lastReceiver=name
      currentReceiver=name
    end
  end
  UIDropDownMenu_SetText(mcf.Filter,name or NONE)
  self:UpdateMailCommanderFrame()
end
function addon:SetCatFilter(info,name)
  if name and dbcategory[name] then
    currentCategory=name
  else
    for n,v in pairs(dbcategory) do
      currentCategory=n
      break
    end
  end
  UIDropDownMenu_SetText(mcf.Filter,currentCategory or NONE)
  self:UpdateMailCommanderFrame()
end
function addon:RefreshSendable(sync)
  if sync then
    return self:doRefreshSendable()
  else
    self:coroutineExecute(0.01,"doRefreshSendable")
  end
end
function addon:doRefreshSendable(dbg)
	shouldsend=false
	wipe(sendable)
	for toon,toonData in pairs (db.toons) do
	 -- Skipping ignored, and from outher realms
	 if not toonData.ignored and toon ~= thisToon then
  		for i,d in pairs(toonData.requests) do
        if not addon:IsDisabled(i,toon) then
          if Count:Sendable(i,toon) > 0 then
            if dbg then pp("       ",db.items[i].l,"GOT!") end
						sendable[toon]=sendable[toon] or {}
						tinsert(sendable[toon],i)
						shouldsend=true
					end
				end
				if coroutine.running() then coroutine.yield() end
			end
		end
	end
	ldb:Update()
end
local info={}
function addon:InitializeDropDownForCats(this,level,menulist)
  local mcf=MailCommanderFrame
  wipe(info)
  local padding
  local realm=''
  local faction=''
  info.notCheckable=nil
  info.func= function(...) self:SetCatFilter(...) end
  info.isTitle=nil
  info.disabled=nil
  local current=currentCategory
  print("Initializing dropdown for categories",current)
  UIDropDownMenu_SetText(mcf.Filter,currentCategory or NONE)
  for name,data in pairs(dbcategory) do
        if not current then
          current = name
          self:SetCatFilter(nil,name)
        end
        info.isTitle=nil
        info.notCheckable=nil
        info.disabled=nil
        info.checked=strcmputf8i(current,name)==0
        if info.checked then
          UIDropDownMenu_SetText(mcf.Filter,name or NONE)
        end
        info.arg1=name
        info.tooltipTitle=TRADE_SKILLS
        info.tooltipOnButton=true
        info.text=name
        info.tooltip=function(tt) tt:AddLine("uno") tt:AddLine("due") end
        UIDropDownMenu_AddButton(info)
  end
end
function addon:InitializeDropDown(this,level,menulist)
	local mcf=MailCommanderFrame
	wipe(info)
	local padding
	local realm=''
	local faction=''
	info.notCheckable=nil
	info.func= function(...) self:SetFilter(...) end
	info.isTitle=true
	info.disabled=nil
	info.padding=nil
  info.notCheckable=true
  info.text=L["Current realm"]
  local myRealm="%s (" ..L["Current Realm"]..")"
  local connectedRealm="%s (" ..L["Connected Realm"]..")"
  local caption
  local firstOne
  local current=addon:GetFilter()
  local t=self:NewTable()
  for _,name in ipairs(toonIndex) do
		if not self:IsIgnored(name) and (currentTab==INEED or name~=thisToon) then
			if currentTab==INEED or sendable[name] or self:GetBoolean("ALLSEND") then
         tinsert(t,name)
  			 if name== (current or NONE) then
			     caption=name
			   end
			   if not firstOne then firstOne=name end
	   end
		end
	end
	if not caption then caption=firstOne end
	if not caption then caption=NONE end
	for _,name in ipairs(t) do
	-- Per realm header
    local data=toonTable[name]
		if realm~=data.realm then
			realm=data.realm
			if type(realm)=="nil" then self:applyDEBUG("Realm is nil for",data.name) end
			info.isTitle=true
			info.notCheckable=true
			info.leftPadding=nil
      info.icon=nil
      info.text=realm
      if data.realm==thisRealm then
         info.text=myRealm:format(realm)
      elseif realmkey:find(data.realm or NONE,1,true) then
         info.text=connectedRealm:format(data.realm)
      else
        info.text=realm
      end
			UIDropDownMenu_AddButton(info)
		end
		info.isTitle=nil
		info.notCheckable=nil
		info.disabled=nil
		info.leftPadding=nil
	  info.icon=FACTION_LOGO_TEXTURES[PLAYER_FACTION_GROUP[data.faction]]
		info.checked=strcmputf8i(caption,name)==0
		info.arg1=name
		info.tooltipTitle=TRADE_SKILLS
		info.tooltipOnButton=true
    info.text=data.text
		info.tooltipText=data.tooltip
		UIDropDownMenu_AddButton(info)
	end
  UIDropDownMenu_SetText(mcf.Filter,caption)
  self:DelTable(t)
end
function addon:BuildPresetItem(i)
  local frame=CreateFrame("Frame",nil,mcf,"MailCommanderItemTemplate")
  frame:SetScale(0.5)
  frame:SetPoint("TOPLEFT",mcf.Additional[i-1],"BOTTOMLEFT",0,40*mcf.Additional[i-1]:GetScale())
  frame.NameFrame:Hide()
  frame.Name:Hide()
  frame.Keep:Hide()
  frame.Cap:Hide()
  frame.Bg:Hide()
  mcf.Additional[i]=frame
  return frame
end
function addon:RenderPresets()
	local i=1
	local frame=mcf.Additional[1]
	frame:Show()
  --frame:SetScale(0.5)

	for k,data in pairs(presets) do
		i=i+1
		local frame=mcf.Additional[i] or self:BuildPresetItem(i)
		local itemButton=frame.ItemButton
		itemButton:SetAttribute("section","presets")
		if not data.l then data.l="[Loading]" end
		itemButton:SetAttribute("itemlink",k)
		SetItemButtonTexture(itemButton,data.t)
		itemButton:GetParent().Name:SetText(data.l:gsub('[%]%[]',''))
    frame:Show()
	end
end
function addon:RenderButtonList(store,page)
	mcf.store=store
	if currentRequester==thisToon then mcf.Delete:Disable() else mcf.Delete:Enable() end
	--local total=#store
	page=page or 0
	local nextpage=false
	local section =mcf:GetAttribute("section") or "items"
	local first=page*slots
	local last=(page+1)*slots
	local i=1
	if currentTab==INEED or (currentTab == ICATEGORIES and store) then
		i=i+self:AddButton(i-page*slots,nil,section)
	end
	if store then
		checkBags()
		for itemId,forbidden in pairs(store) do
			if currentTab==INEED or
				currentTab==ICATEGORIES or
				(currentTab==IFILTER and (toonTable[forbidden].level or maxLevel) >= self:GetNumber("MINLEVEL")) or
				(currentTab==ISEND and (self:GetBoolean('ALLSEND') or Count:Sendable(itemId) >0)) then
				if i>first then
					if i > last then
						nextpage=true
						break
					else
						i=i+self:AddButton(i-page*slots,currentTab==IFILTER and forbidden or itemId,section)
					end
				else
				  i=i+1
				end
			end
		end
	end
	if currentTab == ISEND then
		mcf.Send:Enable()
	end
	i=i-page*slots
	if mcf.Items then
		while i<=#mcf.Items do
			i=i+self:AddButton(i,false,section)
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
  if legacy then
    mcf.Info:Show()
    mcf.Info:SetText(L["Work in progress"])
    return
  end
	mcf.Filter:Show()
	mcf.AddCategory:Show()
  mcf.RemoveCategory:Show()
	mcf.NameText:SetText(L["Item categories"])
	mcf:SetAttribute("section","items")
	print("currentCategory",currentCategory,NONAME,currentCategory~=NONAME)
	if currentCategory and currentCategory~=NONAME then
  	self:RenderButtonList(dbcategory[currentCategory].list)
	else
    self:RenderButtonList()
  end
end
function addon:RenderNeedBox()
	self:RefreshSendable(true)
	mcf.Delete:Show()
	mcf.Filter:Show()
	mcf.NameText:SetText(L["Items needed by selected toon"])
	local toon=self:GetFilter()
	mcf:SetAttribute("section","items")
	self:RenderButtonList(db.toons[toon].requests)
	--UIDropDownMenu_SetText(mcf.Filter,toon)
end
function addon:RenderFilterBox()
	mcf.Info:Show()
  mcf.InfoClick:Show()
	mcf.Info:SetFormattedText(L["Characters under level |cffff9900%d|r are not shown"],self:GetNumber("MINLEVEL"))
	mcf.NameText:SetText(L["Enable or disable toons"])
  mcf.AddContact:Show()
	mcf:SetAttribute("section","toons")
	self:RenderButtonList(toonIndex)
end
function addon:RenderSendBox()
  wipe(DontSendNow)
	self:RefreshSendable(true)
	mcf.Send:Show()
	mcf.All:SetChecked(self:GetBoolean("ALLSEND"))
	mcf.All:Show()
	mcf.All.tooltip=L["Show all toons regardless if they have items to send or not"]
	mcf.Filter:Show()
	mcf.NameText:SetText(L["Items you can send to selected toon"])
	local toon=self:GetFilter()
	mcf:SetAttribute("section","items")
	if toon then
	 self:RenderButtonList(db.toons[toon].requests)
	else
   self:RenderButtonList()
	end
	--UIDropDownMenu_SetText(mcf.Filter,toon)
end
function addon:OnSendEnter(this)
	local tip=GameTooltip
	tip:SetOwner(this,"ANCHOR_CURSOR")
	tip:AddLine(L["Send all enabled items (no confirmation asked)"])
	tip:Show()
end
function addon:OnAddContactEnter(this)
  local tip=GameTooltip
  tip:SetOwner(this,"ANCHOR_CURSOR")
  tip:AddLine(L["Directly add a toon to the recipient list"])
  tip:Show()
end
function addon:OnAllClick(this,value)
	self:SetBoolean("ALLSEND",value)
	return self:UpdateMailCommanderFrame()
end
function addon:OnInfoEnter(this)
  if currentTab == IFILTER then
    local tip=GameTooltip
    tip:SetOwner(this,"ANCHOR_CURSOR")
    tip:AddLine(L["Click to change minimum shown level"])
    tip:Show()
  end
end
function addon:OnDeleteEnter(this)
	local tip=GameTooltip
	tip:SetOwner(this,"ANCHOR_CURSOR")
	tip:AddLine(L["Remove the selected toon from the droplist"])
	tip:Show()
end
function addon:OnHelpClick(this)
	return self:Gui()
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
	tip:AddLine(L["Click here to open configuration screen"],C:Green())
	tip:Show()
end
function addon:SetLimit(itemInBag,dbg)
	if true then return end
	if not itemInBag then return end
	local qt=0
	local toon=currentTab==INEED and currentRequester or currentReceiver
	local stock=stock(toon,itemInBag)
	local keep=keep(thisToon,itemInBag)
	local cap=cap(toon,itemInBag)-stock
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
	currentRequester=NONAME
	addon:UpdateMailCommanderFrame()
end
function addon:DeleteStore()
	if currentRequester and currentRequester ~= NONAME then
		self:Popup(C("Mailcommander","Orange").. "\n" .. format(L["Do you want to delete %1$s\nfrom DataStore, too?"].."\n"..
					L["If you dont remove %1$s also from DataStore, it will be back"],currentRequester),
					DeleteStore,function() currentRequester=NONAME addon:UpdateMailCommanderFrame() end,currentRequester)
		currentRequester=NONAME
	end
end
local function DeleteToon(popup,toon)
  if not legacy then
	  db.toons[toon]=nil
	else
  	wipe(db.requests[toon])
  	wipe(toonTable[toon])
  	for itemid,_ in pairs(db.disabled) do
  		wipe(db.disabled[itemid][toon])
  	end
	end
	local d=_G.DataStore
  currentRequester=NONAME
	print("LoadToonList")
	addon:loadToonList()
  print("UpdateMailCommanderFrame")
  addon:UpdateMailCommanderFrame()
end
function addon:OnDeleteClick(this,button)
	local info=rawget(db.toons,currentRequester)
	if info then
		self:Popup(C("Mailcommander","Orange").. "\n" .. format(L["Do you want to delete\n%s?"],info.text),DeleteToon,function() end,currentRequester)
	end
end

local function FillMailSlot(bag,slot)
	local containerInfo = GetContainerItemInfo(bag,slot)
	local count = containerInfo.stackCount
	local locked = containerInfo.isLocked
	addon:Debug("Filling from",bag,slot,GetContainerItemInfo(bag,slot))
	if locked or not count then
		addon:ScheduleTimer(FillMailSlot,0.01,bag,slot)
	else
		UseContainerItem(bag,slot)
	end
end
function addon:Mail(itemId)
	checkBags()
	if not itemId then
		SendMailMoneyGold:SetText('')
	end
	return self:SearchItem(itemId)
end
local sortable={}
local needed={}
local function standardCheck(itemInBag,itemId,bag,slot)
	return itemInBag and itemInBag==itemId or false
end
function addon:xSearchItem(itemId)
  self:Debug(itemId)
  if IsAltKeyDown() then
    return self:NewSearchItem(itemId)
  else
    return self:NormalSearchItem(itemId)
  end
end
function addon:SearchItem(itemId)
  if addon:IsDisabled(itemId) then self:Debug("Disabled",itemId)return false end
  local start=GetTimePreciseSec()
  wipe(sortable)
  wipe(needed)
  local toon=currentReceiver
  local connected=Count.connectedRealm[toon]
  --DevTools_Dump({'requests',db.toons[toon].requests})
  for id,enabled in pairs(db.toons[toon].requests) do
    local idata=db.items[id]
    if not self:IsDisabled(id,toon) and (not itemId or itemId==id) and (connected or idata.boa and db.toons[toon].boa) then
      if type(id)=="string" then
        if id=="boe" or id =="boatoken" then
          needed[id]=true
        elseif id ~= "gold" then
          for k,v in pairs(presets[id].list) do
            if type(v)=="boolean" then v=k end
            needed[v]=true
          end
        end
      else
        needed[id]=true
      end
    end
  end
  --DevTools_Dump({'needed',needed})
  for bagId,slotId in Bags() do
    local itemLink=GetContainerItemLink(bagId,slotId)
    if itemLink then
      local id=parseLink(itemLink)
      if id then
		local containerInfo = GetContainerItemInfo(bagId,slotId)
		local n = containerInfo.stackCount
        local GotIt=false
        if needed[id] then
          --self:Debug("Counting",id,itemLink)
          tobesent[id]=Count:Sendable(id,toon)
          GotIt=true
        elseif needed.boatoken then
          if presets.boatoken:validate(id,toon,bagId,slotId,true) then
            tobesent[id]=Count:Sendable(id,toon,bagId,slotId)
            GotIt=true
          end
        elseif needed.boe then
          if presets.boe:validate(id,toon,bagId,slotId) then
            tobesent[id]=Count:Sendable(id,toon,bagId,slotId)
            GotIt=true
          end
        end
        if GotIt then tinsert(sortable,format("%05d:%s:%s:%s",10000+bags[id]-n,id,bagId,slotId)) end
      end
    end
  end
  if Count:Sendable('gold',toon) then
    SendGold()
  end
  --DevTools_Dump({'tobesent',tobesent})
  --DevTools_Dump({'sortable',sortable})
  --DevTools_Dump({'sending',sending})

  if #sortable>0 then
    table.sort(sortable)
    for i=1,#sortable do
      local qt,itemId,bagId,slotId=strsplit(":",sortable[i])
      local itemLink=GetContainerItemLink(bagId,slotId)
      if tobesent[itemId]>0 then
        qt=10000-tonumber(qt)
        self:Debug(itemLink,qt,tobesent[itemId])
        if qt==tobesent[itemId] then
          self:Debug("moved=",self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt))
          --self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
          tobesent[itemId]=0
        end
      end
    end
    for i=1,#sortable do
      local qt,itemId,bagId,slotId=strsplit(":",sortable[i])
      if tobesent[itemId]>0 then
        qt=10000-tonumber(qt)
        if qt>tobesent[itemId] then
          self:Debug("moved>",self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt))
          --self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
          tobesent[itemId]=0
        end
      end
    end
    for i=1,#sortable do
      local qt,itemId,bagId,slotId=strsplit(":",sortable[i])
      if tobesent[itemId]>0 then
        qt=10000-tonumber(qt)
        self:Debug("moved",self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt))
        --self:MoveItemToSendBox(itemId,tonumber(bagId),tonumber(slotId),qt)
        tobesent[itemId]=tobesent[itemId]-qt
      end
    end
  end
  local fine=GetTimePreciseSec()
  self:Debug("New Took ",fine-start)
end
function addon:NormalSearchItem(itemId)
  if addon:IsDisabled(itemId) then self:Debug("Disabled",itemId)return false end
  self:Debug(itemId)
  local start=GetTimePreciseSec()
  wipe(sortable)
  wipe(needed)
  local toon=currentReceiver
  for bagId,slotId in Bags() do
    local bagItemId=GetContainerItemID(bagId,slotId)
    if bagItemId then
      self:Debug(bagId,slotId,itemId,bagItemId)
      if itemId then
        if Count:IsSendable(itemId,bagItemId,toon,bagId,slotId) then
		  local containerInfo = GetContainerItemInfo(bagId,slotId)
		  local n = containerInfo.stackCount
          tobesent[bagItemId]=Count:Sendable(itemId,toon)
          tinsert(sortable,format("%05d:%s:%s:%s",10000+bags[bagItemId]-n,bagItemId,bagId,slotId))
        end
      else
        for itemid,info in pairs(db.toons[currentReceiver].requests) do
          local isdisabled=addon:IsDisabled(itemid,toon)
          if not isdisabled then
            if Count:IsSendable(itemid,bagItemId,toon,bagId,slotId) then
			  local containerInfo = GetContainerItemInfo(bagId,slotId)
			  local n = containerInfo.stackCount
              tobesent[bagItemId]=Count:Sendable(itemid,toon)
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
  local fine=GetTimePreciseSec()
  --self:Debug("Normal Took ",fine-start)
  --DevTools_Dump(sortable)
  --DevTools_Dump(tobesent)
end
function addon:Open(this)
	if currentTab==INEED then
		self:StartTooltips()
	end
end
function addon:Close(this)
	StackSplitFrame:Hide()
	--CloseAllBags(this)
	wipe(sending)
	wipe(tobesent)
	self:StopTooltips()
end
function addon:MoveItemToSendBox(itemId,bagId,slotId,qt)
	local needsplit
	local limit=tobesent[itemId]-sending[itemId]
	if limit==0 then return 0 end
	if qt > limit then
		qt=limit
		needsplit=true
	else
		needsplit=false
	end
	if needsplit then
		local freebag,freeslot=self:ScanBags(0,0)
		if freebag and freeslot then
			SplitContainerItem(bagId,slotId,qt)
			PickupContainerItem(freebag,freeslot)
			FillMailSlot(freebag,freeslot)
		else
			self:Print(L["Need at least one free slot in bags in order to send less than a full stack"])
			return 0
		end
	else
		FillMailSlot(bagId,slotId)
	end
	return qt
end
function addon:FireMail(this)
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
		--name, itemId,textureid, count, quality = GetSendMailItem(index)
		local name,_,_,count=GetSendMailItem(i)
		if name then
			body=body..name .. " x " .. count .. "\n"
			sent=sent+1
		end
	end
	local sentGold=tonumber(SendMailMoneyGold:GetText()) or 0
	if sent +sentGold > 0 then
		SendMailSubjectEditBox:SetText(header)
		mailRecipient=currentReceiver
		local t1,r1=strsplit('-',thisToon)
		local t2,r2=strsplit('-',mailRecipient)
		local sendingTo=mailRecipient
		if r1==r2 then
			sendingTo=t2
		end
		SendMailNameEditBox:SetText(sendingTo)
		if this then
			if not self:GetBoolean('DRY') then
				if sentGold>0 then
					SendMailMailButton_OnClick(SendMailMailButton)
				else
					self:Print("Mail sent:\n",body)
					if not self:GetBoolean("MAILBODY") then
						body=""
					end
					SendMail(sendingTo,header,body)
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
	print(UIDropDownMenu_GetText(mcf.Filter))
	checkBags()
	for i=1,ATTACHMENTS_MAX_SEND do
		if GetSendMailItem(i) then sent=i end
	end
	SendMailNameEditBox:SetText("working")
	self:Mail()
	self:ScheduleTimer("FireMail",1,this)
end
function addon:MailEvent(event,...)
	if event=="MAIL_SEND_SUCCESS" then
		mcf.Send:Enable()
		local receiver=SendMailNameEditBox:GetText() or mailRecipient
		if #sending then
			if not receiver or receiver=='' then receiver=mailRecipient end
			if receiver=='' then receiver=nil end
			local flagId
			if receiver then
				for id,qt in pairs(sending) do
					db.toons[receiver].stock[id]=db.toons[receiver].stock[id]+qt
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
local extraToon
local professions={}
local classes
function addon:buildPanel()
      if not classes then
          if UnitSex("PLAYER") == 3 then
            classes=LOCALIZED_CLASS_NAMES_FEMALE
          else
            classes=LOCALIZED_CLASS_NAMES_MALE
           end
      end
      classes[UNKNOWN]=UNKNOWN
      professions[UNKNOWN]=UNKNOWN
      local factions={
        Alliance=FACTION_ALLIANCE,
        Horde=FACTION_HORDE
      }
      local answer={
      c=UNKNOWN,
      p1=UNKNOWN,
      p2=UNKNOWN,
      l=maxLevel,
      f=thisFaction
      }
      local factory=self:GetFactory()
      local t=factory:Panel(mcf,false)
      t:ClearAllPoints()
      local x,y=0,-23
      t:SetPoint("TOPLEFT",x,y)
      t:SetPoint("TOPRIGHT",x,y)
      t:SetPoint("BOTTOMLEFT")
      t:SetPoint("BOTTOMRIGHT")
      t:AddChild('c',factory:DropDown(t,'DEMONHUNTER',classes,CLASS,CHOOSE .. ' ' .. CLASS))
      t:AddChild('l',factory:Slider(t,1,maxLevel,maxLevel,LEVEL,CHOOSE .. ' ' .. LEVEL))
      t:AddChild('f',factory:DropDown(t,thisFaction,factions,CHOOSE .. ' ' .. FACTION))
      t:AddChild('p1',factory:DropDown(t,UNKNOWN,professions,PROFESSIONS_FIRST_PROFESSION,CHOOSE .. ' ' .. PROFESSIONS_FIRST_PROFESSION))
      t:AddChild('p2',factory:DropDown(t,UNKNOWN,professions,PROFESSIONS_SECOND_PROFESSION,CHOOSE .. ' ' .. PROFESSIONS_SECOND_PROFESSION))
      t:AddChild('a',factory:Checkbox(t,false,ITEM_ACCOUNTBOUND,L["This toon can receive Account Bound items"]))
      t:AddChild('b',factory:Button(t,SAVE))
      t:SetOnChange('b',function(self,value)
        local answer=self.father:GetValue()
        local name=self.father:GetAttribute('toon')
        local toon=db.toons[name]
        local rstart=name:find('-',1,true)
        toon.class=answer.c
        toon.localizedClass=classes[answer.c]
        toon.faction=answer.f
        toon.level=answer.l
        toon.realm=name:sub(rstart+1)
        toon.p1=professions[answer.p1]
        toon.p2=professions[answer.p2]
        toon.boa=answer.a
        addon:loadToonList()
        addon:RenderFilterBox()
        t:Hide()
      end)
    return t
end
function addon:ShowExtraToon(name)
  if not extraToon then
    extraToon=self:buildPanel()
  end
  if extraToon:IsShown() then extraToon:Hide() end
  local toon=db.toons[name]
  extraToon:SetValue('c',toon.class)
  extraToon:SetValue('l',toon.level or maxLevel)
  extraToon:SetValue('f',toon.faction or "Alliance")
  local p1=toon.p1 and toon.p1:gsub('%A','') or UNKNOWN
  local p2=toon.p1 and toon.p2:gsub('%A','') or UNKNOWN
  extraToon:SetValue('p1',tIndexOf(professions,p1))
  extraToon:SetValue('p2',tIndexOf(professions,p2))
  extraToon:SetTitle(name)
  extraToon:SetAttribute('toon',name)
  extraToon:Show()
end
function addon:AddCustomToon(name)
  if not name:find('-') then
    name=name..'-'..GetRealmName()
  end
  local toon=db.toons[name]
  if toon.text then
    self:Popup(C("Mailcommander","Orange").. "\n" .. name .. ' ' .. L['already present in database'] .. ': ' .. toon.text)
  else
    self:ShowExtraToon(name)
  end
end
function addon:RefreshCategory(name)
  for _,category in pairs(dbcategory) do
    if not name or dbcategory.i==name  then
      if type(category.list) == "table" then
        wipe(category.list)
      else
        category.list={}
      end
      for _,item in pairs(category.items) do
        tinsert(category.list,item.i)
      end
      if name then return end
    end
  end

end
function addon:AddCustomCategory(name,description)
  description=description or name
  if (not dbcategory[name]) then
    dbcategory[name]={
      l=pseudolink:format(name,description),
      t=QUESTIONMARK_ICON,
      list={}
    }
  end
  self:RefreshCategory(name)
  self:SetCatFilter(nil,name)
  self:UpdateMailCommanderFrame()
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
		self:Popup(C("Mailcommander","Orange").. "\n" .. L["Please open mailbox before attempting to send"])
		return false
	end
	return true
end
function addon:OnItemClicked(itemButton,button)
  local section=itemButton:GetAttribute("section")
  addon:Debug("Clicked",itemButton,button,section)
  if section=="items" then
    return self:ClickedOnItem(itemButton,button)
  elseif section=="toons" then
    local name=itemButton:GetAttribute('toon')
    return self:ClickedOnToon(itemButton,button)
  elseif section=="presets" then
    if currentTab==INEED then
      local key=itemButton:GetAttribute('itemlink')
      addon:Debug(key)
      local preset=presets[key]
      if db.toons[currentRequester].requests[key] then return end
      db.toons[currentRequester].requests[key]=true
      self:RefreshSendable(true)
      self:UpdateMailCommanderFrame()
      return
    end
  elseif section=="drop" then
    if button=="LeftButton" and not GetCursorInfo() then
      local key=itemButton:GetAttribute('itemlink')
      if key then
        return PickupItem(key)
      else
        self:ShowAddItemid()
      end
    elseif button=="LeftButton" then
      self:OnItemDropped(itemButton)
    elseif button=="RightButton" then
      return self:SetAdditional()
    else
      print("Che minchia di tasto e'?",button)
    end
    return
  end
  --@debug@
  return self:Popup(C("Mailcommander","Orange").. "\n" .. "Invalid section ".. tostring(section))
  --@end-debug@
end

function addon:ClickedOnToon(itemButton,button)
	local name=itemButton:GetAttribute("toon")
	if not name then return end
	if button=="LeftButton" then
	  if IsShiftKeyDown() then
	   return self:ShowExtraToon(name)
	  end
		self:ToggleIgnored(name)
		if self:IsIgnored(name) then
			itemButton.Disabled:Show()
		else
			itemButton.Disabled:Hide()
		end
		return self:OnItemEnter(itemButton,button)
	elseif button=="RightButton" then
		return self:Popup(C("Mailcommander","Orange").. "\n" .. format(L["Do you want to delete\n%s?"],toonTable[name].text),DeleteToon,function() end,name)
	end

end
function addon:OnResetClick(this)
	StackSplitFrame:Hide()
	this.SplitStack(this,0)
end
local function UpdateItemInfo(itemId)
    if presets[itemId] then
      local data=db.items[itemId]
      if itemId=="boatoken" then data.boa=true end
      if itemId=="boe" then data.boe=true end
      if type(presets[itemId].list)=="table" then
        for k,v in pairs(presets[itemId].list) do
          if type(v)=="boolean" then v=k end
          if db.items[v].boa then
            data.boa=true
            break
          end
        end
      end
    else
      local name,link,quality,_,_,_,_,_,_,texture,_,_,_,bindType,_,_,_=GetItemInfo(itemId)
      if link then
        local data=db.items[itemId]
        data.l=link
        data.t=texture
        data.bop=(bindType==LE_ITEM_BIND_ON_ACQUIRE)
        data.boe= (bindType==LE_ITEM_BIND_ON_EQUIP or bindType== LE_ITEM_BIND_ON_USE)
        data.boa=quality==Enum.ItemQuality.Heirloom or I:IsBoa(itemId)
     end
   end
end
function addon:RefreshItemlinks(...)
  local refresher
  self:Debug("Refreshlink start")
  refresher=coroutine.wrap(function()
    for i,data in pairs(db.items) do
      UpdateItemInfo(i)
      C_Timer.After(0.001,refresher)
      coroutine.yield(true)
    end
    addon:Debug("Refreshlink done")
    refresher=nil
  end)
  refresher()
end
function addon:GET_ITEM_INFO_RECEIVED(itemId,success)
  if success then
    local l= select(2,GetItemInfo(itemId))
    local t= GetItemIcon(itemId)
    db.items[itemId]={
        l =l,t=t
    }
  end
end

local function SplitFunc(this,qt)
	local itemId=parseLink(this:GetAttribute("itemlink"))
	local toon=this.toon
	local key=this.key
	if key=="cap" and qt==0 then qt=nil end
	if legacy then
	 db[key][toon][itemId]=qt
  else
   db.toons[toon][key][itemId]=qt
  end
	addon:SetLimit(itemId)
	addon:UpdateMailCommanderFrame()
end
function addon:ShowSplitter(key,toon,itemButton,itemId,r,g,b)
  self:Debug(key,toon,itemId)
  local msg
  local data=key=="res" and "keep" or key
  self:Debug(key,toon,itemId,data)
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
  local StackSplitFrame=StackSplitFrame
  local StackSplitText=StackSplitFrame.StackSplitText
  StackSplitText:SetText(StackSplitFrame.split);
  StackSplitFrame:OpenStackSplitFrame(99999,itemButton,"RIGHT","LEFT")
  if legacy then
    StackSplitFrame.split = db[data][toon][itemId] or 0
  else
    StackSplitFrame.split = db.toons[toon][data][itemId] or 0
  end
  StackSplitText:SetText(StackSplitFrame.split);
  StackSplitText:SetTextColor(r,g,b)
  if StackSplitFrame.split > 0 then StackSplitFrame.LeftButton:Enable() end
  MailCommanderSplitLabel.Text:SetTextColor(r,g,b)
  MailCommanderSplitLabel.Text:SetText(toon .. "\n" .. msg)
  MailCommanderSplitLabel:Show()
  return
end
function addon:ClickedOnItem(itemButton,button)
	local shift,ctrl,alt=IsShiftKeyDown(),IsControlKeyDown(),IsAltKeyDown()
	local itemLink=itemButton:GetAttribute("itemlink")
	local itemId=parseLink(itemLink)
	local toon=currentTab==INEED and currentRequester or currentReceiver
	dirty=true
	if not itemLink then
		if currentTab==INEED then
			if GetCursorInfo() then
				self:OnItemDropped(itemButton)
			end
		end
		return
	end
  if currentTab==ICATEGORIES then
    if button=="RightButton" then
      dbcategory[currentCategory].list[itemId]=nil
    elseif button=="LeftButton" then
      print("Trying to set icon to itemid",itemId,"for",currentCategory)
      dbcategory[currentCategory].t=db.items[itemId].t
    end
    self:RenderPresets()
    self:UpdateMailCommanderFrame()
    return
  end
  if button=="LeftButton" then
    if not alt then
    	if shift and ctrl then
    		return self:ShowSplitter('res',thisToon,itemButton,itemId,C:Cyan())
    	end
    	if shift then
    		return self:ShowSplitter('cap',toon,itemButton,itemId,C:Green())
    	end
    	if ctrl then
    		return self:ShowSplitter('keep',toon,itemButton,itemId,C:Yellow())
    	end
  	end
	end
	if currentTab==ISEND then
		if (button=="LeftButton") then
		  DontSendNow[itemId] = not DontSendNow[itemId]
			if addon:IsDisabled(itemId) then
				itemButton.Disabled:Show()
			else
				itemButton.Disabled:Hide()
			end
			return self:OnItemEnter(itemButton,button)
		elseif button=="RightButton" then
		  self:Debug(currentToon(),self:CanSendMail(),itemId)
			if not self:CanSendMail() then
				return
			end
			self:Mail(itemId)
			self:ScheduleTimer("FireMail",0.05)
		end
	elseif currentTab==INEED then
		if button=="LeftButton" then
			if (itemId and toon) then
			 self:Debug(alt)
        if type(db.toons[toon].requests[itemId])~="table" then db.toons[toon].requests[itemId]={} end
        if alt then
          db.toons[toon].requests[itemId]['ALL']= not db.toons[toon].requests[itemId]['ALL']
        else
          db.toons[toon].requests[itemId][thisToon]= not db.toons[toon].requests[itemId][thisToon]
        end
         DevTools_Dump(db.toons[toon].requests[itemId])
				if addon:IsDisabled(itemId) then
					itemButton.Disabled:Show()
				else
					itemButton.Disabled:Hide()
				end
				self:OnItemEnter(itemButton,button)
			else
			--@debug@
			self:Debug("Error:",itemId,toon)
			--@end-debug@
			end
		elseif button=="RightButton" then
  		  db.toons[currentRequester].requests[itemId]=nil
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
function addon:TipColor(c,enabled)
  if enabled then
    return c.r,c.g,c.b,GREEN_FONT_COLOR.r,GREEN_FONT_COLOR.g,GREEN_FONT_COLOR.b
  else
    return c.r,c.g,c.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b
  end
end
function addon:OnItemEnter(itemButton,motion)
	local section=itemButton:GetAttribute("section")
	GameTooltip:SetOwner(itemButton,"ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	local ENABLEME=ENABLE .. ' for ' .. thisToon
  local DISABLEME=DISABLE .. ' for ' .. thisToon
  local ENABLEALL=ENABLE .. ' for all toons (takes precedence)'
  local DISABLEALL=DISABLE .. ' for all toons (takes precedence)'
  local ENABLESEND=ENABLE
  local DISABLESEND=DISABLE .. ' sending this item just once'
	if section =="items" then
		local itemlink=itemButton:GetAttribute('itemlink')
		if itemlink then
			--GameTooltip:SetHyperlink(itemlink)
			GameTooltip:AddLine(itemlink:gsub('[%]%[]',''))
      local itemId=parseLink(itemlink)
      local disabled,disabledAll,disabledMe=addon:IsDisabled(itemId)
      local color1=C.White
      local color2=disabled and GREEN_FONT_COLOR or RED_FONT_COLOR
			if currentTab == ICATEGORIES then
          GameTooltip:AddDoubleLine(KEY_BUTTON1,L["Use as category Icon"],color1.r,color1.g,color1.b,GREEN_FONT_COLOR.r,GREEN_FONT_COLOR.g,GREEN_FONT_COLOR.b)
          GameTooltip:AddDoubleLine(KEY_BUTTON2,REMOVE,color1.r,color1.g,color1.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
			else
  			local toon=currentToon()
        local info = type(itemId)=="string" and presets[itemId] or nil
        local split= not (info and info.nosplit or nil)
        local keepMsg= info and info.keep or L['Set min storage']
        local capMsg= info and info.cap or L['Set max storage']
  			if currentTab==INEED then
          GameTooltip:AddDoubleLine(KEY_BUTTON1,(disabledMe and ENABLEME or DISABLEME),self:TipColor(color1,disabledMe))
          GameTooltip:AddDoubleLine(ALT_KEY_TEXT .. ' - ' .. KEY_BUTTON1,(disabledAll and ENABLEALL or DISABLEALL),self:TipColor(color1,disabledAll))
  				if disabledAll then
  					GameTooltip:AddLine(L["This item has been disabled for ALL toons"],C:Orange())
          elseif disabledMe then
            GameTooltip:AddLine(L["This item has been disabled only for "] .. thisToon,C:Orange())
  				end
  				GameTooltip:AddDoubleLine(KEY_BUTTON2,REMOVE,color1.r,color1.g,color1.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
  			else
          GameTooltip:AddDoubleLine(KEY_BUTTON1,(DontSendNow[itemId] and ENABLESEND or DISABLESEND),self:TipColor(color1,DontSendNow[itemId]))
  				if disabled then GameTooltip:AddLine(format(L["Disabled items are not sent with \"%s\" button"],L["Send All"]),C:Orange()) end
  				GameTooltip:AddDoubleLine(KEY_BUTTON2,L["Add to sendmail panel"],color1.r,color1.g,color1.b,GREEN_FONT_COLOR.r,GREEN_FONT_COLOR.g,GREEN_FONT_COLOR.b)
  			end
  			GameTooltip:AddLine("Settings for " .. toon,C:Orange())
  			if split then
  				GameTooltip:AddDoubleLine(CTRL_KEY_TEXT .. ' - ' .. KEY_BUTTON1,keepMsg..' (Min)' ,color1.r,color1.g,color1.b,C:Yellow())
  				GameTooltip:AddDoubleLine(SHIFT_KEY_TEXT .. ' - ' .. KEY_BUTTON1,capMsg..' (Max)' ,color1.r,color1.g,color1.b,C:Green())
          GameTooltip:AddDoubleLine("Min:",keep(toon,itemId),C.White.r,C.White.g,C.White.b,C:Yellow())
          GameTooltip:AddDoubleLine("Max:",cap(toon,itemId)==CAP and 'N/A' or cap(toon,itemId),C.White.r,C.White.g,C.White.b,C:Green())
  			end
  			local qt=GetItemCount(itemId)-bags[itemId]
  			if info then qt=Count:Sendable(itemId,toon) end
  			GameTooltip:AddLine("Availability on " .. C(thisToon,'Green'),C:Orange())
  			if split then
  				GameTooltip:AddDoubleLine(CTRL_KEY_TEXT .. ' - ' .. SHIFT_KEY_TEXT .. '-' .. KEY_BUTTON1,L["Set reserved"] ,color1.r,color1.g,color1.b,C:Cyan())
  			end
  			GameTooltip:AddDoubleLine("Total:",qt,nil,nil,nil,C:Silver())
  			if split then
  				GameTooltip:AddDoubleLine("Reserved:",keep(thisToon,itemId),nil,nil,nil,C:Cyan())
  				GameTooltip:AddDoubleLine("Sendable:",math.max(0,qt-keep(thisToon,itemId)),nil,nil,nil,C:White())
  			else
  				GameTooltip:AddDoubleLine("Sendable:",qt,nil,nil,nil,C:White())
  			end
  --@debug@
  			GameTooltip:AddDoubleLine("Id:",itemId,C:Silver())
  			GameTooltip:AddDoubleLine("Sending:",sending[itemId],C:Silver())
  			GameTooltip:AddDoubleLine("Tobesent:",tobesent[itemId],C:Silver())
  --@end-debug@
        if IsShiftKeyDown() then
          local t=self:NewTable()
          for bagId,slotId in Bags() do
            if presets.boe:validate(nil,toon,bagId,slotId) then
              local loc = ItemLocation:CreateFromBagAndSlot(bagId,slotId)
               local itemLink=C_Item.GetItemName(loc)
               if t[itemLink] then
                t[itemLink]=t[itemLink]+1
               else
                t[itemLink]=1
               end
            end
          end
          for k,v in pairs(t) do
            GameTooltip:AddDoubleLine(k,v)
          end
          DevTools_Dump(t)
          self:DelTable(t)
        end
      end
		else
			GameTooltip:SetText(L["Dragging an item here will add it to the list"])
		end
	elseif section=="toons" then
		local name=itemButton:GetAttribute('toon')
		if name then
			local enabled=not self:IsIgnored(name)
			local color1=C.White
			local color2=enabled and GREEN_FONT_COLOR or RED_FONT_COLOR
			GameTooltip:AddLine(toonTable[name].text)
			GameTooltip:AddLine(toonTable[name].tooltip)
			GameTooltip:AddDoubleLine(KEY_BUTTON1,enabled and DISABLE or ENABLE,color1.r,color1.g,color1.b,color2.r,color2.g,color2.b)
			GameTooltip:AddLine(L["Disabled toons will not appear in any list"],C:Orange())
			GameTooltip:AddDoubleLine(KEY_BUTTON2,REMOVE,color1.r,color1.g,color1.b,RED_FONT_COLOR.r,RED_FONT_COLOR.g,RED_FONT_COLOR.b)
			GameTooltip:AddLine(L["Use to remove deleted toons"],C:Orange())
      GameTooltip:AddDoubleLine(SHIFT_KEY_TEXT .. '-'  .. KEY_BUTTON1,L["Edit"],color1.r,color1.g,color1.b,C:Yellow())
      GameTooltip:AddLine(L["You can adjust class, level, faction and tradeskills"],C:Orange())

		end
	elseif section=="drop" then
		GameTooltip:AddLine(L["Temporary item slot"],C:Green())
		local itemlink=itemButton:GetAttribute('itemlink')
		if itemlink then
			GameTooltip:SetHyperlink(itemlink)
		end
		GameTooltip:AddLine(L["Items dropped here can be redropped everywhere"])
    GameTooltip:AddLine(KEY_BUTTON2 .. " " .. L["clears the slot"])
	elseif section=="presets" then
		local itemlink=itemButton:GetAttribute('itemlink')
		GameTooltip:AddLine(L["Click to add to current toon"],C:Green())
		GameTooltip:AddLine(presets[itemlink].l)
  elseif section=="categories" then
    local itemlink=itemButton:GetAttribute('itemlink')
    GameTooltip:AddLine(L["Click to add to current toon"],C:Green())
    GameTooltip:AddLine(itemlink)
	end
  --@debug@
	GameTooltip:AddDoubleLine("Section",section,C:Silver())
  GameTooltip:AddDoubleLine("Width",GameTooltip:GetWidth(),C:Silver())
  --@end-debug@
  GameTooltip:SetWidth(500)
	GameTooltip:Show()
end
function addon:OnArrowsClick(this)
	self:RenderButtonList(mcf.store,this:GetID())
end
function addon:ResetPanel()
        mcf.Info:Hide()
        mcf.InfoClick:Hide()
        mcf.AddContact:Hide()
        mcf.AddCategory:Hide()
        mcf.RemoveCategory:Hide()
        mcf.Filter:Hide()
        mcf.All:Hide()
        mcf.Delete:Hide()
        mcf.Send:Hide()
        wipe(DontSendNow)
        for _,f in ipairs(mcf.Additional) do
          f:Hide()
        end
        for _,f in pairs(mcf.Items) do
          f:Hide()
        end
        if SendMailFrame:IsVisible() then
          PanelTemplates_EnableTab(mcf,ISEND)
        else
          PanelTemplates_DisableTab(mcf,ISEND)
        end
end
function addon:OnTabClick(tab)
  if (extraToon) then extraToon:Hide() extraToon:Reset() end
  self:ResetPanel()
	PanelTemplates_SetTab(mcf, tab:GetID())
	currentTab=mcf.selectedTab
	if currentTab==INEED then
		self:StartTooltips()
	else
		self:StopTooltips()
	end
	print("tabclick",tab)
	self:UpdateMailCommanderFrame()
end
function addon:UpdateMailCommanderFrame()
	if mcf.selectedTab==INEED then
    --self:InitializeDropDown(mcf.filter)
    addon:RenderPresets()
		addon:RenderNeedBox(mcf)
    UIDropDownMenu_Initialize(mcf.Filter, function(...) self:InitializeDropDown(...) end );
	elseif mcf.selectedTab==ISEND then
	 print(1,addon:GetFilter(),currentReceiver)
   print(2,addon:GetFilter(),currentReceiver)
    --self:InitializeDropDown(mcf.filter)
		addon:RenderSendBox(mcf)
    UIDropDownMenu_Initialize(mcf.Filter, function(...) self:InitializeDropDown(...) end );
   print(3,addon:GetFilter(),currentReceiver)
	elseif mcf.selectedTab==IFILTER then
		addon:RenderFilterBox(mcf)
	elseif mcf.selectedTab==ICATEGORIES then
    --self:InitializeDropDownForCats(mcf.filter)
    addon:RenderPresets()
		addon:RenderCategoryBox(mcf)
    UIDropDownMenu_Initialize(mcf.Filter, function(...) self:InitializeDropDownForCats(...) end );
	else
--@debug@
		print("Invalid tab",mcf.selectedTab)
--@end-debug@
		return
	end
end
function addon:LoadItem(itemButton,itemLink,store,index)
  print(itemButton,itemLink,store,index)
  if (not I:IsBop(itemLink)) then
    local itemID=self:GetItemID(itemLink)
    store[itemID]=true
    if not db.items[itemID] then
      db.items[itemID]={t=QUESTIONMARK_ICON,l=itemLink}
    end
    db.items[itemID].t=GetItemIcon(itemID)
    db.items[itemID].l=itemLink
    self:RefreshSendable(true)
    dirty=true
  else
    self:Popup(C("Mailcommander","Orange").. "\n" .. L["You cant mail soulbound items"])
  end
end
function addon:OnItemDropped(itemButton)
	dirty=true
	local type,itemID,itemLink=GetCursorInfo()
	print(type,itemID,itemLink)
	--local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID)
	if type=="item" then
		if not itemLink then itemLink = select(2,GetItemInfo(itemID)) end
	elseif type=="merchant" then
		itemLink = GetMerchantItemLink(itemID)
	else
		return
	end
	local texture=GetItemIcon(itemLink) or QUESTIONMARK_ICON
	ClearCursor()
	if itemButton:GetName()=="MailCommanderFrameAdditionalItemButton" then
		self:SetAdditional(itemLink,texture)
		return
	end
	ClearCursor()
  if currentTab==INEED then
	 local index=self:GetFilter()
	 if index ~= NONAME then self:LoadItem(itemButton,itemLink,db.toons[index].requests,index) end
  elseif currentTab==ICATEGORIES then
   local index=currentCategory
   if index ~= NONAME then self:LoadItem(itemButton,itemLink,dbcategory[index].list,index) end
  else
    return
  end
	if currentTab==INEED or currentTab==ICATEGORIES then
	end
	self:UpdateMailCommanderFrame()
end
function addon:Reset(input,...)
	local message=C("Mailcommander","Orange").. "\n" ..  L["Are you sure you want to erase all data?"]
	addon:Popup(message,0,
			function(this)
				addon.db:ResetDB(addon.db:GetCurrentProfile())
				addon.db.global.dbversion=2
				ReloadUI()
			end,
			function() end
		)
end
function addon:a1(tip,link)
	print("a1")
	return self:attachItemTooltip(tip,link)
end
function addon:a2(tip,link)
	print("a2")
	return self:attachItemTooltip(tip,link)
end
function addon:a3(tip,link)
	print("a3")
	return self:attachItemTooltip(tip,link)
end
function addon:a4(tip,link)
	print("a4")
	return self:attachItemTooltip(tip,link)
end
function addon:a5(tip,link)
	print("a5")
	return self:attachItemTooltip(tip,link)
end
function addon:a6(tip,link)
	print("a6")
	return self:attachItemTooltip(tip,link)
end
function addon:a7(tip,link)
	print("a7")
	return self:attachItemTooltip(tip,link)
end
function addon:a8(tip,link)
	print("a8")
	return self:attachItemTooltip(tip,link)
end
local draggables={}
function addon:attachItemTooltip(tip,link,...)
	if not link and tip.GetItem then link=select(2,tip:GetItem()) end
	if link then
		local type,id = link:match("H(%a+):(%d*):")
		local mousefocus=GetMouseFocus()
		if (id == "" or id == "0") and TradeSkillFrame ~= nil and TradeSkillFrame:IsVisible() and mousefocus.reagentIndex then
			local selectedRecipe = TradeSkillFrame.RecipeList:GetSelectedRecipeID()
			for i = 1, 8 do
				if mousefocus.reagentIndex == i then
				  id = C_TradeSkillUI.GetRecipeReagentItemLink(selectedRecipe, i):match("item:(%d+):") or nil
				  break
				end
			end
		end
		if id then
			if not draggables[mousefocus] then
				self:SecureHookScript(mousefocus,"OnDragStart","Pickup")
				mousefocus:RegisterForDrag("LeftButton")
				draggables[mousefocus]=true
			end
			currentID=id
			tip:AddLine(me,C.Orange())
			tip:AddLine(GetBindingText(GetBindingKey("MCPickup")) .. " to pickup",C.Green())
			tip:Show()
		end
	end
end
function addon:Pickup(itemid)
	if mcf:IsVisible() and mcf.selectedTab==INEED then
		if currentID and not GetCursorInfo() then
			print(currentID)
			PickupItem(currentID)
		end
	end
end
function addon:OnAddCategoryEnter(this)
  local tip=GameTooltip
  tip:SetOwner(this,"ANCHOR_CURSOR")
  tip:AddLine(L["Create a new custom category"])
  tip:Show()
end
function addon:OnRemoveCategoryEnter(this)
  local tip=GameTooltip
  tip:SetOwner(this,"ANCHOR_CURSOR")
  tip:AddLine(L["Remove a custom category"])
  tip:Show()
end
local function DeleteCategory(self,category)
  dbcategory[category]=nil
  currentCategory=NONAME
  for toon,data in pairs(db.toons) do
    data.requests[category]=nil
  end
  addon:UpdateMailCommanderFrame()
end
function addon:ShowRemoveCategory()
  self:Popup(C("Mailcommander","Orange").. "\n" .. L["Are you sure you want to remove '%s'?"]:format(currentCategory),3600,DeleteCategory,true,currentCategory)
end

do
  local dialogName
  function addon:ShowAddCustomToon()
    if not dialogName then dialogName=self:BuildAddContact() end
    StaticPopup_Show(dialogName,"","")
  end
end
function addon:BuildAddContact()
  local name="MAILCOMMANDER_ADDCONTACT"
  local i=0
  while StaticPopupDialogs[name] do
    i=i+1
    name = name .. tostring(i)
  end
-- Custom static popup
StaticPopupDialogs[name] = {
  text = C("Mailcommander","Orange").. "\n" .. CHARACTER_NAME_PROMPT,
  button1 = ADD,
  button2 = CANCEL,
  hasEditBox = 1,
  autoCompleteSource = GetAutoCompleteResults,
  autoCompleteArgs = { AUTOCOMPLETE_LIST.ALL.include, AUTOCOMPLETE_LIST.ALL.exclude },
  maxLetters = 31,
  whileDead = 1,
  OnHide = function(self)
    ChatEdit_FocusActiveWindow();
    self.editBox:SetText("");
  end,
  OnAccept = function(self, data)
    _G.MailCommander:AddCustomToon(self.editBox:GetText())
    self.editBox:SetText("");
  end,
  timeout = 0,
  EditBoxOnEnterPressed = function(self, data)
    local parent = self:GetParent();
    local editBox = parent.editBox;
    _G.MailCommander:AddCustomToon(self.editBox:GetText())
    editBox:SetText("");
    parent:Hide();
  end,
  EditBoxOnEscapePressed = function(self)
    self:GetParent():Hide();
  end,
  hideOnEscape = 1
}
return name
end
do
  local dialogName
  function addon:ShowAddCategory()
    if not dialogName then dialogName=self:BuildAddCategory() end
    StaticPopup_Show(dialogName,"","")
  end
end
function addon:BuildAddCategory()
  local name="MAILCOMMANDER_ADDCATEGORY"
  local i=0
  while StaticPopupDialogs[name] do
    i=i+1
    name = name .. tostring(i)
  end
-- Custom static popup
StaticPopupDialogs[name] = {
  text = C("Mailcommander","Orange").. "\n" .. CATEGORY,
  button1 = ADD,
  button2 = CANCEL,
  hasEditBox = 1,
  maxLetters = 31,
  whileDead = 1,
  OnHide = function(self)
    ChatEdit_FocusActiveWindow();
    self.editBox:SetText("");
  end,
  OnAccept = function(self, data)
    _G.MailCommander:AddCustomCategory(self.editBox:GetText())
    self.editBox:SetText("");
  end,
  timeout = 0,
  EditBoxOnEnterPressed = function(self, data)
    local parent = self:GetParent();
    local editBox = parent.editBox;
    _G.MailCommander:AddCustomCategory(self.editBox:GetText())
    editBox:SetText("");
    parent:Hide();
  end,
  EditBoxOnEscapePressed = function(self)
    self:GetParent():Hide();
  end,
  hideOnEscape = 1
}
return name
end
do
  local dialogName
  function addon:ShowAddItemid()
    if not dialogName then dialogName=self:BuildAddItemid() end
    StaticPopup_Show(dialogName,"","")
  end
end
function addon:BuildAddItemid()
  local name="MAILCOMMANDER_ADDITEMID"
  local i=0
  while StaticPopupDialogs[name] do
    i=i+1
    name = name .. tostring(i)
  end
-- Custom static popup
StaticPopupDialogs[name] = {
  text = C("Mailcommander","Orange").. "\n\n" .. L["You can directly enter an itemid to be loaded in the temporary slot"],
  button1 = ADD,
  button2 = CANCEL,
  hasEditBox = 1,
  maxLetters = 31,
  whileDead = 1,
  OnHide = function(self)
    ChatEdit_FocusActiveWindow();
    self.editBox:SetText("");
  end,
  OnAccept = function(self, data)
    _G.MailCommander:AddCustomItemid(self.editBox:GetText())
    self.editBox:SetText("");
  end,
  timeout = 0,
  EditBoxOnEnterPressed = function(self, data)
    local parent = self:GetParent();
    local editBox = parent.editBox;
    _G.MailCommander:AddCustomItemid(self.editBox:GetText())
    editBox:SetText("");
    parent:Hide();
  end,
  EditBoxOnEscapePressed = function(self)
    self:GetParent():Hide();
  end,
  hideOnEscape = 1
}
return name
end
function addon:AddCustomItemid(itemid)
  --153703
  self:Debug("Add Custom Id")
  local id,_,_,_,t=GetItemInfoInstant(itemid)
  if id then
      local n,l=GetItemInfo(id)
      if not l then
        l=pseudolink:format(id,L["Loading Data"])
      end
      self:SetAdditional(l,t)
      local item = Item:CreateFromItemID(id)
      item:ContinueOnItemLoad(function()
        addon:SetAdditional(item:GetItemLink(),item:GetItemIcon())
      end)
  else
      C_Timer.After(0.1,function() addon:Popup( C("MailCommander","Orange").. "\n\n" .. '"' ..tostring(itemid) .. '" '  .. L["not found"]) end )
  end
end
function addon:LoadProfessions()
  do
    local skills={
      Inscription=773,
      Jewelcrafting=755,
      Skinning=393,
      Enchanting=333,
      Engineering=202,
      Tailoring=197,
      Mining=186,
      Herbalism=182,
      Alchemy=171,
      Leatherworking=165,
      Blacksmithing=164
    }
    --skills=C_TradeSkillUI.GetAllProfessionTradeSkillLines()
    local load
    function load()
      for key, var in pairs(skills) do
        tinsert(professions, C_TradeSkillUI.GetTradeSkillDisplayName(var))
        coroutine.yield()
      end
      tsort(professions)
    end
    self:coroutineExecute(0.05,load)
  end
end
_G.MailCommander=addon
--@debug@
_G.MCOM=addon
_G.MCOM.sendable=sendable
_G.MCOM.toonTable=toonTable
_G.MCOUNT=Count

--@end-debug@

-- Key Bindings Names
_G.BINDING_HEADER_MAILCOMMANDER="MailCommander"
_G.BINDING_NAME_MCConfig=L["Requests Configuration"]
