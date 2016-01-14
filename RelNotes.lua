local me,ns=...
--@do-not-package@
local addon=LibStub("LibInit"):GetAddon(me) --#Addon
local L=addon:GetLocale()
function addon:loadHelp()
self:RelNotes(1,0,0,[[
Feature:
]])
end
--@end-do-not-package@
