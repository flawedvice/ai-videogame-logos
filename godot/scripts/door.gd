extends StaticBody2D

@onready var interaction_range: Area2D = $InteractionRange
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var label: Label = $Label
@onready var open_sound: AudioStreamPlayer2D = $Sounds/OpenSound
@onready var close_sound: AudioStreamPlayer2D = $Sounds/CloseSound

@export var entity_name = "door"

var open = false
var on_range = false
var pending_interaction = false

func _ready() -> void:
	add_to_group("interactables")
	label.text = "Interact with door"
	label.hide()

func _process(_delta: float) -> void:
	var interact = Input.is_action_just_pressed("interact") or pending_interaction
	if on_range and interact:
		pending_interaction = false
		if open:
			animated_sprite_2d.play("close")
			close_sound.play()
			await animated_sprite_2d.animation_finished
			collision_shape_2d.disabled = false
			open = false
		else:
			animated_sprite_2d.play("open")
			open_sound.play()
			await animated_sprite_2d.animation_finished
			collision_shape_2d.disabled = true
			open = true

func _on_interaction_range_body_entered(_body: Node2D) -> void:
	label.show()
	on_range = true
	

func _on_interaction_range_body_exited(_body: Node2D) -> void:
	label.hide()
	on_range = false


func _on_player_voice_interact() -> void:
	if on_range:
		pending_interaction = true
