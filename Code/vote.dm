/datum/vote/New()

	nextvotetime = world.timeofday // + 10*config.votedelay


/datum/vote/proc/canvote()

	var/excess = world.timeofday - vote.nextvotetime

	if(excess < -10000)		// handle clock-wrapping problems - very long delay (>20 hrs) if wrapped
		vote.nextvotetime = world.timeofday
		return 1
	return (excess >= 0)



/datum/vote/proc/nextwait()
	return timetext( round( (nextvotetime - world.timeofday)/10) )

/datum/vote/proc/endwait()
	return timetext( round( (votetime - world.timeofday)/10) )

/datum/vote/proc/timetext(var/interval)
	var/minutes = round(interval / 60)
	var/seconds = round(interval % 60)

	var/tmin = "[minutes>0?num2text(minutes)+"min":null]"
	var/tsec = "[seconds>0?num2text(seconds)+"sec":null]"

	if(tmin && tsec)				// hack to skip inter-space if either field is blank
		return "[tmin] [tsec]"
	else
		if(!tmin && !tsec)		// return '0sec' if 0 time left
			return "0sec"
		return "[tmin][tsec]"

/datum/vote/proc/getvotes()

	var/list/L = list()


	for(var/mob/M in world)
		if(M.client && M.client.inactivity < 1200)		// clients inactive for 2 minutes don't count
			if (M.client.vote != "none")
				L[M.client.vote] += 1


	return L


/datum/vote/proc/endvote()

	if(!voting)		// means that voting was aborted by an admin
		return

	world << "\red <B>***Voting has closed.</B>"

	if(config.logvote)	world.log << "VOTE: Voting closed, result was [winner]"

	voting = 0
	nextvotetime = world.timeofday + 10*config.votedelay

	for(var/mob/M in world)		// clear vote window from all clients
		if(M.client)
			M << browse(null, "window=vote")
			M.client.showvote = 0

	calcwin()

	if(mode)
		var/wintext = upperfirst(winner)
		if(winner=="default")
			world << "Result is \red No change."
			return

		// otherwise change mode


		world << "Result is change to \red [wintext]"


		// write resulting mode to savefile

		var/F = file(persistent_file)
		fdel(F)
		F << winner

		if(ticker)
			world <<"\red <B>World will reboot in 10 seconds</B>"

			sleep(100)
			if(config.loggame) world.log << "GAME: Rebooting due to mode vote "
			world.Reboot()
		else
			master_mode = winner

	else

		if(winner=="default")
			world << "Result is \red No restart."
			return

		world << "Result is \red Restart round."

		world <<"\red <B>World will reboot in 5 seconds</B>"

		sleep(50)
		if(config.loggame) world.log << "GAME: Rebooting due to restart vote"
		world.Reboot()
	return


/datum/vote/proc/calcwin()

	var/list/votes = getvotes()

	if(vote.mode)
		var/best = -1

		for(var/v in votes)
			if(v=="none")
				continue
			if(best < votes[v])
				best = votes[v]


		var/list/winners = list()

		for(var/v in votes)
			if(votes[v] == best)
				winners += v

		var/ret = ""


		for(var/w in winners)
			if(length(ret) > 0)
				ret += "/"
			if(w=="default")
				winners = list("default")
				ret = "No change"
				break
			else
				ret += upperfirst(w)



		if(winners.len != 1)
			ret = "Tie: " + ret


		if(winners.len == 0)
			vote.winner = "default"
			ret = "No change"
		else
			vote.winner = pick(winners)

		return ret
	else

		if(votes["default"] < votes["restart"])

			vote.winner = "restart"
			return "Restart"
		else
			vote.winner = "default"
			return "No restart"


/mob/verb/vote()


	usr.client.showvote = 1


	var/text = "<HTML><HEAD><TITLE>Voting</TITLE></HEAD><BODY scroll=no>"

	var/footer = "<HR><A href='?src=\ref[vote];voter=\ref[src];vclose=1'>Close</A></BODY></HTML>"


	if(config.votenodead && usr.stat == 2)
		text += "Voting while dead has been disallowed."
		text += footer
		usr << browse(text, "window=vote")
		usr.client.showvote = 0
		usr.client.vote = "none"
		return

	if(vote.voting)
		// vote in progress, do the current

		text += "Vote to [vote.mode?"change mode":"restart round"] in progress.<BR>"
		text += "[vote.endwait()] until voting is closed.<BR>"

		var/list/votes = vote.getvotes()

		if(vote.mode)		// true if changing mode

			text += "Current game mode is: <B>[master_mode]</B>.<BR>Select the mode to change to:<UL>"

			for(var/md in vote.vmodes)
				var/disp = upperfirst(md)
				if(md=="default")
					disp = "No change"

				//world << "[md]|[disp]|[src.client.vote]|[votes[md]]"

				if(src.client.vote == md)
					text += "<LI><B>[disp]</B>"
				else
					text += "<LI><A href='?src=\ref[vote];voter=\ref[src];vote=[md]'>[disp]</A>"

				text += "[votes[md]>0?" - [votes[md]] vote\s":null]<BR>"

			text += "</UL>"

			text +="<p>Current winner: <B>[vote.calcwin()]</B><BR>"

			text += footer

			usr << browse(text, "window=vote")

		else	// voting to restart

			text += "Restart the world?<BR><UL>"

			var/list/VL = list("default","restart")

			for(var/md in VL)
				var/disp = (md=="default"? "No":"Yes")

				if(src.client.vote == md)
					text += "<LI><B>[disp]</B>"
				else
					text += "<LI><A href='?src=\ref[vote];voter=\ref[src];vote=[md]'>[disp]</A>"

				text += "[votes[md]>0?" - [votes[md]] vote\s":null]<BR>"

			text += "</UL>"

			text +="<p>Current winner: <B>[vote.calcwin()]</B><BR>"

			text += footer

			usr << browse(text, "window=vote")


	else		//no vote in progress


		if(!config.allowvoterestart && !config.allowvotemode)
			text += "<P>Player voting is disabled.</BODY></HTML>"

			usr << browse(text, "window=vote")
			usr.client.showvote = 0
			return

		if(!vote.canvote())		// not time to vote yet
			if(config.allowvoterestart) text+="Voting to restart is enabled.<BR>"
			if(config.allowvotemode) text+="Voting to change mode is enabled.<BR>"

			text+="<BR><P>Next vote can begin in [vote.nextwait()]."
			text+=footer

			usr << browse(text, "window=vote")

		else			// voting can begin
			if(config.allowvoterestart)
				text += "<A href='?src=\ref[vote];voter=\ref[src];vmode=1'>Begin restart vote.</A><BR>"
			if(config.allowvotemode)
				text += "<A href='?src=\ref[vote];voter=\ref[src];vmode=2'>Begin change mode vote.</A><BR>"

			text += footer
			usr << browse(text, "window=vote")

	spawn(20)
		if(usr.client && usr.client.showvote)
			usr.vote()
		else
			usr << browse(null, "window=vote")

		return


/datum/vote/Topic(href, href_list)
	..()

	var/mob/M = locate(href_list["voter"])			// mob of player that clicked link

	if(href_list["vclose"])

		if(M)
			M << browse(null, "window=vote")
			M.client.showvote = 0
		return

	if(href_list["vmode"])
		if(vote.voting)
			return

		if(!vote.canvote() )	// double check even though this shouldn't happen
			return

		vote.mode = text2num(href_list["vmode"])-1 	// hack to yield 0=restart, 1=changemode
		vote.voting = 1						// now voting
		vote.votetime = world.timeofday + config.voteperiod*10	// when the vote will end

		spawn(config.voteperiod*10)
			vote.endvote()

		world << "\red<B>*** A vote to [vote.mode?"change game mode":"restart"] has been initiated by [M.key].</B>"
		world << "\red     You have [vote.timetext(config.voteperiod)] to vote."

		if(config.logvote)	world.log << "VOTE: Voting to [vote.mode?"change mode":"restart round"] started by [M.name]/[M.key]"

		for(var/mob/CM in world)
			if(CM.client)
				if(config.votenodefault || (config.votenodead && CM.stat == 2))
					CM.client.vote = "none"
				else
					CM.client.vote = "default"

		if(M) M.vote()
		return


		return

	if(href_list["vote"] && vote.voting)
		if(M)
			M.client.vote = href_list["vote"]

			//world << "Setting client [M.key]'s vote to: [href_list["vote"]]."

			M.vote()
		return
