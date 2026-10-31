extends StaticBody3D
## A hold-to-use object (terminal, valve panel). The player script raycasts
## against the "interact" physics layer and drives `progress`.

signal completed(who)

var prompt := "Use"
var hold_time := 2.0
var done := false
var locked_message := "Locked."
## Optional callable returning bool; when it returns false the object is locked.
var unlock_check := Callable()


func is_unlocked() -> bool:
	if unlock_check.is_valid():
		return unlock_check.call()
	return true


func can_use() -> bool:
	return not done and is_unlocked()


func get_prompt() -> String:
	if done:
		return ""
	return prompt


func complete() -> void:
	if done:
		return
	done = true
	completed.emit(self)
