--by Crazydru 
local BCStime
local Bonus=0

local function writeLine(s,r,g,b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(s, r or 1, g or 1, b or 0.5)
    end
end

function QuickHeal_Paladin_GetRatioHealthyExplanation()
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local RatioFull = QuickHealVariables["RatioFull"];
--by Crazydru 修改健康阈值文本
    if RatioHealthy >= RatioFull then
        return "战斗中只会使用"..QUICKHEAL_SPELL_HOLY_LIGHT .. " ，脱战后会使用 ".. QUICKHEAL_SPELL_FLASH_OF_LIGHT;
    else
        if RatioHealthy > 0 then
            return QUICKHEAL_SPELL_HOLY_LIGHT .. " 只在战斗中且如果目标低于 " .. RatioHealthy*100 .. "% 血量使用，其余时候使用" .. QUICKHEAL_SPELL_FLASH_OF_LIGHT          
        else
            return " 只使用 " .. QUICKHEAL_SPELL_FLASH_OF_LIGHT ;           
        end
    end
end

function QuickHeal_Paladin_FindSpellToUse(Target, healType, multiplier, forceMaxHPS)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

    -- Return immediatly if no player needs healing
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

    -- Determine health and healneed of target
    local healneed;
    local Health;

    if QuickHeal_UnitHasHealthInfo(Target) then
        -- Full info available
        healneed = UnitHealthMax(Target) - UnitHealth(Target) - HealComm:getHeal(UnitName(Target)); -- Implementatin for HealComm
        if Overheal then
            healneed = healneed * multiplier;
        else
            --
        end
        Health = UnitHealth(Target) / UnitHealthMax(Target);
    else
        -- Estimate target health
        healneed = QuickHeal_EstimateUnitHealNeed(Target,true); -- needs HealComm implementation maybe
        if Overheal then
            healneed = healneed * multiplier;
        else
            --
        end
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
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

 -- Divine Favor Talent (increases Holy shock effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local dfMod = 5*talentRank/100 + 1;
    debug(string.format("Divine Favor talentmodification: %f", dfMod))

    -- 神圣震击天赋
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14);
    local hsMod = talentRank;
    debug(string.format("神圣震击: %f", hlMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    --if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        --debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        --InCombat = false;
    --end

    -- Detect proc of 'Holy Judgement" (next Holy Light is fast cast)
    --if QuickHeal_DetectBuff('player',"ability_paladin_judgementblue") then
        --debug("BUFF: Holy Judgement (out of combat healing forced)");
        --InCombat = false;
    --end

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Detect Daybreak on target
    local dbMod = QuickHeal_DetectBuff(Target,"Spell_Holy_AuraMastery");
    if dbMod then dbMod = 1.2 else dbMod = 1 end;
    debug("Daybreak healing modifier",dbMod);

    -- Get a list of ranks available of 'Flash of Light' and 'Holy Light'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("发现圣光术等级提升 %d, 发现圣光闪等级提升 %d", maxRankHL, maxRankFL))

--by Crazydru 加载神圣震击
	--local SpellIDsHS = nil
	--local maxRankHS = nil
	--local HSUsable=false
	--if hsMod ==1 then
		--SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
		--maxRankHS = table.getn(SpellIDsHS);
		--HSUsable= GetSpellCooldown(SpellIDsHS[1], "spell")==0 and QuickHealVariables.HolyShock and InCombat
	--end
    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)            3 = 4 | 3 < 4 | 3 > 4
    end
--by Crazydru 重构加血逻辑
    if not forceMaxHPS and InCombat and not TargetIsHealthy then
        if Health < RatioFull then
	        SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
            if healneed > ( 83+healMod25*PF6 )*hlMod*dbMod*K and ManaLeft >= 60  and maxRankHL >=2 and downRankNH >= 2 and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
            if healneed > (173+healMod25*PF14)*hlMod*dbMod*K and ManaLeft >= 110 and maxRankHL >=3 and downRankNH >= 3 and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
            if healneed > (333+healMod25)*hlMod*dbMod*K and ManaLeft >= 190 and maxRankHL >=4 and downRankNH >= 4 and SpellIDsHL[4] then SpellID = SpellIDsHL[4]; HealSize = (333+healMod25)*hlMod*dbMod end
            if healneed > (522+healMod25)*hlMod*dbMod*K and ManaLeft >= 275 and maxRankHL >=5 and downRankNH >= 5 and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522+healMod25)*hlMod*dbMod end
            if healneed > (739+healMod25)*hlMod*dbMod*K and ManaLeft >= 365 and maxRankHL >=6 and downRankNH >= 6 and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739+healMod25)*hlMod*dbMod end
            if healneed > (999+healMod25)*hlMod*dbMod*K and ManaLeft >= 465 and maxRankHL >=7 and downRankNH >= 7 and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999+healMod25)*hlMod*dbMod end
            if healneed > (1317+healMod25)*hlMod*dbMod*K and ManaLeft >= 580 and maxRankHL >=8 and downRankNH >= 8 and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317+healMod25)*hlMod*dbMod end
            if healneed > (1680+healMod25)*hlMod*dbMod*K and ManaLeft >= 660 and maxRankHL >=9 and downRankNH >= 9 and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680+healMod25)*hlMod*dbMod end
            --if healneed >(315+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end -- Default to Holy Shock(Rank 1)
            --if healneed >(360+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
            --if healneed >(500+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	        --if healneed >(655+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
        end
    elseif forceMaxHPS then
	    SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
	    if ManaLeft >= 60  and maxRankHL >=2 and downRankNH >= 2 and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
	    if ManaLeft >= 110 and maxRankHL >=3 and downRankNH >= 3 and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
        if ManaLeft >= 35  and maxRankFL >=1 and downRankFH >= 1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod*dbMod end
        if ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod*dbMod end
        if ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod*dbMod end
        if ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod*dbMod end
        if ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod*dbMod end
        if ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod*dbMod end
	    if ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod*dbMod end
        --if ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end 
        --if ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
        --if ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	    --if ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
    else
        if Health < RatioFull then
	        SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
            if healneed > (83+healMod25*PF6)*hlMod*dbMod*K and ManaLeft >= 60  and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
            if healneed > (173+healMod25*PF14)*hlMod*dbMod*K and ManaLeft >= 110 and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
            if maxRankFL >=1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod*dbMod end -- Default to rank 1 of FL
            if healneed > (102+healMod15)*hlMod*dbMod*k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod*dbMod end
            if healneed > (153+healMod15)*hlMod*dbMod*k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod*dbMod end
            if healneed > (206+healMod15)*hlMod*dbMod*k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod*dbMod end
            if healneed > (278+healMod15)*hlMod*dbMod*k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod*dbMod end
            if healneed > (348+healMod15)*hlMod*dbMod*k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod*dbMod end
	        if healneed > (428+healMod15)*hlMod*dbMod*k and ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod*dbMod end
            --if healneed >(315+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end -- Default to Holy Shock(Rank 1)
            --if healneed >(360+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
            --if healneed >(500+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	        --if healneed >(655+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
        end
    end
    return SpellID,HealSize*HDB;
end

function QuickHeal_Paladin_FindHealSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;
    local Overheal = false;

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

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

    -- Local aliases to access main module functionality and settings
    local RatioFull = QuickHealVariables["RatioFull"];
    local RatioHealthy = QuickHeal_GetRatioHealthy();
    local UnitHasHealthInfo = QuickHeal_UnitHasHealthInfo;
    local EstimateUnitHealNeed = QuickHeal_EstimateUnitHealNeed;
    local GetSpellIDs = QuickHeal_GetSpellIDs;
    local debug = QuickHeal_debug;

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
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or incombat;

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

 -- Divine Favor Talent (increases Holy shock effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local dfMod = 5*talentRank/100 + 1;
    debug(string.format("Divine Favor talentmodification: %f", dfMod))

    -- by Crazydru 神圣震击天赋
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14);
    local hsMod = talentRank;
    debug(string.format("神圣震击: %f", hlMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect proc of 'Hand of Edward the Odd' mace (next spell is instant cast)
    --if QuickHeal_DetectBuff('player',"Spell_Holy_SearingLight") then
        --debug("BUFF: Hand of Edward the Odd (out of combat healing forced)");
        --InCombat = false;
    --end

    -- Detect proc of 'Holy Judgement" (next Holy Light is fast cast)
    --if QuickHeal_DetectBuff('player',"ability_paladin_judgementblue") then
        --debug("BUFF: Holy Judgement (out of combat healing forced)");
        --InCombat = false;
    --end

    -- Get total healing modifier (factor) caused by healing target debuffs
    --local HDB = QuickHeal_GetHealModifier(Target);
    --debug("Target debuff healing modifier",HDB);
    healneed = healneed/hdb;


    -- Detect Daybreak on target
    local dbMod = QuickHeal_DetectBuff(Target,"Spell_Holy_AuraMastery");
    if dbMod then dbMod = 1.2 else dbMod = 1 end;
    debug("Daybreak healing modifier",dbMod);

    -- Get a list of ranks available of 'Flash of Light' and 'Holy Light'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    local NoFL = maxRankFL < 1;
    debug(string.format("发现圣光术等级提升 %d, 发现圣光闪等级提升 %d", maxRankHL, maxRankFL))

--by Crazydru
	--local SpellIDsHS = nil
	--local maxRankHS = nil
	--local HSUsable=false
	--if hsMod ==1 then
		--SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
		--maxRankHS = table.getn(SpellIDsHS);
		--HSUsable= GetSpellCooldown(SpellIDsHS[1], "spell")==0 and QuickHealVariables.HolyShock and InCombat
	--end


    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals


    -- below changed to not differentiate between in or out if combat. Original code down below
    -- Find suitable SpellID based on the defined criteria
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)            3 = 4 | 3 < 4 | 3 > 4
    end

--by Crazydru 重构加血逻辑
    if not forceMaxHPS and InCombat and not TargetIsHealthy then
        if Health < RatioFull then
	        SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
            if healneed > ( 83+healMod25*PF6 )*hlMod*dbMod*K and ManaLeft >= 60  and maxRankHL >=2 and downRankNH >= 2 and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
            if healneed > (173+healMod25*PF14)*hlMod*dbMod*K and ManaLeft >= 110 and maxRankHL >=3 and downRankNH >= 3 and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
            if healneed > (333+healMod25)*hlMod*dbMod*K and ManaLeft >= 190 and maxRankHL >=4 and downRankNH >= 4 and SpellIDsHL[4] then SpellID = SpellIDsHL[4]; HealSize = (333+healMod25)*hlMod*dbMod end
            if healneed > (522+healMod25)*hlMod*dbMod*K and ManaLeft >= 275 and maxRankHL >=5 and downRankNH >= 5 and SpellIDsHL[5] then SpellID = SpellIDsHL[5]; HealSize = (522+healMod25)*hlMod*dbMod end
            if healneed > (739+healMod25)*hlMod*dbMod*K and ManaLeft >= 365 and maxRankHL >=6 and downRankNH >= 6 and SpellIDsHL[6] then SpellID = SpellIDsHL[6]; HealSize = (739+healMod25)*hlMod*dbMod end
            if healneed > (999+healMod25)*hlMod*dbMod*K and ManaLeft >= 465 and maxRankHL >=7 and downRankNH >= 7 and SpellIDsHL[7] then SpellID = SpellIDsHL[7]; HealSize = (999+healMod25)*hlMod*dbMod end
            if healneed > (1317+healMod25)*hlMod*dbMod*K and ManaLeft >= 580 and maxRankHL >=8 and downRankNH >= 8 and SpellIDsHL[8] then SpellID = SpellIDsHL[8]; HealSize = (1317+healMod25)*hlMod*dbMod end
            if healneed > (1680+healMod25)*hlMod*dbMod*K and ManaLeft >= 660 and maxRankHL >=9 and downRankNH >= 9 and SpellIDsHL[9] then SpellID = SpellIDsHL[9]; HealSize = (1680+healMod25)*hlMod*dbMod end
            --if healneed >(315+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end -- Default to Holy Shock(Rank 1)
            --if healneed >(360+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
            --if healneed >(500+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	        --if healneed >(655+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
        end
    elseif forceMaxHPS then
	    SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
	    if ManaLeft >= 60  and maxRankHL >=2 and downRankNH >= 2 and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
	    if ManaLeft >= 110 and maxRankHL >=3 and downRankNH >= 3 and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
        if ManaLeft >= 35  and maxRankFL >=1 and downRankFH >= 1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod*dbMod end
        if ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod*dbMod end
        if ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod*dbMod end
        if ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod*dbMod end
        if ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod*dbMod end
        if ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod*dbMod end
	    if ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod*dbMod end
        --if ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end 
        --if ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
        --if ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	    --if ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
    else
        if Health < RatioFull then
	        SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
            if healneed > ( 83+healMod25*PF6 )*hlMod*dbMod*K and ManaLeft >= 60  and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
            if healneed > (173+healMod25*PF14)*hlMod*dbMod*K and ManaLeft >= 110 and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
            if maxRankFL >=1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod*dbMod end -- Default to rank 1 of FL
            if healneed > (102+healMod15)*hlMod*dbMod*k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod*dbMod end
            if healneed > (153+healMod15)*hlMod*dbMod*k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod*dbMod end
            if healneed > (206+healMod15)*hlMod*dbMod*k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod*dbMod end
            if healneed > (278+healMod15)*hlMod*dbMod*k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod*dbMod end
            if healneed > (348+healMod15)*hlMod*dbMod*k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod*dbMod end
	        if healneed > (428+healMod15)*hlMod*dbMod*k and ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod*dbMod end
            --if healneed >(315+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end -- Default to Holy Shock(Rank 1)
            --if healneed >(360+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
            --if healneed >(500+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	        --if healneed >(655+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
        end
    end
    return SpellID,HealSize*HDB;
end


function QuickHeal_Paladin_FindHoTSpellToUse(Target, healType, forceMaxRank)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

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
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    -- Divine Favor Talent (increases Holy shock effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local dfMod = 5*talentRank/100 + 1;
    debug(string.format("Divine Favor talentmodification: %f", dfMod))

    -- 神圣震击天赋
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14);
    local hsMod = talentRank;
    debug(string.format("神圣震击: %f", hlMod))


    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect Daybreak on target
    local dbMod = QuickHeal_DetectBuff(Target,"Spell_Holy_AuraMastery");
    if dbMod then dbMod = 1.2 else dbMod = 1 end;
    debug("Daybreak healing modifier",dbMod);

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available of 'Flash of Light' and 'Holy Light' and 'Holy Shock'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    --local SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    --local maxRankHS = table.getn(SpellIDsHS);
    local NoFL = maxRankFL < 1;
    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))
	local SpellIDsHS = nil
	local maxRankHS = nil
	local HSUsable=false
	if hsMod ==1 then
		SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
		maxRankHS = table.getn(SpellIDsHS);
		debug(string.format("Found HS up to rank %d", maxRankHS))
--by Crazydru
		HSUsable= GetSpellCooldown(SpellIDsHS[1], "spell")==0
	end

    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals


    QuickHeal_debug(string.format("healneed: %f  target: %s  healType: %s  forceMaxRank: %s", healneed, Target, healType, tostring(forceMaxRank)));

--by Crazydru 重构加血逻辑
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)            3 = 4 | 3 < 4 | 3 > 4
    end
    if healType == "hot" then
        if not forceMaxHPS then
	        --SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
            --if healneed > ( 83+healMod25*PF6 )*hlMod*dbMod*K and ManaLeft >= 60  and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
            --if healneed > (173+healMod25*PF14)*hlMod*dbMod*K and ManaLeft >= 110 and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
            --if maxRankFL >=1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod*dbMod end
            --if healneed > (102+healMod15)*hlMod*dbMod*k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod*dbMod end
            --if healneed > (153+healMod15)*hlMod*dbMod*k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod*dbMod end
            --if healneed > (206+healMod15)*hlMod*dbMod*k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod*dbMod end
            --if healneed > (278+healMod15)*hlMod*dbMod*k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod*dbMod end
            --if healneed > (348+healMod15)*hlMod*dbMod*k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod*dbMod end
	        --if healneed > (428+healMod15)*hlMod*dbMod*k and ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod*dbMod end
            if healneed >(315+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end
            if healneed >(360+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
            if healneed >(500+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	        if healneed >(655+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
        else
	        --SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
	        --if ManaLeft >= 60  and maxRankHL >=2 and downRankNH >= 2 and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
	        --if ManaLeft >= 110 and maxRankHL >=3 and downRankNH >= 3 and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
            --if ManaLeft >= 35  and maxRankFL >=1 and downRankFH >= 1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod*dbMod end
            --if ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod*dbMod end
            --if ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod*dbMod end
            --if ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod*dbMod end
            --if ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod*dbMod end
            --if ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod*dbMod end
	        --if ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod*dbMod end
            if ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end 
            if ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
            if ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	        if ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
        end
    end
    return SpellID,HealSize*HDB;
end

function QuickHeal_Paladin_FindHoTSpellToUseNoTarget(maxhealth, healDeficit, healType, multiplier, forceMaxHPS, forceMaxRank, hdb, incombat)
    local SpellID = nil;
    local HealSize = 0;

    -- +Healing-PenaltyFactor = (1-((20-LevelLearnt)*0.0375)) for all spells learnt before level 20
    local PF1 = 0.2875;
    local PF6 = 0.475;
    local PF14 = 0.775;

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
    local healMod25 = (2.5/3.5) * Bonus;
    debug("Final Healing Bonus (1.5,2.5)", healMod15,healMod25);

    local InCombat = UnitAffectingCombat('player') or UnitAffectingCombat(Target);

    -- Healing Light Talent (increases healing by 4% per rank)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,6);
    local hlMod = 4*talentRank/100 + 1;
    debug(string.format("Healing Light talentmodification: %f", hlMod))

    -- Divine Favor Talent (increases Holy shock effect by 5% per rank, as crit is 50% bonus only)
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,13);
    local dfMod = 5*talentRank/100 + 1;
    debug(string.format("Divine Favor talentmodification: %f", dfMod))

    -- 神圣震击天赋
    local _,_,_,_,talentRank,_ = GetTalentInfo(1,14);
    local hsMod = talentRank;
    debug(string.format("神圣震击: %f", hsMod))

    local TargetIsHealthy = Health >= RatioHealthy;
    local ManaLeft = UnitMana('player');

    if TargetIsHealthy then
        debug("Target is healthy",Health);
    end

    -- Detect Daybreak on target
    local dbMod = QuickHeal_DetectBuff(Target,"Spell_Holy_AuraMastery");
    if dbMod then dbMod = 1.2 else dbMod = 1 end;
    debug("Daybreak healing modifier",dbMod);

    -- Get total healing modifier (factor) caused by healing target debuffs
    local HDB = QuickHeal_GetHealModifier(Target);
    debug("Target debuff healing modifier",HDB);
    healneed = healneed/HDB;

    -- Get a list of ranks available of 'Flash of Light' and 'Holy Light' and 'Holy Shock'
    local SpellIDsHL = GetSpellIDs(QUICKHEAL_SPELL_HOLY_LIGHT);
    local SpellIDsFL = GetSpellIDs(QUICKHEAL_SPELL_FLASH_OF_LIGHT);
    --local SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
    local maxRankHL = table.getn(SpellIDsHL);
    local maxRankFL = table.getn(SpellIDsFL);
    --local maxRankHS = table.getn(SpellIDsHS);
    local NoFL = maxRankFL < 1;

    debug(string.format("Found HL up to rank %d, and found FL up to rank %d", maxRankHL, maxRankFL))
	local SpellIDsHS = nil
	local maxRankHS = nil
	local HSUsable=false
	if hsMod ==1 then
		SpellIDsHS = GetSpellIDs(QUICKHEAL_SPELL_HOLY_SHOCK);
		maxRankHS = table.getn(SpellIDsHS);
		debug(string.format("Found HS up to rank %d", maxRankHS))

		HSUsable= GetSpellCooldown(SpellIDsHS[1], "spell")==0
	end



    --Get max HealRanks that are allowed to be used
    local downRankFH = QuickHealVariables.DownrankValueFH  -- rank for 1.5 sec heals
    local downRankNH = QuickHealVariables.DownrankValueNH -- rank for < 1.5 sec heals

--by Crazydru 重构加血逻辑
    local k = 1;
    local K = 1;
    if InCombat then
        local k = 0.9; -- In combat means that target is loosing life while casting, so compensate
        local K = 0.8; -- k for fast spells (FL) and K for slow spells (HL)            3 = 4 | 3 < 4 | 3 > 4
    end
    --SpellID = SpellIDsHL[1]; HealSize = (43+healMod25*PF1)*hlMod*dbMod; -- Default to rank 1 of HL
    --if healneed > ( 83+healMod25*PF6 )*hlMod*dbMod*K and ManaLeft >= 60  and maxRankHL >=2 and (TargetIsHealthy and maxRankFL <= 1 or NoFL) and SpellIDsHL[2] then SpellID = SpellIDsHL[2]; HealSize =  (83+healMod25*PF6)*hlMod*dbMod end
    --if healneed > (173+healMod25*PF14)*hlMod*dbMod*K and ManaLeft >= 110 and maxRankHL >=3 and (TargetIsHealthy and maxRankFL <= 3 or NoFL) and SpellIDsHL[3] then SpellID = SpellIDsHL[3]; HealSize = (173+healMod25*PF14)*hlMod*dbMod end
    --if maxRankFL >=1 and SpellIDsFL[1] then SpellID = SpellIDsFL[1]; HealSize = (67+healMod15)*hlMod*dbMod end -- Default to rank 1 of FL
    --if healneed > (102+healMod15)*hlMod*dbMod*k and ManaLeft >= 50  and maxRankFL >=2 and downRankFH >= 2 and SpellIDsFL[2] then SpellID = SpellIDsFL[2]; HealSize = (102+healMod15)*hlMod*dbMod end
    --if healneed > (153+healMod15)*hlMod*dbMod*k and ManaLeft >= 70  and maxRankFL >=3 and downRankFH >= 3 and SpellIDsFL[3] then SpellID = SpellIDsFL[3]; HealSize = (153+healMod15)*hlMod*dbMod end
    --if healneed > (206+healMod15)*hlMod*dbMod*k and ManaLeft >= 90  and maxRankFL >=4 and downRankFH >= 4 and SpellIDsFL[4] then SpellID = SpellIDsFL[4]; HealSize = (206+healMod15)*hlMod*dbMod end
    --if healneed > (278+healMod15)*hlMod*dbMod*k and ManaLeft >= 115 and maxRankFL >=5 and downRankFH >= 5 and SpellIDsFL[5] then SpellID = SpellIDsFL[5]; HealSize = (278+healMod15)*hlMod*dbMod end
    --if healneed > (348+healMod15)*hlMod*dbMod*k and ManaLeft >= 140 and maxRankFL >=6 and downRankFH >= 6 and SpellIDsFL[6] then SpellID = SpellIDsFL[6]; HealSize = (348+healMod15)*hlMod*dbMod end
    --if healneed > (428+healMod15)*hlMod*dbMod*k and ManaLeft >= 180 and maxRankFL >=7 and downRankFH >= 7 and SpellIDsFL[7] then SpellID = SpellIDsFL[7]; HealSize = (428+healMod15)*hlMod*dbMod end
    if healneed*100/(100-math.min(QuickHealVariables.Waste,50)) >(315+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 280 and maxRankHS ==1 and SpellIDsHS[1] and HSUsable then SpellID = SpellIDsHS[1]; HealSize = (315+healMod15)*dfMod*hlMod*dbMod end -- Default to Holy Shock(Rank 1)
    if healneed*100/(100-math.min(QuickHealVariables.Waste,50)) >(360+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 335 and maxRankHS ==2 and SpellIDsHS[2] and HSUsable then SpellID = SpellIDsHS[2]; HealSize = (360+healMod15)*dfMod*hlMod*dbMod end
    if healneed*100/(100-math.min(QuickHealVariables.Waste,50)) >(500+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 410 and maxRankHS ==3 and SpellIDsHS[3] and HSUsable then SpellID = SpellIDsHS[3]; HealSize = (500+healMod15)*dfMod*hlMod*dbMod end
	if healneed*100/(100-math.min(QuickHealVariables.Waste,50)) >(655+healMod15)*dfMod*hlMod*dbMod and ManaLeft >= 485 and maxRankHS ==4 and SpellIDsHS[4] and HSUsable then SpellID = SpellIDsHS[4]; HealSize = (655+healMod15)*dfMod*hlMod*dbMod end
    return SpellID,HealSize*hdb;
end



function QuickHeal_Command_Paladin(msg)

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
    writeLine("== QUICKHEAL USAGE : PALADIN ==");
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
    writeLine("   [heal] 对40码内目标使用神圣震击/圣光术/圣光闪现");
    writeLine("   [type] 对20码内目标优先使用震击，其次使用圣光闪现");
    writeLine(" [mod] (可选) [heal]模式下额外选项:");
    writeLine("   [max] 用最高级神圣震击/圣光闪现治疗技能治疗不满血目标");
    writeLine("  [hot] 模式下额外选项:");
    writeLine("   [max] 用最高级神圣震击/圣光闪现治疗不满血团员");
    writeLine("   [fh] 用最高级神圣震击/圣光闪现治疗目标，无视是否掉血");

    writeLine("/qh reset 重置");
end

