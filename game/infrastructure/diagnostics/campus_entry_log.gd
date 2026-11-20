class_name CampusEntryLog
extends RefCounted
## Android owns the process exit record. Checkpoints relate it to the work that
## was in progress, including a failure before Godot can draw or log a frame.

static func available() -> bool:
	return Engine.has_singleton("WdfzEntryDiagnostics")


static func mark(stage: String) -> void:
	if available(): Engine.get_singleton("WdfzEntryDiagnostics").stage(stage)


static func resource_issue(detail: String) -> void:
	if available(): Engine.get_singleton("WdfzEntryDiagnostics").assetIssue(detail)
	push_warning(detail)


static func report() -> String:
	var device := String(Engine.get_singleton("WdfzEntryDiagnostics").report()) if available() else OS.get_name()
	return "%s · Godot %s · %s · %s\n%s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string,
			RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(), device]
