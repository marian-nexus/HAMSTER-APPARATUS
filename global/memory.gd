class_name Memory extends Node

const ass_sen = {"satisfaction": 1, "respect": 0, "fear": -1,
	"joy": 1, "boredom": -1, "betrayal": -1, "resentment": -1}

var target: Object
var context: String
var associations = []:
	set(value):
		var accepted_items := ass_sen.keys()
		var new_array := []
		for item in value:
			if not item in accepted_items: printerr(item + " is not an acceptable memory association")
			elif item in new_array: continue
			else:
				new_array.append(item)
				sentiment += ass_sen[item]
		associations = new_array
var sentiment := 0
