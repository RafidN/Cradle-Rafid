class_name ContentData
extends Resource
## Base for authored content: attacks, techniques, beasts, zones, ranks, sigils, Ways.
## Content lives in .tres files under shared/data/<type>/, and registries find it there.

## Stable name used by references in data and by saves. Never rename once players exist.
@export var id: StringName
## The number sent over the network. Unique per content type; never reuse a retired one.
@export var net_id := -1
