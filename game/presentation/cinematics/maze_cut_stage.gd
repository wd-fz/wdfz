class_name MazeCutStage
extends RefCounted
## Presentation inputs for the live or archive maze cut. No save or gameplay callbacks.
var player: PlayerController
var ui: GameUI
var audio: AudioFx
var settings: GameSettings
var geometry: MazeGeometry
var elevator: ElevatorModule
var campus: CampusModule
var scene: Callable
var can_stand: Callable
