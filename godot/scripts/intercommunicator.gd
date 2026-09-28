extends Node2D

@onready var http_request: HTTPRequest = $HTTPRequest

@export var api_url = "http://127.0.0.1:8000"

signal received_commands(sentence: String, matches: Array)
signal received_vocabulary(vocabulary: Dictionary)

func _ready() -> void:
	# Create an HTTP request node and connect its completion signal.
	http_request.request_completed.connect(_on_request_completed)
	
	# Perform a GET request. The URL below returns JSON as of writing.
	var error = http_request.request(api_url + "/ping")
	await http_request.request_completed
	
	if error == OK:
		print("Successfull ping to server.")
	else:
		push_error("An error occurred in the HTTP request.")


func get_vocabulary():
	var headers = ["Content-Type: application/json"]
	
	# Avoid collisions
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		await http_request.request_completed
		
	var err = http_request.request(api_url + "/vocabulary", headers, HTTPClient.METHOD_GET)
	if err != OK:
		push_error("Could not complete get_vocabulary request")
	


func set_vocabulary(vocabulary: Dictionary):
	var headers = ["Content-Type: application/json"]
	# Avoid collisions
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		await http_request.request_completed

	var err = http_request.request(api_url + "/vocabulary", headers, HTTPClient.METHOD_POST, JSON.stringify(vocabulary))
	if err != OK:
		push_error("Could not complete set_vocabulary request")
	


func send_audio(record: AudioStreamWAV):
	var headers = [
		"Content-Type: application/octet-stream",
		"Content-Length: %d" % record.data.size(),
		"X-Sample-Rate: %d" % record.mix_rate,
		"X-Stereo: %s" % str(record.stereo),
		"Cache-Control: no-cache",
		"Cache-Control: no-store",
	]
	# Avoid collisions
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		await http_request.request_completed

	var err = http_request.request_raw(api_url + "/listen", headers, HTTPClient.METHOD_POST, record.data)
	if err != OK:
		push_error("Could not complete send_audio request")

## Makes sure a new HTTP call can be made by waiting previous calls, if any.
func _ensure_http_available():
	var status := http_request.get_http_client_status()
	if status == HTTPClient.STATUS_BODY or status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_CONNECTING:
		await http_request.request_completed


func _on_request_completed(_result, _response_code, _headers, body):
	if _response_code != 200:
		print("Error on the server")
		received_commands.emit("", [])
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		print("Error on the server")
		received_commands.emit("", [])
	# Handle command parsing from /listen
	elif json["endpoint"] == "/listen" and json["status"] == "OK":
		var results = json["results"]
		if results["sentence"] != null and results["matches"] != null:
			print("Received commands:", results["sentence"])
			received_commands.emit(results["sentence"], results["matches"])
		else:
			received_commands.emit("", [])
	elif json["endpoint"] == "/vocabulary" and json["status"] == "OK":
		if json["method"] == "POST":
			print(json["message"])
		elif json["method"] == "GET":
			print("Got vocabulary!")
			received_vocabulary.emit(json["vocabulary"])
	
