// To add a rev to the list of revolutionaries, make sure it's rev (with if(SSticker.mode.name == "revolution)),
// then call SSticker.mode:add_revolutionary(_THE_PLAYERS_MIND_)
// nothing else needs to be done, as that proc will check if they are a valid target.
// Just make sure the converter is a head before you call it!
// To remove a rev (from brainwashing or w/e), call SSticker.mode:remove_revolutionary(_THE_PLAYERS_MIND_),
// this will also check they're not a head, so it can just be called freely
// If the game somtimes isn't registering a win properly, then SSticker.mode.check_win() isn't being called somewhere.


/datum/game_mode/revolution
	name = "revolution"
	config_tag = "revolution"
	antag_flag = ROLE_REV
	false_report_weight = 10
	restricted_jobs = list("Security Officer", "Warden", "Detective", "AI", "Cyborg","Captain", "Head of Personnel", "Head of Security", "Chief Engineer", "Research Director", "Chief Medical Officer")
	required_players = 20 //formerly 30
	required_enemies = 1
	recommended_enemies = 3
	enemy_minimum_age = 14

	announce_span = "danger"
	announce_text = "Some crewmembers are attempting a coup!\n\
	<span class='danger'>Revolutionaries</span>: Expand your cause and overthrow the heads of staff by execution or otherwise.\n\
	<span class='notice'>Crew</span>: Prevent the revolutionaries from taking over the station."

	divider_for_antagonists = 10
	minimum_enemies = 1

	var/finished = 0
	var/check_counter = 0
	var/max_headrevs = 3
	var/datum/team/revolution/revolution
	var/list/datum/mind/headrev_candidates = list()
	var/end_when_heads_dead = TRUE

	var/list/defeated_head_players = list()

	var/target_is_security = 0

///////////////////////////
//Announces the game type//
///////////////////////////
/datum/game_mode/revolution/announce()
	to_chat(world, "<B>The current game mode is - Revolution!</B>")
	to_chat(world, "<B>Some crewmembers are attempting to start a revolution!<BR>\nRevolutionaries - Kill the Captain, HoP, HoS, CE, RD and CMO. Convert other crewmembers (excluding the heads of staff, and security officers) to your cause by flashing them. Protect your leaders.<BR>\nPersonnel - Protect the heads of staff. Kill the leaders of the revolution, and brainwash the other revolutionaries (by beating them in the head).</B>")


///////////////////////////////////////////////////////////////////////////////
//Gets the round setup, cancelling if there's not enough players at the start//
///////////////////////////////////////////////////////////////////////////////

/datum/game_mode/revolution/can_start()
	. = ..()
	if(!.)
		return .
	var/list/heads = list()
	for(var/command_position in GLOB.command_positions)
		var/datum/job/job = SSjob.GetJob(command_position)
		for(var/level = 1 to 3)
			for(var/mob/dead/new_player/player in GLOB.player_list)
				if(jobban_isbanned(player, job.title))
					continue
				if(!job.player_old_enough(player.client))
					continue
				if(player.mind && job.title in player.mind.restricted_roles)
					continue
				if(CONFIG_GET(flag/enforce_human_authority) && !player.client.prefs.pref_species.qualifies_for_rank(job.title, player.client.prefs.features))
					continue
				if(player.client.prefs.GetJobDepartment(job, level) & job.flag)
					heads += player.mind
	if(!heads.len)
		return 0

/datum/game_mode/revolution/pre_setup()
	if(CONFIG_GET(flag/protect_roles_from_antagonist))
		restricted_jobs += protected_jobs

	if(CONFIG_GET(flag/protect_assistant_from_antagonist))
		restricted_jobs += "Assistant"

	max_headrevs = recommended_enemies

	for (var/i=1 to max_headrevs)
		if (antag_candidates.len==0)
			break
		var/datum/mind/lenin = antag_pick(antag_candidates)
		antag_candidates -= lenin
		headrev_candidates += lenin
		lenin.restricted_roles = restricted_jobs

	if(headrev_candidates.len < required_enemies)
		return FALSE

	return TRUE

/datum/game_mode/revolution/post_setup()

	var/list/heads = SSjob.get_living_heads()
	var/list/sec = SSjob.get_living_sec()
	var/weighted_score = min(max(round(heads.len - ((8 - sec.len) / 3)),1),max_headrevs)

	for(var/datum/mind/rev_mind in headrev_candidates)	//People with return to lobby may still be in the lobby. Let's pick someone else in that case.
		if(isnewplayer(rev_mind.current))
			headrev_candidates -= rev_mind
			var/list/newcandidates = shuffle(antag_candidates)
			if(newcandidates.len == 0)
				continue
			for(var/M in newcandidates)
				var/datum/mind/lenin = M
				antag_candidates -= lenin
				newcandidates -= lenin
				if(isnewplayer(lenin.current)) //We don't want to make the same mistake again
					continue
				else
					var/mob/Nm = lenin.current
					if(Nm.job in restricted_jobs)	//Don't make the HOS a replacement revhead
						antag_candidates += lenin	//Let's let them keep antag chance for other antags
						continue

					headrev_candidates += lenin
					break

	while(weighted_score < headrev_candidates.len) //das vi danya
		var/datum/mind/trotsky = pick(headrev_candidates)
		antag_candidates += trotsky
		headrev_candidates -= trotsky

	revolution = new()

	for(var/datum/mind/rev_mind in headrev_candidates)
		log_game("[rev_mind.key] (ckey) has been selected as a head rev")
		var/datum/antagonist/rev/head/new_head = new()
		new_head.give_flash = TRUE
		new_head.give_hud = TRUE
		new_head.remove_clumsy = TRUE
		rev_mind.add_antag_datum(new_head,revolution)

	revolution.update_objectives()
	revolution.update_heads()

	SSshuttle.registerHostileEnvironment(src)
	..()

/datum/game_mode/revolution/Post_DivideOccupations()
	var/list/targets = list()
	if(SSjob)
		targets += SSjob.get_all_heads()
		if(!targets.len)
			targets += SSjob.get_all_sec()
			target_is_security = 1
	if(!targets.len)
		message_admins("Failed to start revs due to no heads of staff. Skipping.")
		return FALSE
	return TRUE

/datum/game_mode/revolution/process()
	check_counter++
	if(check_counter >= 5)
		if(!finished)
			SSticker.mode.check_win()
		check_counter = 0
	return FALSE

//////////////////////////////////////
//Checks if the revs have won or not//
//////////////////////////////////////
/datum/game_mode/revolution/check_win()
	if(check_rev_victory())
		finished = 1
	else if(check_heads_victory())
		finished = 2
	return

///////////////////////////////
//Checks if the round is over//
///////////////////////////////
/datum/game_mode/revolution/check_finished()
	if(CONFIG_GET(keyed_flag_list/continuous)["revolution"])
		if(finished)
			SSshuttle.clearHostileEnvironment(src)
		return ..()
	if(finished != 0 && end_when_heads_dead)
		return TRUE
	else
		return ..()

///////////////////////////////////////////////////
//Deals with converting players to the revolution//
///////////////////////////////////////////////////
/proc/is_revolutionary(mob/M)
	return M && istype(M) && M.mind && M.mind.has_antag_datum(/datum/antagonist/rev)

/proc/is_head_revolutionary(mob/M)
	return M && istype(M) && M.mind && M.mind.has_antag_datum(/datum/antagonist/rev/head)

//////////////////////////
//Checks for rev victory//
//////////////////////////
/*/datum/game_mode/revolution/proc/check_rev_victory()
	for(var/datum/objective/mutiny/objective in revolution.objectives)
		if(!(objective.check_completion()))
			return FALSE
	return TRUE*/
/datum/game_mode/revolution/proc/check_rev_victory()
	for(var/datum/objective/mutiny/objective in revolution.objectives)
		if(!objective.target)
			continue
		if(is_player_alive_and_well(objective.target))
			return FALSE
	return TRUE

/////////////////////////////
//Checks for a head victory//
/////////////////////////////
/datum/game_mode/revolution/proc/check_heads_victory()
	for(var/datum/mind/rev_mind in revolution.head_revolutionaries())
		if(is_player_alive_and_well(rev_mind))
			return FALSE
	return TRUE

/datum/game_mode/revolution/proc/is_player_alive_and_well(datum/mind/M)
	if(istype(M,/mob))
		var/mob/mob = M
		if(mob.mind)
			M = mob.mind
	if(istype(M) && M.current)
		var/turf/T = get_turf(M.current)
		var/away = 0
		if(istype(M.current,/mob/living))
			var/client/C
			if(M.current && M.current.client)
				C = M.current.client
			if(!C)
				for(var/mob/dead/observer/O in GLOB.player_list)
					if(O.can_reenter_corpse && O.mind == M && O.client)
						C = O.client
						break
			if(C && C.is_afk())
				away = 1
			else if(!C)
				away = 1
		var/inactivetoolong = 0
		if(away)
			if(!(M in defeated_head_players))
				defeated_head_players[M] = world.time
			if(M in defeated_head_players && defeated_head_players[M]+600 <= world.time)
				inactivetoolong = 1
		else
			if(M in defeated_head_players)
				defeated_head_players.Remove(M)
		if(!inactivetoolong && considered_alive(M) && is_station_level(T.z))
			if(istype(M.current,/mob/living/carbon))
				return TRUE
	return FALSE

/datum/game_mode/revolution/set_round_result()
	..()
	if(finished == 1)
		SSticker.mode_result = "win - heads killed"
		SSticker.news_report = REVS_WIN
	else if(finished == 2)
		SSticker.mode_result = "loss - rev heads killed"
		SSticker.news_report = REVS_LOSE

//TODO What should be displayed for revs in non-rev rounds
/datum/game_mode/revolution/special_report()
	if(finished == 1)
		return "<span class='redtext big'>The heads of staff were killed or exiled! The revolutionaries win!</span>"
	else if(finished == 2)
		return "<span class='redtext big'>The heads of staff managed to stop the revolution!</span>"

/datum/game_mode/revolution/generate_report()
	return "Employee unrest has spiked in recent weeks, with several attempted mutinies on heads of staff. Some crew have been observed using flashbulb devices to blind their colleagues, \
		who then follow their orders without question and work towards dethroning departmental leaders. Watch for behavior such as this with caution. If the crew attempts a mutiny, you and \
		your heads of staff are fully authorized to execute them using lethal weaponry - they will be later cloned and interrogated at Central Command."

/datum/game_mode/revolution/extended
	name = "extended_revolution"
	config_tag = "extended_revolution"
	end_when_heads_dead = FALSE

/datum/game_mode/revolution/speedy
	name = "speedy_revolution"
	config_tag = "speedy_revolution"
	end_when_heads_dead = FALSE
	var/endtime = null
	var/fuckingdone = FALSE

/datum/game_mode/revolution/speedy/pre_setup()
	endtime = world.time + 20 MINUTES
	return ..()

/datum/game_mode/revolution/speedy/process()
	. = ..()
	if(check_counter == 0)
		if (world.time > endtime && !fuckingdone)
			fuckingdone = TRUE
			for (var/obj/machinery/nuclearbomb/N in GLOB.nuke_list)
				if (!N.timing)
					N.timer_set = 200
					N.set_safety()
					N.set_active()
