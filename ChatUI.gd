extends Control

@onready var _NM = get_node("/root/NetworkManager")
@onready var messages_container: VBoxContainer = %MessagesContainer
@onready var scroll: ScrollContainer = %ChatScroll
@onready var input_field: LineEdit = %ChatInput
@onready var send_btn: Button = %SendBtn
@onready var toggle_btn: Button = %ChatToggleBtn
@onready var chat_panel: PanelContainer = %ChatPanel

var _max_messages: int = 50
var _collapsed: bool = false

func _ready() -> void:
	_NM.chat.connect(_on_chat_message)
	send_btn.pressed.connect(_send_message)
	input_field.text_submitted.connect(_on_text_submitted)
	toggle_btn.pressed.connect(_toggle_chat)
	focus_mode = Control.FOCUS_NONE

func _on_chat_message(player_id: int, player_name: String, message: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.focus_mode = Control.FOCUS_NONE
	label.add_theme_font_size_override("normal_font_size", 14)
	if player_id == _NM.player_id:
		label.text = "[color=#5fba7d][b]" + player_name + ":[/b][/color] " + message
	else:
		label.text = "[color=#6fa8dc][b]" + player_name + ":[/b][/color] " + message
	messages_container.add_child(label)
	while messages_container.get_child_count() > _max_messages:
		messages_container.get_child(0).queue_free()
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _send_message() -> void:
	var msg: String = input_field.text.strip_edges()
	if msg.is_empty():
		return
	_NM.send_chat(msg)
	input_field.text = ""
	input_field.grab_focus()

func _on_text_submitted(_text: String) -> void:
	_send_message()

func _toggle_chat() -> void:
	_collapsed = not _collapsed
	chat_panel.visible = not _collapsed
	toggle_btn.text = ">" if _collapsed else "Chat"
