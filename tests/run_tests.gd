extends SceneTree
## Real engine tests without an addon. All test saves use an isolated directory.

const APP := preload("res://game/app/app.tscn")
var _checks := 0
var _failures: PackedStringArray = []
var _test_path := "user://framework-tests/run-%s/slot.json" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("FAIL: ", message)


func same_json(a: Variant, b: Variant) -> bool:
	# JSON has one numeric type; Godot's nested Dictionary equality is type-strict.
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 0.000001
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not same_json(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for index in a.size():
			if not same_json(a[index], b[index]):
				return false
		return true
	return a == b


func _run() -> void:
	var framework := preload("res://tests/suites/framework.gd").new(self)
	var campus := preload("res://tests/suites/campus.gd").new(self)
	var school := preload("res://tests/suites/school.gd").new(self)
	var story := preload("res://tests/suites/story.gd").new(self)
	var threats := preload("res://tests/suites/threats.gd").new(self)
	var phone := preload("res://tests/suites/phone.gd").new(self)
	var atmosphere := preload("res://tests/suites/atmosphere.gd").new(self)
	var progress := preload("res://tests/suites/progress.gd").new(self)
	var presentation := preload("res://tests/suites/presentation.gd").new(self)
	var integration := preload("res://tests/suites/integration.gd").new(self)
	# Keep the original execution order; splitting suites must not drop coverage.
	framework._test_clock()
	framework._test_modules_and_schema()
	framework._test_storage()
	await framework._test_app()
	campus._test_campus_rules()
	campus._test_elevator_rules()
	school._test_school_rules()
	campus._test_inventory_rules()
	story._test_story_rules()
	threats._test_patrol_rules()
	threats._test_anomaly_rules()
	story._test_routes_rules()
	progress._test_achievements()
	threats._test_garage_rules()
	campus._test_facility_rules()
	phone._test_broadcast_rules()
	phone._test_phone_rules()
	story._test_talent_rules()
	story._test_fake_normal_rules()
	school._test_body_rules()
	story._test_exchange_rules()
	school._test_day_rules()
	school._test_tales_rules()
	school._test_checkup_rules()
	progress._test_speedrun_rules()
	story._test_gaze_rules()
	story._test_paper_rules()
	campus._test_marks_rules()
	school._test_classmates_rules()
	school._test_sensory_rules()
	atmosphere._test_caption_rules()
	atmosphere._test_dread_rules()
	atmosphere._test_atmos_rules()
	atmosphere._test_mono_rules()
	atmosphere._test_scene_rules()
	presentation._test_settings_rules()
	story._test_investigation_rules()
	campus._test_exploration_rules()
	campus._test_drop_rules()
	phone._test_plane_rules()
	phone._test_camera_rules()
	phone._test_snake_rules()
	progress._test_run_new_rules()
	campus._test_duty_rules()
	campus._test_last_life_box()
	campus._test_umbrella_rules()
	campus._test_vault_hold()
	await presentation._test_fake_people()
	presentation._test_call_budget()
	progress._test_score_rules()
	progress._test_run_records()
	progress._test_results_page()
	progress._test_records_panel()
	presentation._test_dev_tools()
	presentation._test_hands()
	presentation._test_opening()
	presentation._test_scene_beats()
	presentation._test_portal_device()
	presentation._test_ending_cut()
	presentation._test_death_cg()
	presentation._test_day_banner()
	presentation._test_chalk_notes()
	presentation._test_chalk_texture()
	presentation._test_phantoms()
	presentation._test_traces()
	presentation._test_weather_fx()
	presentation._test_model_tiers()
	presentation._test_anomaly_traces()
	presentation._test_chase_dash()
	presentation._test_canteen_view()
	presentation._test_mirror_view()
	presentation._test_legacy_save()
	presentation._test_link_view()
	presentation._test_broadcast_props()
	presentation._test_inspection_scatter()
	await integration._test_campus_app()
	await presentation._test_legacy_import()
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_test_path + suffix):
			DirAccess.remove_absolute(_test_path + suffix)
	var death_log := _test_path.get_base_dir().path_join("death_log.json")
	if FileAccess.file_exists(death_log):
		DirAccess.remove_absolute(death_log)
	DirAccess.remove_absolute(_test_path.get_base_dir())
	CampusData.clear_caches()
	print("FRAMEWORK TESTS: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
