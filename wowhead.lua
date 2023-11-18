local me,ns = ...

ns.wowhead_update=1505985201
-- Classes masks
ns.classes=
{
  DEATHKNIGHT = {
    id = 6,
    mask = 32,
    enUS = "Death Knight"
  },
  WARRIOR = {
    id = 1,
    mask = 1,
    enUS = "Warrior"
  },
  ROGUE = {
    id = 4,
    mask = 8,
    enUS = "Rogue"
  },
  MAGE = {
    id = 8,
    mask = 128,
    enUS = "Mage"
  },
  PRIEST = {
    id = 5,
    mask = 16,
    enUS = "Priest"
  },
  HUNTER = {
    id = 3,
    mask = 4,
    enUS = "Hunter"
  },
  WARLOCK = {
    id = 9,
    mask = 256,
    enUS = "Warlock"
  },
  DEMONHUNTER = {
    id = 12,
    mask = 2048,
    enUS = "Demon Hunter"
  },
  SHAMAN = {
    id = 7,
    mask = 64,
    enUS = "Shaman"
  },
  DRUID = {
    id = 11,
    mask = 1024,
    enUS = "Druid"
  },
  MONK = {
    id = 10,
    mask = 512,
    enUS = "Monk"
  },
  PALADIN = {
    id = 2,
    mask = 2,
    enUS = "Paladin"
  }
}

-- DataMined from WowHead items?filter=cr=133:152;crs=1:6;crv=0:0 on 21/09/2017
-- Scraped 25 items
-- DataMined from WowHead items?filter=cr=133:152;crs=1:11;crv=0:0 on 21/09/2017
-- Scraped 27 items
-- DataMined from WowHead items?filter=cr=133:152;crs=1:3;crv=0:0 on 21/09/2017
-- Scraped 28 items
-- DataMined from WowHead items?filter=cr=133:152;crs=1:8;crv=0:0 on 21/09/2017
-- Scraped 26 items
ns.classBoa=
{
  ["153155"] = 35,
  ["102280"] = 1544,
  ["127816"] = 35,
  ["127790"] = 3592,
  ["127782"] = 400,
  ["102269"] = 35,
  ["102322"] = 1544,
  ["127805"] = 68,
  ["153148"] = 3592,
  ["127810"] = 68,
  ["153153"] = 35,
  ["127795"] = 3592,
  ["153145"] = 3592,
  ["127780"] = 400,
  ["128472"] = 1544,
  ["127792"] = 3592,
  ["102284"] = 400,
  ["102270"] = 68,
  ["127783"] = 400,
  ["127822"] = 35,
  ["127818"] = 35,
  ["153140"] = 35,
  ["153158"] = 68,
  ["127803"] = 68,
  ["153151"] = 3592,
  ["127809"] = 68,
  ["102273"] = 68,
  ["127819"] = 35,
  ["102263"] = 35,
  ["128473"] = 400,
  ["102321"] = 400,
  ["102290"] = 400,
  ["102289"] = 400,
  ["127820"] = 35,
  ["102264"] = 35,
  ["102277"] = 1544,
  ["102288"] = 400,
  ["102287"] = 400,
  ["127779"] = 400,
  ["127817"] = 35,
  ["153136"] = 3592,
  ["153137"] = 68,
  ["152737"] = 3592,
  ["102279"] = 1544,
  ["153156"] = 400,
  ["127778"] = 400,
  ["127793"] = 3592,
  ["102283"] = 1544,
  ["147294"] = 32,
  ["102285"] = 400,
  ["153149"] = 68,
  ["153139"] = 3592,
  ["153152"] = 68,
  ["127794"] = 3592,
  ["102268"] = 35,
  ["102271"] = 68,
  ["153146"] = 35,
  ["127781"] = 400,
  ["127804"] = 68,
  ["153143"] = 35,
  ["102320"] = 35,
  ["127777"] = 400,
  ["153154"] = 400,
  ["147296"] = 1024,
  ["127808"] = 68,
  ["127797"] = 3592,
  ["127806"] = 68,
  ["153138"] = 68,
  ["152742"] = 400,
  ["102282"] = 1544,
  ["127791"] = 3592,
  ["152738"] = 400,
  ["153147"] = 68,
  ["152743"] = 35,
  ["152734"] = 400,
  ["147298"] = 128,
  ["147770"] = 4,
  ["147580"] = 4,
  ["102267"] = 35,
  ["94604"] = 1024,
  ["102323"] = 68,
  ["153142"] = 3592,
  ["152741"] = 68,
  ["102275"] = 68,
  ["147297"] = 4,
  ["102274"] = 68,
  ["153150"] = 35,
  ["153173"] = 68,
  ["127796"] = 3592,
  ["153144"] = 400,
  ["153141"] = 400,
  ["127807"] = 68,
  ["102266"] = 35,
  ["102286"] = 400,
  ["102278"] = 1544,
  ["102281"] = 1544,
  ["127784"] = 400,
  ["102272"] = 68,
  ["102265"] = 35,
  ["127821"] = 35,
  ["152744"] = 68,
  ["153135"] = 400,
  ["153157"] = 35,
  ["102276"] = 68,
  ["152739"] = 3592,
  ["127823"] = 35
}

-- DataMined from WowHead items?filter=na=battlestone;cr=133;crs=1;crv=0 on 21/09/2017
-- Scraped 21 items
ns.battlestones={
  137387, -- 4Immaculate Dragonkin Battle-Stone
  137388, -- 4Immaculate Humanoid Battle-Stone
  137389, -- 4Immaculate Undead Battle-Stone
  137390, -- 4Immaculate Mechanical Battle-Stone
  137391, -- 4Immaculate Aquatic Battle-Stone
  137392, -- 4Immaculate Magic Battle-Stone
  137393, -- 4Immaculate Critter Battle-Stone
  137394, -- 4Immaculate Beast Battle-Stone
  137395, -- 4Immaculate Elemental Battle-Stone
  137396, -- 4Immaculate Flying Battle-Stone
  92665, -- 5Flawless Elemental Battle-Stone
  92675, -- 5Flawless Beast Battle-Stone
  92676, -- 5Flawless Critter Battle-Stone
  92677, -- 5Flawless Flying Battle-Stone
  92678, -- 5Flawless Magic Battle-Stone
  92679, -- 5Flawless Aquatic Battle-Stone
  92680, -- 5Flawless Mechanical Battle-Stone
  92681, -- 5Flawless Undead Battle-Stone
  92682, -- 5Flawless Humanoid Battle-Stone
  92683, -- 5Flawless Dragonkin Battle-Stone
  98715, -- 5Marked Flawless Battle-Stone
}
-- DataMined from WowHead items?filter=na=training;cr=133;crs=1;crv=0 on 21/09/2017
-- Scraped 13 items
ns.trainingstones={
  153130, -- 1Man'ari Training Amulet
  116374, -- 7Beast Battle-Training Stone
  116416, -- 7Humanoid Battle-Training Stone
  116417, -- 7Mechanical Battle-Training Stone
  116418, -- 7Critter Battle-Training Stone
  116419, -- 7Dragonkin Battle-Training Stone
  116420, -- 7Elemental Battle-Training Stone
  116421, -- 7Flying Battle-Training Stone
  116422, -- 7Magic Battle-Training Stone
  116423, -- 7Undead Battle-Training Stone
  116424, -- 7Aquatic Battle-Training Stone
  116429, -- 7Flawless Battle-Training Stone
  127755, -- 7Fel-Touched Battle-Training Stone
  122457, -- 7Ultimate Battle-Training Stone
}
