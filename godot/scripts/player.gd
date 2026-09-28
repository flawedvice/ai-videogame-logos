extends CharacterBody2D


enum State {
	IDLE,
	DEAD,
	MOVING,
	ATTACK,
	HURT,
	LISTENING
}

enum Pose {
	FALL,
	CROUCH,
	STAND
}

@export var Bullet: PackedScene

@export var speed = 100.0
@export var jump_velocity = -175.0
@export var health = 100
@export var state: State
@export var pose: Pose
@export var confused_message := "Sorry, what did you say?"

@onready var animated_sprite = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera
@onready var gun_sound: AudioStreamPlayer2D = $Sounds/GunSound
@onready var step_sound: AudioStreamPlayer2D = $Sounds/StepSound
@onready var crouch_sound: AudioStreamPlayer2D = $Sounds/CrouchSound
@onready var jump_sound: AudioStreamPlayer2D = $Sounds/JumpSound
@onready var land_sound: AudioStreamPlayer2D = $Sounds/LandSound
@onready var stand_sound: AudioStreamPlayer2D = $Sounds/StandSound
@onready var hit_sound: AudioStreamPlayer2D = $Sounds/HitSound
@onready var muzzle: Marker2D = $Muzzle
@onready var scan_timer: Timer = $ScanTimer
@onready var mask_flashlight: PointLight2D = $Lights/MaskFlashlight
@onready var intercommunicator: Node2D = $"../Intercommunicator"
@onready var commands: RichTextLabel = $CommandsLabel
@onready var control: Control = $"../Control"

var muzzle_origin: Vector2
var mask_origin: Vector2
var zoom_tween: Tween
var zoomed = Vector2(4.0, 4.0)
var no_zoom = Vector2(3.0, 3.0)
var direction: float
var in_scan_range: Array[Node2D] = []
var voice_id: String
var effect: AudioEffectRecord
var recording: AudioStreamWAV
var target_node: Node2D
var _tts_id_counter := 0

signal tts_finished(id: int)
signal voice_interact

func _ready() -> void:
	add_to_group("player")
	state = State.IDLE
	pose = Pose.STAND
	muzzle_origin = muzzle.position
	mask_origin = mask_flashlight.position
	
	# TTS
	voice_id = DisplayServer.tts_get_voices_for_language("en")[2]
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_tts_utterance_done)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_tts_utterance_done)
	
	# STT
	var audio_bus_idx = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(audio_bus_idx, 0)
	
	# First instructions
	if control.voice_control_active:
		commands.text = "Press spacebar to speak and release to process"
		speak(commands.text)
		await get_tree().create_timer(2).timeout
		commands.clear()


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
	# User actions
	action()
	# Animation
	animation()
	# Movement
	movement()


func _zoom_to(target: Vector2) -> void:
	if zoom_tween:
		zoom_tween.kill()
	zoom_tween = create_tween()
	zoom_tween.tween_property(camera, "zoom", target, 0.755) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)


# Handle user actions
func action():
	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		jump()
		
	# Handle crouch
	if Input.is_action_pressed("crouch"):
		pose = Pose.CROUCH

	# Handle crouch zoom
	if Input.is_action_just_pressed("crouch"):
		crouch_sound.play()
		_zoom_to(zoomed)
	elif Input.is_action_just_released("crouch"):
		stand_sound.play()
		pose = Pose.STAND
		_zoom_to(no_zoom)
	
	# Handle attack
	if Input.is_action_just_pressed("shoot"):
		attack()
	
	# Handle scans
	if Input.is_action_just_pressed("scan"):
		scan()
	
	# Handle listening
	if Input.is_action_just_pressed("listen") and control.voice_control_active:
		state = State.LISTENING
		commands.text = "Listening"
		speak("I'm listening.")
		_zoom_to(zoomed)
		await zoom_tween.finished
		effect.set_recording_active(true)
		
		
	if Input.is_action_just_released("listen") and control.voice_control_active:
		recording = effect.get_recording()
		effect.set_recording_active(false)
		process_audio(recording)
		state = State.IDLE
		_zoom_to(no_zoom)


# Handle movement and direction
func movement():
	# Handle falls
	var prev_pose := pose
	if not is_on_floor():
		pose = Pose.FALL
	else:
		match prev_pose:
			Pose.FALL:
				land_sound.play()
				pose = Pose.STAND
			Pose.CROUCH, Pose.STAND:
				pose = prev_pose
			_:
				pose = Pose.STAND

	# Update direction
	if not control.voice_control_active:
		direction = Input.get_axis("move_left", "move_right")
	
	# Update state
	if not control.voice_control_active:
		var prev_state = state
		if direction:
			state = State.MOVING if prev_state == State.IDLE else prev_state
		else:
			state = State.IDLE if prev_state == State.MOVING else prev_state
	
	# Update aiming
	var muzzle_x = muzzle_origin.x
	var muzzle_y = muzzle_origin.y + 8.0 if pose == Pose.CROUCH else muzzle_origin.y
	if direction > 0:
		muzzle_x = abs(muzzle_origin.x)
	elif direction < 0:
		muzzle_x = abs(muzzle_origin.x) * -1
	else:	# Else, keep muzzle position
		muzzle_x = muzzle.position.x
	
	muzzle.position = Vector2(muzzle_x, muzzle_y)
	
	# Update velocity
	if direction and state == State.MOVING:
		velocity.x = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
	
	# Perform movement
	move_and_slide()


## Handle animations
func animation():
	# Change direction of animation
	var mask_x = mask_origin.x
	var mask_y = mask_origin.y
	if direction > 0:
		animated_sprite.flip_h = false
	elif direction < 0:
		animated_sprite.flip_h = true
		mask_x = mask_origin.x * -1
	
	if pose == Pose.CROUCH:
		mask_y += 4
	mask_flashlight.position = Vector2(mask_x, mask_y)
	mask_flashlight.look_at(mask_flashlight.global_position + Vector2(direction, 0))
	
	match state:
		State.HURT:
			hit_sound.play()
			state = State.IDLE
		State.DEAD:
			animated_sprite.play("death")
			await animated_sprite.animation_finished
			get_tree().reload_current_scene()
		State.ATTACK:
			if pose == Pose.CROUCH:
				animated_sprite.play("crouch_attack")
			else:
				animated_sprite.play("attack")
			await animated_sprite.animation_finished
			state = State.IDLE
		State.MOVING:
			if pose == Pose.FALL:
				animated_sprite.play("jump")
			else:
				animated_sprite.play("move")
		State.IDLE, _:
			if pose == Pose.FALL:
				animated_sprite.play("jump")
			elif pose == Pose.CROUCH:
				animated_sprite.play("crouch_idle")
			else:
				animated_sprite.play("idle")


## Handle hits by enemies. Not meant to be used inside the current class.
func hit(val: float):
	if state == State.DEAD: return
	health = clampf(health-val, 0.0, 100.0)
	if health == 0.0:
		state = State.DEAD
	print(health)


## Simple TTS Wrapper for more idiomatic calls.
func speak(message: String):
	_tts_id_counter += 1
	var id := _tts_id_counter
	DisplayServer.tts_speak(message, voice_id, 50, 1.0, 1.0, id)
	while true:
		var finished_id = await tts_finished
		if finished_id == id:
			return


## Scan functionality
func scan():
	_zoom_to(zoomed)
	await zoom_tween.finished
	
	var msg := ""
	if in_scan_range.is_empty():
		msg = "Nothing in the surroundings"
	else:
		var entity_list = []
		for entity in in_scan_range:
			entity_list.push_front([entity, floor((entity.global_position.x - global_position.x) / 10)])
		
		# Sort by distance, closest first
		entity_list.sort_custom(func (a, b): return a[1] < b[1])
		while not entity_list.is_empty():
			var entity_distance = entity_list.pop_front()
			var entity = entity_distance[0]
			var distance = entity_distance[1]
			var entity_direction: String
			if distance < 0:
				entity_direction = "to the left"
			elif distance > 0:
				entity_direction = "to the right"
			else:
				entity_direction = "right here" 
			var location = entity_direction if entity_direction == "right here" else "%d steps %s" % [distance, entity_direction]
			
			if msg.is_empty():
				msg += "Spotted "
			elif entity_list.is_empty():
				msg += ", and "
			else:
				msg += ", "
			msg += "one %s %s" % [entity.entity_name, location]
		
	speak(msg)
	
	scan_timer.start()
	await scan_timer.timeout
	_zoom_to(no_zoom)


## Attack functionality
func attack(target: Node2D = null):
	if control.voice_control_active:
		stop()
		# Point towards target, if provided
		if target:
			direction = clampf(target.global_position.x - global_position.x, -1.0, 1.0)
	
	state = State.ATTACK
	await animated_sprite.animation_finished
	gun_sound.play()
	var bullet_direction = Vector2(-1 if animated_sprite.flip_h else 1, 0)
	var bullet = Bullet.instantiate()
	add_child(bullet)
	bullet.direction = bullet_direction
	bullet.transform = muzzle.transform


## Handle simple jumps
func jump():
	print("jumping")
	if is_on_floor():
		velocity.y = jump_velocity
		jump_sound.play()


# Stop anything the player is doing
func stop():
	if state == State.MOVING:
		direction = 0
	state = State.IDLE

## Process the recorded audio and send it to Whisper
func process_audio(record: AudioStreamWAV):
	speak("Processing.")
	commands.text = "Processing..."
	intercommunicator.send_audio(record)


func process_instructions(instructions: Array[String]):
	
	# Get unique commands
	var instructions_set = {}
	for i in instructions:
		instructions_set[i] = true
	var unique_commands = instructions_set.keys()
	
	# Sort instructions
	var target = []
	var purpose = []
	var rest = []
	for command in unique_commands:
		match command:
			"left", "right", "enemy", "door":
				target.push_back(command)
			"crouch", "move", "stop", "scan", "attack", "interact", "jump", "stand":
				purpose.push_back(command)
			_:
				rest.push_back(command)
	
	# Execute instructions in priority order
	
	# Point towards target
	var current_target: String
	for command in target:
		match command:
			"left":
				current_target = "left"
				direction = -1
			"right":
				current_target = "right"
				direction = 1
			"enemy":
				current_target = "enemy"
			"door":
				current_target = "door"
			_:
				current_target = ""
	
	# Perform action
	var msg := ""
	for command in purpose:
		match command:
			"crouch":
				pose = Pose.CROUCH
				msg += "Crouching."
			"move":
				state = State.MOVING
				msg += "Moving %s." % "left" if direction < 0 else "right"
			"stop":
				stop()
				msg += "Stopped. What now?"
			"attack":
				msg += "Attacking %s." % current_target 
				attack()
			"scan":
				msg += "Scanning my surroundings."
				scan()
			"interact":
				if current_target.is_empty():
					msg += "Interacting."
				else:
					msg += "Interacting with %s." % current_target
				voice_interact.emit()
			"jump":
				msg += "Jumping. Why not?"
				pose = Pose.STAND
				jump()
			"stand":
				msg += "Stand up and guard. Sure thing."
				pose = Pose.STAND
	
	# Print rest for debugging
	for command in rest:
		print(command)
	
	# Speak the received instructions out loud.
	speak(msg)


func _on_scan_range_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") or body.is_in_group("interactables"):
		in_scan_range.append(body)


func _on_scan_range_body_exited(body: Node2D) -> void:
	if in_scan_range.is_empty():
		return
	in_scan_range = in_scan_range.filter(func(node): return node != body)	


func _on_intercommunicator_received_commands(sentence: String, matches: Array) -> void:
	
	if sentence.is_empty() or matches.is_empty():
		commands.text = confused_message
		speak(confused_message)
		await get_tree().create_timer(2).timeout
		print("Clearing after confused")
		commands.clear()
		return
	
	commands.text = sentence
	
	var message: Array[String] = []
	var instructions: Array[String] = []
	for m in matches:
		instructions.push_back(m[0])
	
	var inserted: bool
	for word in sentence.split(" "):
		inserted = false
		# Matches come as tuples of normalized keyword, actual detected word, how it was matched
		for m in matches:
			if word == m[1]:
				inserted = true
				message.push_back("[color=red] %s [/color]" % word)
				break
		if not inserted:
			message.push_back(word)
	
	await get_tree().create_timer(0.5).timeout
	print("Clearing after sentence")
	commands.clear()
	commands.text = "%s" % " ".join(message)
	process_instructions(instructions)

func _on_tts_utterance_done(id: int) -> void:
	tts_finished.emit(id)
