extends CharacterBody2D

enum State {
	IDLE,
	DEAD,
	CHASE,
	ATTACK,
	HURT
}

@onready var animated_sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D

@onready var hit_sound: AudioStreamPlayer2D = $Sounds/HitSound
@onready var death_sound: AudioStreamPlayer2D = $Sounds/DeathSound
@onready var step_sound: AudioStreamPlayer2D = $Sounds/StepSound

@onready var detection_range: Area2D = $DetectionRange
@onready var attack_range: Area2D = $AttackRange

@export var state: State = State.IDLE
@export var speed = 50.0
@export var health = 75
@export var damage = 20
@export var entity_name = "enemy"


var dead = false
var target: Node2D

func _ready() -> void:
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		
	animate()
		
	move()

func attack(player: Node2D) -> void:
	state = State.ATTACK
	player.hit(damage)
	

## Used by bullets to deal damage to enemies. Usage not intended for self.
func hit(val: float):
	if state == State.DEAD: return
	state = State.HURT
	health = clampf(health-val, 0.0, 100.0)
	if health == 0.0:
		state = State.DEAD

# Updates direction and moves enemy accordingly.
func move() -> void:
	if state == State.DEAD || state == State.ATTACK: return
	
	var direction = clamp(target.global_position.x - global_position.x, -1.0, 1.0) if target else 0.0
	if direction:
		velocity.x = direction * speed
		if direction < 0:
			animated_sprite.flip_h = true
		elif direction > 0:
			animated_sprite.flip_h = false
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		
	move_and_slide()


## Handle animations
func animate():
	#print(state)
	match state:
		State.HURT:
			animated_sprite.play("hit")
			hit_sound.play()
			await animated_sprite.animation_finished
			state = State.IDLE
		State.DEAD:
			animated_sprite.play("death")
			death_sound.play()
			await animated_sprite.animation_finished
			queue_free()
		State.ATTACK:
			animated_sprite.play("attack")
			await animated_sprite.animation_finished
			state = State.IDLE
		State.CHASE:
			animated_sprite.play("move")
			step_sound.play()
		State.IDLE:
			animated_sprite.play("idle")


func _on_detection_range_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		state = State.CHASE
		target = body


func _on_detection_range_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		state = State.IDLE
		target = null


func _on_attack_range_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		print("Attacking player")
		state = State.ATTACK
		body.hit(damage)
