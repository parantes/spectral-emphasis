# +-------------------------+
# | spectral_emphasis.praat |
# +-------------------------+
#
# Author: Pablo Arantes <pabloarantes@protonmail.com>
# Created: 2010-06-20
# Modified: 2013-01-19
# Version: 0.2 (beta)
#
# TODO:
# * Issue error message or deal with the situation where there
#   is no interval in a TextGrid matching a label in the
#   user-provided label list.
# * Study the idea of removing the option to extract Pitch
#   automatically. It does not work well when there is a lot
#   pitch range variation
# * Remove 'start' and 'end' columns in report table
#
# Purpose:
# Measures spectral emphasis in selected intervals. Emphasis is defined
# as the difference (in dB) between the overall intensity and the
# intensity in a signal that is low-pass filtered at 1.5 times the
# F0 mean in a window with default width of 25 ms. Within each analysis 
# interval the window advances with a default step of half window width
# to follow the F0 contour. It is thought to reflect the relative
# contribution of the high-frequency band to the overall intensity.
# See Traunmüller and Eriksson 2000 (JASA v. 107(6), 3438-3451) and 
# Heldner 2003 (Journal of Phonetics, v. 31, 39-62) for more details
#
#
# Copyright (C) 2010-2021 Pablo Arantes
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

form Spectral emphasis
	comment Folder where the sound files are:
	sentence Audio 
	comment Folder where the TextGrid files are:
	sentence Grids 
	comment Tier where the intervals to be analyzed are:
	positive Tier 1
	comment Extract Pitch or provide files?
	boolean Extract no
	comment If 'Extract' is marked, should Pitch be purged?
	boolean Purge no
	comment Pitch files folder if files are provided:
	sentence Pitch 
	comment Name of the report file (include folder path)
	sentence Report report.txt
	comment List of labels (one per line, include folder path)
	sentence Labels lab.txt
	positive Window_width_(in_s) 0.025
	optionmenu Average: 1
		option Mean
		option Median
endform

call stringsToTable 'labels$' labels labels
labels = stringsToTable.table

# Shortening GUI variable name
width = window_width

# Window advance step is half the window duration
step = width/2

gridFiles = Create Strings as file list... gridFiles 'grids$'*.TextGrid
nFiles = Get number of strings

for i to nFiles
	select gridFiles
	grid$ = Get string... i
	grid = Read from file... 'grids$''grid$'

	# Finds intervals to be analysed
	call findIntervals grid tier labels
	intervals = findIntervals.table
	select grid
	Remove

	# Defines windows within each interval
	call windows intervals width step
	windows = windows.table
	audioFile$ = grid$ - ".TextGrid" + ".wav"
	audio = Read from file... 'audio$''audioFile$'

	# Pitch handling
	if extract = 1
		pitch = To Pitch... 0 75 600
		call purge_f0 pitch audio purge
		pitch = purge_f0.f0_id
	else
		pitchFile$ = grid$ - ".TextGrid" + ".Pitch"
		pitch = Read from file... 'pitch$''pitchFile$'
	endif
	smoothed = Smooth... 10
	minF0 = Get minimum... 0 0 Hertz Parabolic
	maxF0 = Get maximum... 0 0 Hertz Parabolic
	minF0 = floor(minF0 /10 ) * 10
	maxF0 = ceiling(maxF0 / 10) * 10
	# Interpolation ensures that it will always be possible to
	# determine the low-pass filter upper band
	# It provides also constant extrapolation on the F0 contour edges 
	tempPT = Down to PitchTier
	Interpolate quadratically... 4 Semitones
	interpol = To Pitch... 0.01 minF0 maxF0
	select pitch
	plus tempPT
	Remove
	# 'pitch' refers now to smoothed, interpolated Pitch object
	pitch = interpol

	call emphasis audio pitch intervals windows

	intervals'i' = intervals
endfor

# Joining the individual intervals Tables
if nFiles > 1
	select intervals1
	for i from 2 to nFiles
		plus intervals'i'
	endfor
	joined = Append
	select intervals1
	for i from 2 to nFiles
		plus intervals'i'
	endfor
	Remove
else
	joined = intervals1
	select intervals1
endif
select joined
#Remove column... start
#Remove column... end
Rename... spectral_emphasis

# Cleaning up
select labels
plus gridFiles
Remove

# Writing report file to disk
select joined
Write to table file... 'report$'

###########################################################################
# PROCEDURES
###########################################################################

procedure stringsToTable .path$ .tableName$ .colName$
# =Description=
# Loads a text file as a Strings object and converts it into a Table.
#
# =Variables=
# .path$: text file folder location
# .tableName$: Table name
# .colName$: column name 

	.strings = Read Strings from raw text file... '.path$'
	.lines = Get number of strings
	.table = Create Table with column names... '.tableName$' .lines '.colName$'
	for .line to .lines
		select .strings
		.str$ = Get string... .line
		select .table
		Set string value... .line '.colName$' '.str$'
	endfor
	select .strings
	Remove
endproc

procedure findIntervals .grid .tier .labels
# =Description=
# Creates a Table with information about intervals in a TextGrid
# matching one of the labels in the user-provided label list.
#
# =Variables=
# .grid: TextGrid object numerical ID
# .tier: number of TextGrid tier to be analysed
# .labels: numerical ID of Table containing labels list 

	select .grid
	.grid$ = selected$("TextGrid")
	.table = Create Table with column names... '.grid$'_intervals 0 file label position start end
	select .grid
	.intervals = Get number of intervals... '.tier'
	.matches = 0 ; number of intervals matching a label in the list
	for .i to .intervals
		select .grid
		.label$ = Get label of interval... '.tier' '.i'
		select .labels
		.control = Search column... labels '.label$'
		if .control > 0
			.matches += 1
			select .grid
			.start = Get starting point... '.tier' '.i'
			.end = Get end point... '.tier' '.i'
			select .table
			Append row
			Set string value... .matches file '.grid$'
			Set string value... .matches label '.label$'
			Set string value... .matches position '.matches'
			Set numeric value... .matches start '.start'
			Set numeric value... .matches end '.end'
		endif
	endfor
	# Prompts an error message if there are no intervals
	# in the user-defined tier that matching the labels
	# in the lables list
	select .table
	.control = Get number of rows
	if .control < 1
		exit Error.'newline$'There are no intervals in tier '.tier' that match one of the labels in the provided list.'newline$'
	endif
endproc

procedure windows .intervalsTable .width .step
# =Description=
# Defines windows to be analysed based on width and advance step 
# parameters, both given in ms.
#
# =Variables=
# .intervalsTable: Table object numerical ID
# .width: analysis window width (in ms)
# .step: window advance step (in ms)

	select .intervalsTable
	.file$ = Get value... 1 file
	.nIntervals = Get number of rows
	.table = Create Table with column names... '.file$'_windows 0 file label position window start end
	.nWin = 0
	for .i to .nIntervals
		select .intervalsTable
		.label$ = Get value... .i label
		.pos$ = Get value... .i position
		.intStart = Get value... .i start
		.intEnd = Get value... .i end
		.intDur = .intEnd - .intStart
		.winStart = .intStart
		.winEnd = .intStart
		while .winEnd < .intEnd
			if .width > .intDur
				.winEnd = .intEnd
			else
				.rem = .intStart + (.intDur - (.winStart + .width))
				if .rem  < .step
					.winEnd = .intEnd
				else
					.winEnd = .winStart + .width
				endif
			endif
			.nWin += 1
			select .table
			Append row
			Set string value... .nWin file '.file$'
			Set string value... .nWin label '.label$'
			Set string value... .nWin position '.pos$'
			Set numeric value... .nWin window '.nWin'
			Set numeric value... .nWin start '.winStart'
			Set numeric value... .nWin end '.winEnd'
			.winStart += .step
		endwhile
	endfor
endproc

procedure purge_f0 .f0_id .audio .purge
# == Arguments ==
# .f0_id :: integer
#  Numerical ID of the Pitch object being purged
#
# .audio :: integer
#  numerical ID of the Sound object being analysed
#
# == Purpose ==
# The purpose of the procedure is to remove outlying pitch points in the
# F0 contour the script will work on. First it will extract the F0
# contour in a two-pass operation and then prompt the user to inspect
# the Pitch object and remove or add pitch points as s/he sees fit. When
# the user is done the script's execution will continue.
# 
# The F0 extraction is a two-pass operation. The relevant parameters
# the procedure will manipulate are floor and ceiling F0 values. In the
# first pass the Pitch object is extracted using the default values (75
# and 600 Hz). In the second pass another Pitch object is extracted using
# optimal values for floor and ceiling estimated from the first Pitch
# object. The values are obtained using the following forlumae:
# 
# - F0 ceiling = 1.5*q3
# - F0 floor = 0.65*q1
# 
# where q1 and q3 are respectively the first and third quartiles of the
# first Pitch object F0 values. This heuristic is suggested by Hirst
# [cf. D. Hirst, Proc. XVIth ICPhS, Saarbrucken, 1233 (2007)]. Actually,
# Hirst suggests 0.75 as a coefficient for q1, but in my empirical
# experience 0.75 led to values slightly higher than the first-pass
# minumum value in situations where it was bona fide.

	select .f0_id
	.pitch_name$ = selected$("Pitch")
	.min = Get minimum... 0 0 Hertz None
	.min = round(.min)
	.max = Get maximum... 0 0 Hertz None
	.max = round(.max)
	.q1 = Get quantile... 0 0 0.25 Hertz
	.q1 = floor(.q1)
	.q3 = Get quantile... 0 0 0.75 Hertz
	.q3 = ceiling(.q3)
	.floor = floor(0.65*.q1)
	.ceiling = ceiling(1.5*.q3)
	select .f0_id
	Remove
	select .audio
	! Second pass F0 extraction
	.second_pass = To Pitch (ac)...  0 .floor 15 yes  0.03 0.45 0.01 0.35 0.14 .ceiling
	if .purge = 1
		select .audio
		Edit
		editor Sound '.pitch_name$'
		Pitch settings... .floor .ceiling Hertz   autocorrelation speckles
		endeditor
		.voiced_before = Count voiced frames
		! Prompt user to remove or add points in the 2nd pass Picth object
		Edit
		editor Pitch '.pitch_name$'
			beginPause ("Unvoice spurious pitch points. (Selection > Unvoice)")
			.action = endPause ("Done", 1)
			if .action = 1
				Close
			endif
		endeditor
		.new_min = Get minimum... 0 0 Hertz None
		.new_min = round(.new_min)
		.new_max = Get maximum... 0 0 Hertz None
		.new_max = round(.new_max)
		.voiced_after = Count voiced frames
		.balance = .voiced_after - .voiced_before
		editor Sound '.pitch_name$'
		Close
		endeditor
		! Writing information to the the info window
		clearinfo
		printline F0 extraction report'newline$'--------------------
		printline 1st pass > minimum: '.min' Hz - maximum: '.max' Hz
		printline estimated parameters: floor: '.floor' Hz - ceiling: '.ceiling' Hz
		printline 2nd pass > minimum: '.new_min' Hz - maximum: '.new_max' Hz
		printline net change: '.balance' points'newline$'
	endif
	! Restoring object ID reference
	.f0_id = .second_pass

endproc

procedure emphasis .audio .pitch .intervals .windows
# =Description=
# Gets spectral emphasis for each analysis window in each interval
# in the intervals Table. Emphasis is defined as the intensity
# difference in the whole audio signal and the intensity in a low-pass
# filtered signal with the cut-off frequency for each analysis window
# fixed as 1.5*F0.
#
# =Variables=
# .audio: Sound object numerical ID
# .pitch: Pitch object numerical ID
# .intervals: intervals Table numerical ID
# .windows: windows Table numerical ID 

	select .pitch
	.minF0 = Get minimum... 0 0 Hertz Parabolic
	select .intervals
	Append column... emphasis
	.nInter = Get number of rows
	for .i to .nInter
		select .intervals
		.intStart = Get value... .i start
		.intEnd = Get value... .i end
		.dur = .intEnd - .intStart
		if .dur <= 0.01
			.relWidth = 20
		elsif .dur <= 0.02
			.relWidth = 8
		elsif .dur <= 0.06
			.relWidth = 5
		else
			.relWidth = 3.5
		endif
		select .windows
		.winTable = Extract rows where column (text)... position "is equal to" '.i'
		.nWin = Get number of rows
		Append column... emphasis
		select .audio
		.intAudio = Extract part... .intStart .intEnd rectangular .relWidth yes
		.wholeIntensity = To Intensity... .minF0 0 yes
		for .j to .nWin
			select .winTable
			.winStart = Get value... .j start
			.winEnd = Get value... .j end
			select .pitch
			if average = 1
				.f0Avg = Get mean... .winStart .winEnd Hertz
			else
				.f0Avg = Get quantile... .winStart .winEnd 0.5 Hertz
			endif
			.cutoff = 1.5*.f0Avg
			select .intAudio
			.filtAudio = Filter (pass Hann band)... 0 .cutoff 15
			.filtIntensity = To Intensity... .minF0 0 yes
			if average = 1
				select .wholeIntensity
				.whole = Get mean... .winStart .winEnd energy
				select .filtIntensity
				.filt = Get mean... .winStart .winEnd energy
			else
				select .wholeIntensity
				.whole = Get quantile... .winStart .winEnd 0.5
				select .filtIntensity
				.filt = Get quantile... .winStart .winEnd 0.5
			endif
			.emph = .whole - .filt
			select .winTable
			Set numeric value... .j emphasis .emph
			select .filtAudio
			plus .filtIntensity
			Remove
		endfor
		select .winTable
		if average = 1
			.avgEmph = Get mean... emphasis
		else
			.avgEmph = Get quantile... emphasis 0.5
		endif
		select .intervals
		Set numeric value... .i emphasis '.avgEmph:2'
		select .intAudio
		# Comment the following line to see corresponding table for each interval
		plus .winTable
		plus .wholeIntensity
		Remove
	endfor
	select .audio
	plus .pitch
	plus .windows
	Remove
endproc
