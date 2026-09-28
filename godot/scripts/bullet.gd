extends Area2D

@onready var hit_sound: AudioStreamPlayer2D = $HitSound

@export var speed = 750
@export var damage = 30
@export var direction: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	hit_sound.play()
	if body.is_in_group("enemies"):
		if body.dead:
			return
		body.hit(damage)
	else:
		pass
	queue_free()


	
