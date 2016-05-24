local me,ns = ...

ns.wowhead_update=1464071579
-- Classes masks
ns.classes=
{
	PALADIN = {
		id = 2,
		enUS = "Paladin",
		mask = 2
	},
	SHAMAN = {
		id = 7,
		enUS = "Shaman",
		mask = 64
	},
	MAGE = {
		id = 8,
		enUS = "Mage",
		mask = 128
	},
	WARRIOR = {
		id = 1,
		enUS = "Warrior",
		mask = 1
	},
	DRUID = {
		id = 11,
		enUS = "Druid",
		mask = 1024
	},
	WARLOCK = {
		id = 9,
		enUS = "Warlock",
		mask = 256
	},
	PRIEST = {
		id = 5,
		enUS = "Priest",
		mask = 16
	},
	MONK = {
		id = 10,
		enUS = "Monk",
		mask = 512
	},
	ROGUE = {
		id = 4,
		enUS = "Rogue",
		mask = 8
	},
	DEATHKNIGHT = {
		id = 6,
		enUS = "Death Knight",
		mask = 32
	},
	HUNTER = {
		id = 3,
		enUS = "Hunter",
		mask = 4
	}
}

-- DataMined from WowHead items?filter=cr=133:152;crs=1:6;crv=0:0 on 24/05/2016
-- Scraped 16 items
-- DataMined from WowHead items?filter=cr=133:152;crs=1:11;crv=0:0 on 24/05/2016
-- Scraped 18 items
-- DataMined from WowHead items?filter=cr=133:152;crs=1:3;crv=0:0 on 24/05/2016
-- Scraped 16 items
-- DataMined from WowHead items?filter=cr=133:152;crs=1:8;crv=0:0 on 24/05/2016
-- Scraped 17 items
ns.classBoa=
{
	["127781"] = 400,
	["128473"] = 400,
	["102322"] = 1544,
	["102274"] = 68,
	["127796"] = 1544,
	["127778"] = 400,
	["128472"] = 1544,
	["102263"] = 35,
	["102275"] = 68,
	["127805"] = 68,
	["127777"] = 400,
	["127817"] = 35,
	["102280"] = 1544,
	["102272"] = 68,
	["127795"] = 1544,
	["102290"] = 400,
	["102288"] = 400,
	["102284"] = 400,
	["127809"] = 68,
	["102277"] = 1544,
	["102271"] = 68,
	["102264"] = 35,
	["102289"] = 400,
	["127780"] = 400,
	["127820"] = 35,
	["102276"] = 68,
	["127793"] = 1544,
	["102282"] = 1544,
	["127819"] = 35,
	["127806"] = 68,
	["127779"] = 400,
	["127803"] = 68,
	["127783"] = 400,
	["127808"] = 68,
	["127784"] = 400,
	["127807"] = 68,
	["102281"] = 1544,
	["127797"] = 1544,
	["127816"] = 35,
	["102278"] = 1544,
	_lastupdate = 1464071579,
	["102321"] = 400,
	["102273"] = 68,
	["102279"] = 1544,
	["102287"] = 400,
	["127790"] = 1544,
	["127822"] = 35,
	["102323"] = 68,
	["127791"] = 1544,
	["102283"] = 1544,
	["102285"] = 400,
	["127810"] = 68,
	["127794"] = 1544,
	["102320"] = 35,
	["102268"] = 35,
	["127792"] = 1544,
	["102267"] = 35,
	["127782"] = 400,
	["127821"] = 35,
	["127823"] = 35,
	["102265"] = 35,
	["102270"] = 68,
	["127804"] = 68,
	["102269"] = 35,
	["94604"] = 1024,
	["102266"] = 35,
	["102286"] = 400,
	["127818"] = 35
}

-- DataMined from WowHead items?filter=na=battlestone;cr=133;crs=1;crv=0 on 24/05/2016
-- Scraped 11 items
ns.battlestones={92665,92675,92676,92677,92678,92679,92680,92681,92682,92683,98715}
-- DataMined from WowHead items?filter=na=training;cr=133;crs=1;crv=0 on 24/05/2016
-- Scraped 12 items
ns.trainingstones={116374,116416,116417,116418,116419,116420,116421,116422,116423,116424,116429,127755}
