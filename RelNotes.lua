local me,ns=...
local hlp=LibStub("LibInit"):GetAddon(me)
local L=hlp:GetLocale()
function hlp:loadHelp()
self:HF_Title(me,"RELNOTES")
self:HF_Paragraph("Description")
self:Wiki([[
Mail Commander allows you to define a per character list of needs which wil be displayed when you open the sendmail panel allowing you to send all requested items or just some of them.
You can make this selection permament, disabling some kind of items, or just cherry pick each time
You can also use the "Send all" button to have all enabled items sent with a single click
]])
self:RelNotes(2,0,2,[[
  Fix: MailCommander\MailCommander-2.0.1 90100.lua:403: Usage: GetItemInfoInstant(itemID|"name"|"itemlink")
]])
self:RelNotes(2,0,1,[[
 Fix: MailCommander\MailCommander-2.0.0 90100.lua:1099: bad argument #1 to 'pairs' (table expected, got nil)
]])
self:RelNotes(2,0,0,[[
 Feature: now you can create custom categories
]])
self:RelNotes(1,0,1,[[
Feature: 8.3.0
]])
self:RelNotes(1,0,0,[[
Feature: 8.2.5
Fix: long standing bug, was trying to send bound bind on equip items
]])
self:RelNotes(0,9,11,[[
Feature: 8.2
]])
self:RelNotes(0,9,10,[[
Fix: Lua error line 1704 attempt tp indes global 'StackSplitText' (a null value)
]])
self:RelNotes(0,9,4,[[
Update: Updated boa tokens with 7.3 data
]])
self:RelNotes(0,9,0,[[
Feature: The add button is now always shown on the first page
Fix: no longer count equipped bags as sendable items
Fix: actually run sync scan when opening panels
Feature: Costly operations moved to coroutine
Fix: Restored drag and drop from from tradeskill windows
Fix: Workaround to skip Blizzard confirmation when sending mail to toons on the same realm
]])

end

