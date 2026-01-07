--by Crazydru 
local BCStime
local Bonus=0

local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end
function QuickHeal_Druid_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];

    if RatioHealthy >= RatioFull then
        return QUICKHEAL_SPELL_REGROWTH .. " 总是在战斗中使用 "  .. QUICKHEAL_SPELL_HEALING_TOUCH .. " 将在战斗结束后使用. ";
    else
        if RatioHealthy > 0 then
            return "如果目标血量低于" .. RatioHealthy*100 .. "%，会在战斗中使用" .. QUICKHEAL_SPELL_REGROWTH .. " 否则就使用" .. QUICKHEAL_SPELL_HEALING_TOUCH .. ". ";
        else
            return QUICKHEAL_SPELL_REGROWTH .. " 永远不会被使用. " .. QUICKHEAL_SPELL_HEALING_TOUCH .. " 将总是在战斗中和脱战后使用. ";
        end
    end
end

--by Crazydru 返回unit身上的每跳hot治疗数值
function QuickHeal_GetUnitHotValue(aura,unit)
	local value=0
	unit=unit or "player"
	QuickHeal_ScanningTooltip:SetOwner(QuickHeal_ScanningTooltip, "ANCHOR_NONE")
	if UnitHasAura(unit,aura) then
		local _,i = UnitHasAura(unit,aura)
		QuickHeal_ScanningTooltip:ClearLines()
		QuickHeal_ScanningTooltip:SetUnitBuff(unit, i)
		local text=QuickHeal_ScanningTooltipTextLeft2:GetText() or nil
		_,_,value=string.find(QuickHeal_ScanningTooltipTextLeft2:GetText(), ".*治疗(.%d+)点")
		value=tonumber(value)
	end
	return value
end

function QuickHeal_Druid_FindHealSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
    local ForceHTinCombat = false;
    local NaturesGrace = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediately if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    if multiplier == nil then
        jgpprint(">>> multiplier is NIL <<<")
        --if multiplier > 1.0 then
        --    Overheal = true;
        --end
    elseif multiplier == 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    elseif multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
        Overheal = true;
    end

    -- Determine health and heal need of target
    local healneed;
    local Health;
    if UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target) - HealComm:getHeal(UnitName(Target)); -- Implementatio for HealComm
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = EstimateUnitHealNeed(Target,true);
        Health = UnitHealth(Target)/100;
    end

--by Crazydru 增加BCS进行统计，kook区更新的BCS统计更准确

	BCStime=BCStime or GetTime()-20
	if GetTime()-BCStime>10 then
   	 -- if BonusScanner is running, get +Healing bonus
    	if (BonusScanner) then
        	Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        	debug(string.format("Equipment Healing Bonus: %d", Bonus));
    	end
		if BCS then
			local power,_,_,dmg = BCS:GetSpellPower()
			local heal = BCS:GetHealingPower()
			if dmg == nil then
				power,_,_,dmg = BCS:GetLiveSpellPower()
				heal = BCS:GetLiveHealingPower()
			end
            heal = heal or 0
            power = power or 0
            dmg = dmg or 0
        	Bonus = tonumber(heal)+tonumber(power)-tonumber(dmg);
        	debug(string.format("装备治疗效果: %d", Bonus));
    	end
		BCStime=GetTime()
	end


    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
--by Crazydru该部分需要增加回春治疗系数
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,8); 
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT only
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10); 
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13); 
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Regrowth Talent (increases Regrowth effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,14);
    local iregMod = 10*talentRank/100 + 1;
    debug(string.format("Improved Regrowth talentmodification: %f", iregMod))
   
    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9); 
    local irMod = 5*talentRank/100 + 1;
    debug(string.format("Improved Rejuvenation modifier: %f", irMod));

--by Crazydru 迅捷治愈天赋
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,7);
    local smMod = talentRank;
    debug(string.format("Can use Swiftmend", smMod))

    -- 生命之树形态 - 减少所有治疗技能20%消耗
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,16); 
    local tlMod = 20*talentRank/100;
    debug(string.format("Moonglow modifier: %f", tlMod));

    -- 自然迅捷天赋 - 下一个自然法术瞬发
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,11); 
    local nsMod = talentRank;

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end
--by Crazydru 修改节能施法逻辑
    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

--by Crazydru 屏蔽大迅捷取消树人形态
    -- Detect Nature's Swiftness (next nature spell is instant cast)
    --if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        --debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        --ForceHTinCombat = true;
    --end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -------------------------------------------

    -- Detect Wushoolay's Charm of Nature (Trinket from Zul'Gurub, Madness event)
    if QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect Nature's Grace (next nature spell is hasted by 0.5 seconds)
    --if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") and healneed < ((219*gnMod+healMod25*PF14)*2.8) and
    --        not QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
    --    ManaLeft = 110*tsMod*mgMod;
    --end

    if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") then
        NaturesGrace = true;
    end

    -------------------------------------------

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    --local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);
--by Crazydru
	local SpellIDsSM = nil
	local SMUsable=false
	if smMod ==1 then
		SpellIDsSM = GetSpellIDs(QUICKHEAL_SPELL_SWIFTMEND);
		SMUsable= GetSpellCooldown(SpellIDsSM, "spell")==0 and QuickHealVariables.Swiftmend and (UnitHasAura(Target,QUICKHEAL_SPELL_REJUVENATION) or UnitHasAura(Target,QUICKHEAL_SPELL_REGROWTH) and QuickHeal_GetUnitHotValue(QUICKHEAL_SPELL_REGROWTH,Target) > 60)
	end
	local SpellIDsNS = nil
	local NSUsable=false
	if nsMod ==1 then
		SpellIDsNS = GetSpellIDs(QUICKHEAL_SPELL_NATURES_SWIFTNESS);
		NSUsable= GetSpellCooldown(SpellIDsNS, "spell")==0 and QuickHealVariables.Swiftness and InCombat
	end



    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    --local maxRankRJ = table.getn(SpellIDsRJ);
    
    debug(string.format("Found HT up to rank %d, RG up to rank %d", maxRankHT, maxRankRG));

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for RG
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for HT

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end


-- by Crazydru 修改触使用时机，树人形态下不再用触（除非使用祖格隐藏饰品）
local IsTlForm=UnitHasAura("player",QUICKHEAL_SPELL_TREE_OF_LIFE_FORM)
    if ((TargetIsHealthy or maxRankRG<1 or not InCombat) and not IsTlForm) or ForceHTinCombat then
        -- Not in combat or target is healthy so use the closest available mana efficient healing
        debug(string.format("Not in combat or target healthy or no Regrowth available, will use Healing Touch"))
        if Health < RatioFull then
            SpellID = SpellIDsHT[1]; HealSize = 44*gnMod+healMod15*PF1; -- Default to rank 1
            if healneed > ( 100*gnMod+healMod20*PF8 )*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 and downRankNH >= 2 and SpellIDsHT[2] then SpellID =  SpellIDsHT[2]; HealSize =  100*gnMod+healMod20*PF8 end
            if healneed > ( 219*gnMod+healMod25*PF14)*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 and downRankNH >= 3 and SpellIDsHT[3] then SpellID =  SpellIDsHT[3]; HealSize =  219*gnMod+healMod25*PF14 end
            if healneed > ( 404*gnMod+healMod30)*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 and downRankNH >= 4 and downRankNH >= 4 and SpellIDsHT[4] then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30 end
            if healneed > ( 633*gnMod+healMod35)*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 and downRankNH >= 5 and SpellIDsHT[5] then SpellID =  SpellIDsHT[5]; HealSize =  633*gnMod+healMod35 end
            if healneed > ( 818*gnMod+healMod35)*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 and downRankNH >= 6 and SpellIDsHT[6] then SpellID =  SpellIDsHT[6]; HealSize =  818*gnMod+healMod35 end
            if healneed > (1028*gnMod+healMod35)*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 and downRankNH >= 7 and SpellIDsHT[7] then SpellID =  SpellIDsHT[7]; HealSize = 1028*gnMod+healMod35 end
            if healneed > (1313*gnMod+healMod35)*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 and downRankNH >= 8 and SpellIDsHT[8] then SpellID =  SpellIDsHT[8]; HealSize = 1313*gnMod+healMod35 end
            if healneed > (1656*gnMod+healMod35)*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 and downRankNH >= 9 and SpellIDsHT[9] then SpellID =  SpellIDsHT[9]; HealSize = 1656*gnMod+healMod35 end
            if healneed > (2060*gnMod+healMod35)*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 and downRankNH >= 10 and SpellIDsHT[10] then SpellID = SpellIDsHT[10]; HealSize = 2060*gnMod+healMod35 end
            if healneed > (2472*gnMod+healMod35)*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 and downRankNH >= 11 and SpellIDsHT[11] then SpellID = SpellIDsHT[11]; HealSize = 2472*gnMod+healMod35 end
--by Crazydru
            if UnitHealth(Target)/UnitHealthMax(Target)<0.3 and NSUsable and SpellIDsNS then SpellID = SpellIDsNS; HealSize = HealSize end
            if healneed*100/(100-math.min(QuickHealVariables.Waste,50)) > (888+Bonus*0.8)*irMod*gnMod and ManaLeft >= 199 and SMUsable and SpellIDsSM then SpellID = SpellIDsSM; HealSize = (888+Bonus*0.8)*irMod*gnMod end
        end
    else
        -- target is unhealthy and player has Regrowth
        debug(string.format("In combat and target unhealthy and Regrowth available, will use Regrowth"));
        if Health < RatioFull then
            SpellID = SpellIDsRG[1]; HealSize = (91*gnMod+healModRG*PFRG1)*iregMod; -- Default to rank 1
            if healneed > ( 176*gnMod+healModRG*PFRG2)*iregMod*k and ManaLeft >= 164*tsMod*mgMod and maxRankRG >= 2 and downRankFH >= 2 and SpellIDsRG[2] then SpellID = SpellIDsRG[2]; HealSize =  (176*gnMod+healModRG*PFRG2)*iregMod end
            if healneed > ( 257*gnMod+healModRG)*iregMod*k and ManaLeft >= 224*tsMod*mgMod and maxRankRG >= 3 and downRankFH >= 3 and SpellIDsRG[3] then SpellID = SpellIDsRG[3]; HealSize =  (257*gnMod+healModRG)*iregMod end
            if healneed > ( 339*gnMod+healModRG)*iregMod*k and ManaLeft >= 280*tsMod*mgMod and maxRankRG >= 4 and downRankFH >= 4 and SpellIDsRG[4] then SpellID = SpellIDsRG[4]; HealSize =  (339*gnMod+healModRG)*iregMod end
            if healneed > ( 431*gnMod+healModRG)*iregMod*k and ManaLeft >= 336*tsMod*mgMod and maxRankRG >= 5 and downRankFH >= 5 and SpellIDsRG[5] then SpellID = SpellIDsRG[5]; HealSize =  (431*gnMod+healModRG)*iregMod end
            if healneed > ( 543*gnMod+healModRG)*iregMod*k and ManaLeft >= 408*tsMod*mgMod and maxRankRG >= 6 and downRankFH >= 6 and SpellIDsRG[6] then SpellID = SpellIDsRG[6]; HealSize =  (543*gnMod+healModRG)*iregMod end
            if healneed > ( 686*gnMod+healModRG)*iregMod*k and ManaLeft >= 492*tsMod*mgMod and maxRankRG >= 7 and downRankFH >= 7 and SpellIDsRG[7] then SpellID = SpellIDsRG[7]; HealSize =  (686*gnMod+healModRG)*iregMod end
            if healneed > ( 857*gnMod+healModRG)*iregMod*k and ManaLeft >= 592*tsMod*mgMod and maxRankRG >= 8 and downRankFH >= 8 and SpellIDsRG[8] then SpellID = SpellIDsRG[8]; HealSize =  (857*gnMod+healModRG)*iregMod end
            if healneed > (1061*gnMod+healModRG)*iregMod*k and ManaLeft >= 704*tsMod*mgMod and maxRankRG >= 9 and downRankFH >= 9 and SpellIDsRG[9] then SpellID = SpellIDsRG[9]; HealSize = (1061*gnMod+healModRG)*iregMod end
--by Crazydru
            if UnitHealth(Target)/UnitHealthMax(Target)<0.3 and NSUsable and SpellIDsNS then SpellID = SpellIDsNS; HealSize = 0 end
            if healneed*100/(100-math.min(QuickHealVariables.Waste,50)) > (888+Bonus*0.8)*irMod*gnMod and ManaLeft >= 199 and SMUsable and SpellIDsSM then SpellID = SpellIDsSM; HealSize = (888+Bonus*0.8)*irMod*gnMod end
        end
    end
    
    return SpellID,HealSize*HDB;
end

function QuickHeal_Druid_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;
    local ForceHTinCombat = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    if multiplier == nil then
        jgpprint(">>> multiplier is NIL <<<")
        --if multiplier > 1.0 then
        --    Overheal = true;
        --end
    elseif multiplier == 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    elseif multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
        Overheal = true;
    end

    -- Determine health and heal need of target
    local healneed = healDeficit * multiplier;
    local Health = healDeficit / maxhealth;

--by Crazydru 增加BCS进行统计，kook区更新的BCS统计更准确

	BCStime=BCStime or GetTime()-20
	if GetTime()-BCStime>10 then
   	 -- if BonusScanner is running, get +Healing bonus
    		if (BonusScanner) then
        		Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        		debug(string.format("Equipment Healing Bonus: %d", Bonus));
    		end
		if BCS then
			local power,_,_,dmg = BCS:GetSpellPower()
			local heal = BCS:GetHealingPower()
			if dmg == nil then
				power,_,_,dmg = BCS:GetLiveSpellPower()
				heal = BCS:GetLiveHealingPower()
			end				
            heal = heal or 0
            power = power or 0
            dmg = dmg or 0
        	Bonus = tonumber(heal)+tonumber(power)-tonumber(dmg);
       		debug(string.format("装备治疗效果: %d", Bonus));
    		end
		BCStime=GetTime()
	end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,8);
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT and RG
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10);
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Regrowth Talent (increases Regrowth effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,14);
    local iregMod = 10*talentRank/100 + 1;
    debug(string.format("Improved Regrowth talentmodification: %f", iregMod))

    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    --local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    --local irMod = 5*talentRank/100 + 1;
    --debug(string.format("Improved Rejuvenation modifier: %f", irMod));


    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

--by Crazydru 修改节能施法逻辑
    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

--by Crazydru 屏蔽大迅捷取消树人形态
    -- Detect Nature's Swiftness (next nature spell is instant cast)
    --if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        --debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        --ForceHTinCombat = true;
    --end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -------------------------------------------

    -- Detect Wushoolay's Charm of Nature (Trinket from Zul'Gurub, Madness event)
    if QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        ForceHTinCombat = true;
    end

    -- Detect Nature's Grace (next nature spell is hasted by 0.5 seconds)
    if QuickHeal_DetectBuff('player',"Spell_Nature_NaturesBlessing") and healneed < ((219*gnMod+healMod25*PF14)*2.8) and
            not QuickHeal_DetectBuff('player',"Spell_Nature_Regenerate") then
        ManaLeft = 110*tsMod*mgMod;
    end

    -------------------------------------------

    ---- Get total healing modifier (factor) caused by healing target debuffs
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    --local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);


    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    --local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d", maxRankHT, maxRankRG));

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for RG
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for HT

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end

    --if UnitLevel('player') < 60 then
    --    print('f:QuickHeal_Druid_FindHealSpellToUseNoTarget --you are not 60');
    --else
    --    print('f:QuickHeal_Druid_FindHealSpellToUseNoTarget --you are 60');
    --end

-- by Crazydru 修改触使用时机，树人形态下不再用触（除非使用大迅捷或者祖格隐藏饰品）
local IsTlForm=UnitHasAura("player",QUICKHEAL_SPELL_TREE_OF_LIFE_FORM)
    if not forceMaxHPS and not IsTlForm then
        SpellID = SpellIDsHT[1]; HealSize = 44*gnMod+healMod15*PF1; -- Default to rank 1
        if healneed > ( 100*gnMod+healMod20*PF8 )*k and ManaLeft >=  55*tsMod*mgMod and maxRankHT >=  2 and downRankNH >= 2 and SpellIDsHT[2] then SpellID =  SpellIDsHT[2]; HealSize =  100*gnMod+healMod20*PF8 end
        if healneed > ( 219*gnMod+healMod25*PF14)*K and ManaLeft >= 110*tsMod*mgMod and maxRankHT >=  3 and downRankNH >= 3 and SpellIDsHT[3] then SpellID =  SpellIDsHT[3]; HealSize =  219*gnMod+healMod25*PF14 end
        if healneed > ( 404*gnMod+healMod30)*K and ManaLeft >= 185*tsMod*mgMod and maxRankHT >=  4 and downRankNH >= 4 and SpellIDsHT[4] then SpellID =  SpellIDsHT[4]; HealSize =  404*gnMod+healMod30 end
        if healneed > ( 633*gnMod+healMod35)*K and ManaLeft >= 270*tsMod*mgMod and maxRankHT >=  5 and downRankNH >= 5 and SpellIDsHT[5] then SpellID =  SpellIDsHT[5]; HealSize =  633*gnMod+healMod35 end
        if healneed > ( 818*gnMod+healMod35)*K and ManaLeft >= 335*tsMod*mgMod and maxRankHT >=  6 and downRankNH >= 6 and SpellIDsHT[6] then SpellID =  SpellIDsHT[6]; HealSize =  818*gnMod+healMod35 end
        if healneed > (1028*gnMod+healMod35)*K and ManaLeft >= 405*tsMod*mgMod and maxRankHT >=  7 and downRankNH >= 7 and SpellIDsHT[7] then SpellID =  SpellIDsHT[7]; HealSize = 1028*gnMod+healMod35 end
        if healneed > (1313*gnMod+healMod35)*K and ManaLeft >= 495*tsMod*mgMod and maxRankHT >=  8 and downRankNH >= 8 and SpellIDsHT[8] then SpellID =  SpellIDsHT[8]; HealSize = 1313*gnMod+healMod35 end
        if healneed > (1656*gnMod+healMod35)*K and ManaLeft >= 600*tsMod*mgMod and maxRankHT >=  9 and downRankNH >= 9 and SpellIDsHT[9] then SpellID =  SpellIDsHT[9]; HealSize = 1656*gnMod+healMod35 end
        if healneed > (2060*gnMod+healMod35)*K and ManaLeft >= 720*tsMod*mgMod and maxRankHT >= 10 and downRankNH >= 10 and SpellIDsHT[10] then SpellID = SpellIDsHT[10]; HealSize = 2060*gnMod+healMod35 end
        if healneed > (2472*gnMod+healMod35)*K and ManaLeft >= 800*tsMod*mgMod and maxRankHT >= 11 and downRankNH >= 11 and SpellIDsHT[11] then SpellID = SpellIDsHT[11]; HealSize = 2472*gnMod+healMod35 end
    else
        SpellID = SpellIDsRG[1]; HealSize = (91*gnMod+healModRG*PFRG1)*iregMod; -- Default to rank 1
        if healneed > ( 176*gnMod+healModRG*PFRG2)*iregMod*k and ManaLeft >= 164*tsMod*mgMod and maxRankRG >= 2 and downRankFH >= 2 then SpellID = SpellIDsRG[2]; HealSize =  (176*gnMod+healModRG*PFRG2)*iregMod end
        if healneed > ( 257*gnMod+healModRG)*iregMod*k and ManaLeft >= 224*tsMod*mgMod and maxRankRG >= 3 and downRankFH >= 3 and SpellIDsRG[3] then SpellID = SpellIDsRG[3]; HealSize =  (257*gnMod+healModRG)*iregMod end
        if healneed > ( 339*gnMod+healModRG)*iregMod*k and ManaLeft >= 280*tsMod*mgMod and maxRankRG >= 4 and downRankFH >= 4 and SpellIDsRG[4] then SpellID = SpellIDsRG[4]; HealSize =  (339*gnMod+healModRG)*iregMod end
        if healneed > ( 431*gnMod+healModRG)*iregMod*k and ManaLeft >= 336*tsMod*mgMod and maxRankRG >= 5 and downRankFH >= 5 and SpellIDsRG[5] then SpellID = SpellIDsRG[5]; HealSize =  (431*gnMod+healModRG)*iregMod end
        if healneed > ( 543*gnMod+healModRG)*iregMod*k and ManaLeft >= 408*tsMod*mgMod and maxRankRG >= 6 and downRankFH >= 6 and SpellIDsRG[6] then SpellID = SpellIDsRG[6]; HealSize =  (543*gnMod+healModRG)*iregMod end
        if healneed > ( 686*gnMod+healModRG)*iregMod*k and ManaLeft >= 492*tsMod*mgMod and maxRankRG >= 7 and downRankFH >= 7 and SpellIDsRG[7] then SpellID = SpellIDsRG[7]; HealSize =  (686*gnMod+healModRG)*iregMod end
        if healneed > ( 857*gnMod+healModRG)*iregMod*k and ManaLeft >= 592*tsMod*mgMod and maxRankRG >= 8 and downRankFH >= 8 and SpellIDsRG[8] then SpellID = SpellIDsRG[8]; HealSize =  (857*gnMod+healModRG)*iregMod end
        if healneed > (1061*gnMod+healModRG)*iregMod*k and ManaLeft >= 704*tsMod*mgMod and maxRankRG >= 9 and downRankFH >= 9 and SpellIDsRG[9] then SpellID = SpellIDsRG[9]; HealSize = (1061*gnMod+healModRG)*iregMod end
    end

    return SpellID,HealSize*hdb;
end

function QuickHeal_Druid_FindHoTSpellToUse(Target, healType, forceMaxRank)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediately if no player needs healing
    if not Target then
        return SpellID,HealSize;
    end

    -- Determine health and heal need of target
    local healneed;
    local Health;
    if UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target) - HealComm:getHeal(UnitName(Target)); -- Implementatio for HealComm
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = EstimateUnitHealNeed(Target,true);
        Health = UnitHealth(Target)/100;
    end

--by Crazydru 增加BCS进行统计，kook区更新的BCS统计更准确

	BCStime=BCStime or GetTime()-20
	if GetTime()-BCStime>10 then
   	 -- if BonusScanner is running, get +Healing bonus
    		if (BonusScanner) then
        		Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        		debug(string.format("Equipment Healing Bonus: %d", Bonus));
    		end
		if BCS then
			local power,_,_,dmg = BCS:GetSpellPower()
			local heal = BCS:GetHealingPower()
			if dmg == nil then
				power,_,_,dmg = BCS:GetLiveSpellPower()
				heal = BCS:GetLiveHealingPower()
			end				
            heal = heal or 0
            power = power or 0
            dmg = dmg or 0
        	Bonus = tonumber(heal)+tonumber(power)-tonumber(dmg);
       		debug(string.format("装备治疗效果: %d", Bonus));
    		end
		BCStime=GetTime()
	end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,8);
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT and RG
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10);
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local irMod = 5*talentRank/100 + 1;
    debug(string.format("Improved Rejuvenation modifier: %f", irMod));

--by Crazydru 迅捷治愈天赋
    --local _,_,_,_,talentRank,_ = GetTalentInfo(3,7);
    --local smMod = talentRank;
    --debug(string.format("Can use Swiftmend", smMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

--by Crazydru 修改节能施法逻辑
    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        InCombat = false;
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d, RJ up to rank %d", maxRankHT, maxRankRG, maxRankRJ));

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end

    QuickHeal_debug(string.format("healneed: %f  target: %s  healType: %s  forceMaxRank: %s", healneed, Target, healType, tostring(forceMaxRank)));

    --return SpellIDsRJ[1], 32*irMod+gnMod+healMod15;

    --if UnitLevel('player') < 60 then
    --    print('f:QuickHeal_Druid_FindHoTSpellToUse --you are not 60');
    --else
    --    print('f:QuickHeal_Druid_FindHoTSpellToUse --you are 60');
    --end

    if healType == "hot" then
        --QuickHeal_debug(string.format("Spiritual Healing modifier: %f", shMod));
        --SpellID = SpellIDsR[1]; HealSize = 215*shMod+healMod15; -- Default to Renew

        --if Health < QuickHealVariables.RatioFull then
        --if Health > QuickHealVariables.RatioHealthyPriest then
        if not forceMaxRank then
            SpellID = SpellIDsRJ[1]; HealSize = 32*irMod+gnMod+healMod15; -- Default to Renew(Rank 1)
            if healneed > (56*irMod+gnMod+healMod15)*k and ManaLeft >= 155 and maxRankRJ >=2 and SpellIDsRJ[2] then SpellID = SpellIDsRJ[2]; HealSize = 56*irMod+gnMod+healMod15 end
            if healneed > (116*irMod+gnMod+healMod15)*k and ManaLeft >= 185 and maxRankRJ >=3 and SpellIDsRJ[3] then SpellID = SpellIDsRJ[3]; HealSize = 116*irMod+gnMod+healMod15 end
            if healneed > (180*irMod+gnMod+healMod15)*k and ManaLeft >= 215 and maxRankRJ >=4 and SpellIDsRJ[4] then SpellID = SpellIDsRJ[4]; HealSize = 180*irMod+gnMod+healMod15 end
            if healneed > (244*irMod+gnMod+healMod15)*k and ManaLeft >= 265 and maxRankRJ >=5 and SpellIDsRJ[5] then SpellID = SpellIDsRJ[5]; HealSize = 244*irMod+gnMod+healMod15 end
            if healneed > (304*irMod+gnMod+healMod15)*k and ManaLeft >= 315 and maxRankRJ >=6 and SpellIDsRJ[6] then SpellID = SpellIDsRJ[6]; HealSize = 304*irMod+gnMod+healMod15 end
            if healneed > (388*irMod+gnMod+healMod15)*k and ManaLeft >= 380 and maxRankRJ >=7 and SpellIDsRJ[7] then SpellID = SpellIDsRJ[7]; HealSize = 388*irMod+gnMod+healMod15 end
            if healneed > (488*irMod+gnMod+healMod15)*k and ManaLeft >= 455 and maxRankRJ >=8 and SpellIDsRJ[8] then SpellID = SpellIDsRJ[8]; HealSize = 488*irMod+gnMod+healMod15 end
            if healneed > (688*irMod+gnMod+healMod15)*k and ManaLeft >= 545 and maxRankRJ >=9 and SpellIDsRJ[9] then SpellID = SpellIDsRJ[9]; HealSize = 608*irMod+gnMod+healMod15 end
            if healneed > (756*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = 756*irMod+gnMod+healMod15 end
            if healneed > (888*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+gnMod+healMod15 end
--by Crazydru
            --if healneed > (888+Bonus*0.8)*irMod*gnMod and ManaLeft >= 199 and SMUsable and SpellIDsSM then SpellID = SpellIDsSM; HealSize = (888+Bonus*0.8)*irMod*gnMod end
        else
            SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+gnMod+healMod15
            if maxRankRJ >=2 and SpellIDsRJ[2] then SpellID = SpellIDsRJ[2]; HealSize = 56*irMod+healMod15 end
            if maxRankRJ >=3 and SpellIDsRJ[3] then SpellID = SpellIDsRJ[3]; HealSize = 116*irMod+healMod15 end
            if maxRankRJ >=4 and SpellIDsRJ[4] then SpellID = SpellIDsRJ[4]; HealSize = 180*irMod+healMod15 end
            if maxRankRJ >=5 and SpellIDsRJ[5] then SpellID = SpellIDsRJ[5]; HealSize = 244*irMod+healMod15 end
            if maxRankRJ >=6 and SpellIDsRJ[6] then SpellID = SpellIDsRJ[6]; HealSize = 304*irMod+healMod15 end
            if maxRankRJ >=7 and SpellIDsRJ[7] then SpellID = SpellIDsRJ[7]; HealSize = 388*irMod+healMod15 end
            if maxRankRJ >=8 and SpellIDsRJ[8] then SpellID = SpellIDsRJ[8]; HealSize = 488*irMod+healMod15 end
            if maxRankRJ >=9 and SpellIDsRJ[9] then SpellID = SpellIDsRJ[9]; HealSize = 688*irMod+healMod15 end
            if maxRankRJ >=10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = 756*irMod+healMod15 end
            if maxRankRJ >=11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+healMod15 end
--by Crazydru
            --if healneed > (888+Bonus*0.8)*irMod*gnMod and ManaLeft >= 199 and SMUsable and SpellIDsSM then SpellID = SpellIDsSM; HealSize = (888+Bonus*0.8)*irMod*gnMod end
        end
        --end
    end

    return SpellID,HealSize*HDB;
end

function QuickHeal_Druid_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF8 = 0.55;
    local PFRG1 = 0.7 * 1.042; -- Rank 1 of RG (1.041 compensates for the 0.50 factor that should be 0.48 for RG1)
    local PF14 = 0.775;
    local PFRG2 = 0.925;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    if multiplier == nil then
        jgpprint(">>> multiplier is NIL <<<")
        --if multiplier > 1.0 then
        --    Overheal = true;
        --end
    elseif multiplier == 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
    elseif multiplier > 1.0 then
        jgpprint(">>> multiplier is " .. multiplier .. " <<<")
        Overheal = true;
    end

    -- Determine health and heal need of target
    local healneed = healDeficit * multiplier;
    local Health = healDeficit / maxhealth;

--by Crazydru 增加BCS进行统计，kook区更新的BCS统计更准确

	BCStime=BCStime or GetTime()-20
	if GetTime()-BCStime>10 then
   	 -- if BonusScanner is running, get +Healing bonus
    		if (BonusScanner) then
        		Bonus = tonumber(BonusScanner:GetBonus("HEAL"));
        		debug(string.format("Equipment Healing Bonus: %d", Bonus));
    		end
		if BCS then
			local power,_,_,dmg = BCS:GetSpellPower()
			local heal = BCS:GetHealingPower()
			if dmg == nil then
				power,_,_,dmg = BCS:GetLiveSpellPower()
				heal = BCS:GetLiveHealingPower()
			end				
            heal = heal or 0
            power = power or 0
            dmg = dmg or 0
        	Bonus = tonumber(heal)+tonumber(power)-tonumber(dmg);
       		debug(string.format("装备治疗效果: %d", Bonus));
    		end
		BCStime=GetTime()
	end

    -- Calculate healing bonus
    local healMod15 = (1.5/3.5) * Bonus;
    local healMod20 = (2.0/3.5) * Bonus;
    local healMod25 = (2.5/3.5) * Bonus;
    local healMod30 = (3.0/3.5) * Bonus;
    local healMod35 = Bonus;
    local healModRG = (2.0/3.5) * Bonus * 0.5; -- The 0.5 factor is calculated as DirectHeal/(DirectHeal+HoT)
    debug("Final Healing Bonus (1.5,2.0,2.5,3.0,3.5,Regrowth)", healMod15,healMod20,healMod25,healMod30,healMod35,healModRG);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Gift of Nature - Increases healing by 2% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,8);
    local gnMod = 2*talentRank/100 + 1;
    debug(string.format("Gift of Nature modifier: %f", gnMod));

    -- Tranquil Spirit - Decreases mana usage by 2% per rank on HT only
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,10);
    local tsMod = 1 - 2*talentRank/100;
    debug(string.format("Tranquil Spirit modifier: %f", tsMod));

    -- Moonglow - Decrease mana usage by 3% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local mgMod = 1 - 3*talentRank/100;
    debug(string.format("Moonglow modifier: %f", mgMod));

    -- Improved Rejuvenation -- Increases Rejuvenation effects by 5% per rank
    local _,_,_,_,talentRank,_ = GetTalentInfo(3,9);
    local irMod = 5*talentRank/100 + 1;
    debug(string.format("Improved Rejuvenation modifier: %f", irMod));

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy ",Health);
    end

--by Crazydru 修改节能施法逻辑
    -- Detect Clearcasting (from Omen of Clarity, talent(1,10))
    if QuickHeal_DetectBuff('player',"Spell_Shadow_ManaBurn",1) then -- Spell_Shadow_ManaBurn (1)
        ManaLeft = UnitManaMax('player');  -- set to max mana so max spell rank will be cast
        --healneed = 10^6; -- deliberate overheal (mana is free)
        debug("BUFF: Clearcasting (Omen of Clarity)");
    end

    -- Detect Nature's Swiftness (next nature spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Nature_RavenForm") then
        debug("BUFF: Nature's Swiftness (out of combat healing forced)");
        InCombat = false;
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        InCombat = false;
    end

    -- Get total healing modifier (factor) caused by healing target debuffs
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;

    -- Get a list of ranks available for all spells
    local SpellIDsHT = GetSpellIDs(QUICKHEAL_SPELL_HEALING_TOUCH);
    local SpellIDsRG = GetSpellIDs(QUICKHEAL_SPELL_REGROWTH);
    local SpellIDsRJ = GetSpellIDs(QUICKHEAL_SPELL_REJUVENATION);

    local maxRankHT = table.getn(SpellIDsHT);
    local maxRankRG = table.getn(SpellIDsRG);
    local maxRankRJ = table.getn(SpellIDsRJ);

    debug(string.format("Found HT up to rank %d, RG up to rank %d, RJ up to rank %d", maxRankHT, maxRankRG, maxRankRJ));

    -- Compensation for health lost during combat
    local k=1.0;
    local K=1.0;
    if InCombat then
        k=0.9;
        K=0.8;
    end

    --QuickHeal_debug(string.format("healneed: %f  target: %s  healType: %s  forceMaxRank: %s", healneed, Target, healType, tostring(forceMaxRank)));

    --return SpellIDsRJ[1], 32*irMod+gnMod+healMod15;

    --if UnitLevel('player') < 60 then
    --    print('f:QuickHeal_Druid_FindHoTSpellToUseNoTarget --you are not 60');
    --else
    --    print('f:QuickHeal_Druid_FindHoTSpellToUseNoTarget --you are 60');
    --end

    SpellID = SpellIDsRJ[1]; HealSize = 32*irMod+gnMod+healMod15; -- Default to Renew(Rank 1)
    if healneed > (56*irMod+gnMod+healMod15)*k and ManaLeft >= 155 and maxRankRJ >=2 and SpellIDsRJ[2] then SpellID = SpellIDsRJ[2]; HealSize = 56*irMod+gnMod+healMod15 end
    if healneed > (116*irMod+gnMod+healMod15)*k and ManaLeft >= 185 and maxRankRJ >=3 and SpellIDsRJ[3] then SpellID = SpellIDsRJ[3]; HealSize = 116*irMod+gnMod+healMod15 end
    if healneed > (180*irMod+gnMod+healMod15)*k and ManaLeft >= 215 and maxRankRJ >=4 and SpellIDsRJ[4] then SpellID = SpellIDsRJ[4]; HealSize = 180*irMod+gnMod+healMod15 end
    if healneed > (244*irMod+gnMod+healMod15)*k and ManaLeft >= 265 and maxRankRJ >=5 and SpellIDsRJ[5] then SpellID = SpellIDsRJ[5]; HealSize = 244*irMod+gnMod+healMod15 end
    if healneed > (304*irMod+gnMod+healMod15)*k and ManaLeft >= 315 and maxRankRJ >=6 and SpellIDsRJ[6] then SpellID = SpellIDsRJ[6]; HealSize = 304*irMod+gnMod+healMod15 end
    if healneed > (388*irMod+gnMod+healMod15)*k and ManaLeft >= 380 and maxRankRJ >=7 and SpellIDsRJ[7] then SpellID = SpellIDsRJ[7]; HealSize = 388*irMod+gnMod+healMod15 end
    if healneed > (488*irMod+gnMod+healMod15)*k and ManaLeft >= 455 and maxRankRJ >=8 and SpellIDsRJ[8] then SpellID = SpellIDsRJ[8]; HealSize = 488*irMod+gnMod+healMod15 end
    if healneed > (688*irMod+gnMod+healMod15)*k and ManaLeft >= 545 and maxRankRJ >=9 and SpellIDsRJ[9] then SpellID = SpellIDsRJ[9]; HealSize = 608*irMod+gnMod+healMod15 end
    if healneed > (756*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=10 and SpellIDsRJ[10] then SpellID = SpellIDsRJ[10]; HealSize = 756*irMod+gnMod+healMod15 end
    if healneed > (888*irMod+gnMod+healMod15)*k and ManaLeft >= 655 and maxRankRJ >=11 and SpellIDsRJ[11] then SpellID = SpellIDsRJ[11]; HealSize = 888*irMod+gnMod+healMod15 end


    return SpellID,HealSize*hdb;
end

function QuickHeal_Command_Druid(msg)

    --if PlayerClass == "priest" then
    --  writeLine("DRUID", 0, 1, 0);
    --end

    local _, _, arg1, arg2, arg3 = string.find(msg, "%s?(%w+)%s?(%w+)%s?(%w+)")

    -- match 3 arguments
    if arg1 ~= nil and arg2 ~= nil and arg3 ~= nil then
        if arg1 == "player" or arg1 == "target" or arg1 == "targettarget" or arg1 == "party" or arg1 == "subgroup" or arg1 == "mt" or arg1 == "nonmt" then
            if arg2 == "heal" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL(maxHPS)", 0, 1, 0);
                QuickHeal(arg1, nil, nil, true);
                return;
            end
            if arg2 == "hot" and arg3 == "fh" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT(max rank & no hp check)", 0, 1, 0);
                QuickHOT(arg1, nil, nil, true, true);
                return;
            end
            if arg2 == "hot" and arg3 == "max" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT(max rank)", 0, 1, 0);
                QuickHOT(arg1, nil, nil, true, false);
                return;
            end
        end
    end

    -- match 2 arguments
    local _, _, arg4, arg5= string.find(msg, "%s?(%w+)%s?(%w+)")

    if arg4 ~= nil and arg5 ~= nil then
        if arg4 == "debug" then
            if arg5 == "on" then
                QHV.DebugMode = true;
                --writeLine(QuickHealData.name .. " debug mode enabled", 0, 0, 1);
                return;
            elseif arg5 == "off" then
                QHV.DebugMode = false;
                --writeLine(QuickHealData.name .. " debug mode disabled", 0, 0, 1);
                return;
            end
        end
        if arg4 == "heal" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HEAL (max)", 0, 1, 0);
            QuickHeal(nil, nil, nil, true);
            return;
        end
        if arg4 == "hot" and arg5 == "max" then
            --writeLine(QuickHealData.name .. " HOT (max)", 0, 1, 0);
            QuickHOT(nil, nil, nil, true, false);
            return;
        end
        if arg4 == "hot" and arg5 == "fh" then
            --writeLine(QuickHealData.name .. " FH (max rank & no hp check)", 0, 1, 0);
            QuickHOT(nil, nil, nil, true, true);
            return;
        end
        if arg4 == "player" or arg4 == "target" or arg4 == "targettarget" or arg4 == "party" or arg4 == "subgroup" or arg4 == "mt" or arg4 == "nonmt" then
            if arg5 == "hot" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HOT", 0, 1, 0);
                QuickHOT(arg1, nil, nil, false, false);
                return;
            end
            if arg5 == "heal" then
                --writeLine(QuickHealData.name .. " qh " .. arg1 .. " HEAL", 0, 1, 0);
                QuickHeal(arg1, nil, nil, false);
                return;
            end
        end
    end

    -- match 1 argument
    local cmd = string.lower(msg)

    if cmd == "cfg" then
        QuickHeal_ToggleConfigurationPanel();
        return;
    end

    if cmd == "toggle" then
        QuickHeal_Toggle_Healthy_Threshold();
        return;
    end

    if cmd == "downrank" or cmd == "dr" then
        ToggleDownrankWindow()
        return;
    end

    if cmd == "tanklist" or cmd == "tl" then
        QH_ShowHideMTListUI();
        return;
    end

    if cmd == "reset" then
        QuickHeal_SetDefaultParameters();
        writeLine(QuickHealData.name .. " reset to default configuration", 0, 0, 1);
        QuickHeal_ToggleConfigurationPanel();
        QuickHeal_ToggleConfigurationPanel();
        return;
    end

    if cmd == "heal" then
        --writeLine(QuickHealData.name .. " HEAL", 0, 1, 0);
        QuickHeal();
        return;
    end

    if cmd == "hot" then
        --writeLine(QuickHealData.name .. " HOT", 0, 1, 0);
        QuickHOT();
        return;
    end

    if cmd == "" then
        --writeLine(QuickHealData.name .. " qh", 0, 1, 0);
        QuickHeal(nil);
        return;
    elseif cmd == "player" or cmd == "target" or cmd == "targettarget" or cmd == "party" or cmd == "subgroup" or cmd == "mt" or cmd == "nonmt" then
        --writeLine(QuickHealData.name .. " qh " .. cmd, 0, 1, 0);
        QuickHeal(cmd);
        return;
    end

    -- Print usage information if arguments do not match
    --writeLine(QuickHealData.name .. " Usage:");
    writeLine("== QUICKHEAL USAGE : DRUID ==");
    writeLine("/qh cfg - 打开配置面板.");
    writeLine("/qh toggle - 在迅捷治疗和一般治疗中开关切换 (健康阈值 0% 或 100%).");
    writeLine("/qh downrank | dr - 打开 QuickHeal 的低级法术治疗等级滑块.");
    writeLine("/qh tanklist | tl - 显示坦克列表");
    writeLine("/qh [mask] [type] [mod] - 用最适合的治疗法术来治疗最需要的小队/团队队员.");
    writeLine(" [mask] 限制治疗目标:");
    writeLine("  [player] 只治疗玩家");
    writeLine("  [target] 只治疗目标");
    writeLine("  [targettarget] 只治疗目标的目标");
    writeLine("  [party] 只治疗队伍");
    writeLine("  [mt] 只治疗MT");
    writeLine("  [nonmt] 只治疗非MT");
    writeLine("  [subgroup] 只治疗配置面板中选定的小组");

    writeLine(" [type] 治疗技能类型（[heal] or [hot]）");
    writeLine(" [mod] (可选) [heal] or [hot]模式下额外选项:");
    writeLine("  [heal] 可增加选项:");
    writeLine("   [max] 用最高级直接治疗技能治疗不满血目标");
    writeLine("  [hot] 可增加选项:");
    writeLine("   [max] 用最高级HOT治疗不满血团员");
    writeLine("   [fh] 用最高级HOT治疗目标，无视是否掉血");

    writeLine("/qh reset 重置.");
end
