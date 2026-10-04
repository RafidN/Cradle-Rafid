class_name ContentRegistry
extends RefCounted
## Loads every .tres of one content type from its folder, so adding content means adding
## a file. Content is looked up by string id or net id; `all` is sorted by net id.
## Problems (duplicate or missing ids) are collected in `errors`, which tests check.

var folder := ""
var all: Array[ContentData] = []
var errors := PackedStringArray()

var _by_id := {}
var _by_net_id := {}


func _init(content_folder: String) -> void:
	folder = content_folder
	var seen := {}
	for file in DirAccess.get_files_at(folder):
		# Exported builds list "name.tres.remap"; load() still takes the original path.
		var path := folder.path_join(file.trim_suffix(".remap"))
		if path.get_extension() != "tres" or seen.has(path):
			continue
		seen[path] = true
		var item := load(path) as ContentData
		if item == null:
			errors.append("%s is not content" % path)
		elif item.id == &"" or item.net_id < 0:
			errors.append("%s needs an id and a net_id" % path)
		elif _by_id.has(item.id):
			errors.append("%s: duplicate id '%s'" % [path, item.id])
		elif _by_net_id.has(item.net_id):
			errors.append("%s: duplicate net_id %d" % [path, item.net_id])
		else:
			_by_id[item.id] = item
			_by_net_id[item.net_id] = item
			all.append(item)
	all.sort_custom(func(a: ContentData, b: ContentData): return a.net_id < b.net_id)


func by_id(id: StringName) -> ContentData:
	return _by_id.get(id)


func by_net_id(net_id: int) -> ContentData:
	return _by_net_id.get(net_id)


## -1 if there is no such content (or id is empty).
func net_id_of(id: StringName) -> int:
	var item := by_id(id)
	return item.net_id if item else -1


func size() -> int:
	return all.size()
