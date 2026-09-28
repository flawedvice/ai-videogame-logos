extends Control

enum Mode {
	NORMAL,
	PEACEFUL
}

@onready var intercommunicator: Node2D = $"../Intercommunicator"
@onready var enemies: Node2D = $"../Enemies"

@export var voice_control_active = true
@export var mode = Mode.NORMAL

var requested_vocabulary = false
var vocabulary: Dictionary
var user_paused: bool

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	user_paused = false
	if mode == Mode.PEACEFUL:
		enemies.queue_free()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if not requested_vocabulary:
		intercommunicator.get_vocabulary()
		requested_vocabulary = true
	
	# Handle pause
	get_tree().paused = user_paused
	
	if Input.is_action_just_pressed("reset"):
		get_tree().reload_current_scene()
	
	if Input.is_action_just_pressed("menu"):
		user_paused = !user_paused
		


func _on_intercommunicator_received_vocabulary(_vocabulary: Dictionary) -> void:
	vocabulary = vocabulary
