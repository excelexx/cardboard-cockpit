extends SceneTree
const Preview = preload("res://systems/camera_preview.gd")

func _initialize() -> void:
	var preview = Preview.new()
	var frame := Image.create(320,180,false,Image.FORMAT_RGB8)
	frame.fill(Color(.2,.6,.8))
	if not preview.accept_frame(frame.save_jpg_to_buffer(),100):
		push_error("Preview rejected a valid JPEG"); quit(1); return
	if preview.texture.get_size() != Vector2(320,180):
		push_error("Preview dimensions changed"); quit(1); return
	if preview.accept_frame("not an image".to_utf8_buffer(),200) or preview.last_received != 100:
		push_error("Invalid preview refreshed freshness"); quit(1); return
	var large := Image.create(640,480,false,Image.FORMAT_RGB8)
	if preview.accept_frame(large.save_jpg_to_buffer(),300):
		push_error("Oversized preview accepted"); quit(1); return
	preview.active_endpoint = "ws://127.0.0.1:8765/preview"
	preview.poll(false,"ws://127.0.0.1:8765")
	if preview.texture != null or preview.last_received != -1:
		push_error("Disabling tracking retained the camera image"); quit(1); return
	print("PASS: Camera JPEG decoding, bounds, invalid frame handling and cleanup")
	quit(0)
