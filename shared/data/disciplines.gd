class_name Disciplines
extends RefCounted
## The four disciplines, chosen at character creation and permanent. Each is one branch of
## the talent tree, and your own discipline's branch gets DISCIPLINE_BONUS_POINTS for free.
## The ids match the backend's list (backend/src/app.ts, DISCIPLINES).

const DISCIPLINE_BONUS_POINTS := 3

const ALL := [
	{"id": "enforcer", "name": "Enforcer", "kind": TechniqueData.Kind.ENFORCER,
		"summary": "Empowers the body. Frontline fighter who holds attention."},
	{"id": "lancer", "name": "Lancer", "kind": TechniqueData.Kind.LANCER,
		"summary": "Projects spirit as strikes. Damage from range."},
	{"id": "controller", "name": "Controller", "kind": TechniqueData.Kind.CONTROLLER,
		"summary": "Commands the space around them. Crowd control and support."},
	{"id": "builder", "name": "Builder", "kind": TechniqueData.Kind.BUILDER,
		"summary": "Forges constructs. Shields, traps and healing wards."},
]


static func is_valid(id: String) -> bool:
	return ALL.any(func(d: Dictionary): return d.id == id)


static func display_name(id: String) -> String:
	for discipline: Dictionary in ALL:
		if discipline.id == id:
			return discipline.name
	return id.capitalize()
