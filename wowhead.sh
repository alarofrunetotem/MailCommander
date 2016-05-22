#!/bin/bash
cd $(dirname $0)
echo -e "local me,ns = ...\n" >wowhead.lua
../wowhelpers/MCClassBoa.php >>wowhead.lua
#../wowhelpers/GCGearTokens.php >>wowhead.lua