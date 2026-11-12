extends CanvasLayer
## Esc pauses. "Abandon Run" ends the run (counts as a death - permadeath).

signal abandon_requested

@onready var resume_button: Button = %ResumeButton
@onready var abandon_button: Button = %AbandonButton


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_toggle)
	abandon_button.pressed.connect(func() -> void:
		get_tree().paused = false
		visible = false
		abandon_requested.emit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		resume_button.grab_focus()
