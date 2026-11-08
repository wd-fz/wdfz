extends "res://tests/support/test_suite.gd"

func original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/bell_tails-reference.json.gz").decompress_dynamic(1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func test_original_bells() -> void:
	var audio := AudioFx.new()
	root.add_child(audio)
	var mood := AtmosModule.new()
	var data := original_data()
	var original_notes: Array = data["samples"][0]["notes"]
	for sample: Dictionary in data["samples"]:
		mood.set_context({"day":sample["day"]})
		var tune := mood.bell_tune(sample["kind"],sample["time"])
		check(same_json(tune,sample["tune"]),"original bell tune day %d at %d: %s" % [sample["day"],sample["time"],sample["kind"]])
		audio.stop_all()
		audio.captions_live = true
		audio.school_bell(sample["kind"],true,tune)
		var voice := audio._pool[posmod(audio._next-1,audio._pool.size())]
		var expected_file := ""
		var take: Dictionary = {}
		for candidate: Dictionary in audio._index["sfx"][sample["played"]["id"]]["files"]:
			if candidate["file"]==voice.stream.resource_path.get_file():
				expected_file = candidate["file"]
				take = candidate
		var duration := float(audio._index["sfx"][sample["played"]["id"]]["len"])
		if not tune.is_empty():
			var found := false
			for variant: Dictionary in audio._index["bell_tails"]:
				if absf(float(variant["tail"])-float(tune["tail"]))<.000001 and float(variant["tailLength"])==float(tune["tailLength"]):
					take = variant["files"][0]
					expected_file = take["file"]
					duration = variant["len"]
					found = true
			check(found,"every original day/night final-note combination has a baked stream")
			var last: Dictionary = sample["notes"][7]
			check(absf(duration-(last["at"]+last["duration"]+.35))<.0001,"baked bell retains original last-note duration and decay padding")
			check(same_json(sample["notes"].slice(0,7),original_notes.slice(0,7)),"original early notes retain their pitch, times and lengths")
		check(audio.played.back()==sample["played"]["id"] and voice.stream.resource_path.get_file()==expected_file,"school bell uses the correct original event and final-note variant")
		check(voice.pitch_scale==1 and voice.bus=="SfxSoft" and absf(voice.volume_db-(float(take["db"])+linear_to_db(.45)))<.001,"outdoor bell retains original gain/filter and full playback speed")
		check(absf(voice.stream.get_length()-duration)<.02,"encoded bell length agrees with its original recipe")
		if tune.has("caption"):
			check(str(audio.captions.visible()).contains(tune["caption"]),"tuned bell keeps its original caption")
		check(audio._cat_of(voice.stream)=="event","tail variants keep the original category for stop and cleanup")
		audio.stop("event")
		check(not voice.playing,"event cancellation stops the selected bell variant")
	audio.stop_all()
	audio.queue_free()
	await _frames(2)
