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
self:RelNotes(0,9,0,[[
Feature: The add button is now always shown on the first page
Fix: no longer count equipped bags as sendable items
Fix: actually run sync scan when opening panels
Feature: Costly operations moved to coroutine
Fix: Restored drag and drop from from tradeskill windows
Fix: Workaround to skip Blizzard confirmation when sending mail to toons on the same realm
]])

end

