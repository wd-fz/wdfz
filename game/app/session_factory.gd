class_name SessionFactory
extends RefCounted
## Explicit composition of rule modules and trusted content. Registration order is stable.


static func create() -> GameSession:
	var rooms := CampusData.rooms()
	var campus := CampusData.campus()
	var outdoor := CampusData.layout("out")
	var nav := CampusData.patrol_nav()
	var names := {}
	for id: String in AnomalyModule.DEFS:
		names[id] = String(AnomalyModule.DEFS[id].get("cn", id))
	var features: Array[FeatureModule] = [
		DemoModule.new(),
		CampusData.make_module(),
		ElevatorModule.new(rooms),
		LiftCrowdModule.new(),
		MazeModule.new(CampusData.maze_geometry(), CampusData.maze_data()),
		SchoolModule.new(rooms, outdoor, campus),
		InventoryModule.new(rooms, campus),
		StoryModule.new(),
		KnifeModule.new(),
		WudaKidModule.new(),
		InceptionModule.new(rooms),
		CampusData.make_patrol(),
		CampusData.make_anomaly(),
		RoutesModule.new(campus),
		AchievementsModule.new(AnomalyModule.IDS.size() - 1),
		GarageModule.new(CampusData.layout("garage1")),
		FacilitiesModule.new(rooms, outdoor, campus),
		BroadcastModule.new(rooms, nav),
		PhoneModule.new(),
		TalentModule.new(),
		FakeNormalModule.new(),
		BodyModule.new(rooms),
		ExchangeModule.new(nav, outdoor, campus),
		DayModule.new(),
		TalesModule.new(rooms, CampusData.patrol_data().get("route", {}).get("nodes", [])),
		WindowGazeModule.new(rooms),
		PaperPlaneModule.new(rooms),
		MarksModule.new(rooms),
		ClassmatesModule.new(rooms),
		DreadModule.new(rooms, float(outdoor.get("SC", 1.0))),
		AtmosModule.new(rooms),
		MonoModule.new(rooms),
		InvestigationModule.new(),
		ExplorationModule.new(rooms),
		CameraModule.new(),
		RunScoreModule.new(rooms, outdoor, campus, names),
	]
	var session := GameSession.new()
	for feature in features:
		var error := session.modules.register(feature)
		if not error.is_empty():
			push_error(error)
			return null
	return session
