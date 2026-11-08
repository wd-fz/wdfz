class_name WindowGazeView
extends Node3D
## Original window-gaze body and flattened eyes. This node only follows the supplied eye position.

var eyes: Node3D


func build(nz: float) -> void:
	name = "WindowGaze"
	var body := FigureModel.make("person",Color("0b0d0f"),true,1,Color.BLACK,false)
	body.position = Vector3(0,-.05,-nz*.35)
	body.rotation.y = PI if nz>0 else 0 # FigureModel changes the original +Z front to -Z.
	add_child(body)
	eyes = Node3D.new()
	eyes.name = "Eyes"
	eyes.position = Vector3(0,WindowGazeModule.EYE,nz*.16)
	add_child(eyes)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("e8e4d4")
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.disable_fog = true
	for dx: float in [-.045,.045]:
		var eye := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = .014
		ball.height = .028
		ball.radial_segments = 10
		ball.rings = 8
		eye.mesh = ball
		eye.material_override = white
		eye.scale = Vector3(1.5,.8,.4)
		eye.position.x = dx
		eyes.add_child(eye)


func track(player_eye: Vector3) -> void:
	if eyes.global_position.distance_squared_to(player_eye)>.000001:
		eyes.look_at(player_eye,Vector3.UP,true)
