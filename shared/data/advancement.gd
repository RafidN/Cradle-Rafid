class_name Advancement
extends RefCounted
## Power tiers (shared/data/ranks), sigils (shared/data/sigils) and the aspects of essence.
## Shared so the client can show what's affordable; the server decides.

enum Aspect { FIRE, EARTH, WIND }
## Net ids of ranks and sigils the code refers to directly; a test checks they match the data.
enum Rank { IRON, BRONZE, SILVER }
enum Sigil { TEMPERED_BODY, KINDLED_CORE }

const ASPECT_NAMES := ["Fire", "Earth", "Wind"]
const ASPECT_COLORS := [Color(1.0, 0.5, 0.15), Color(0.8, 0.6, 0.3), Color(0.55, 0.95, 0.85)]

## Essence a fallen spirit practitioner leaves behind (always of their Way's aspect).
const PRACTITIONER_ECHO_ESSENCE := 6
const PRACTITIONER_ECHO_ASPECT := Aspect.FIRE

## Ranks are a ladder: net ids run 0, 1, 2... from the starting tier.
static var ranks := ContentRegistry.new("res://shared/data/ranks")
## Sigil net ids also run 0, 1, 2..., so they can index a practitioner's sigil counts.
static var sigils := ContentRegistry.new("res://shared/data/sigils")


static func rank(net_id: int) -> RankData:
	return ranks.by_net_id(net_id) as RankData


static func rank_count() -> int:
	return ranks.size()


static func rank_name(net_id: int) -> String:
	var data := rank(net_id)
	return data.display_name if data else "?"


static func sigil(net_id: int) -> SigilData:
	return sigils.by_net_id(net_id) as SigilData


static func sigil_count() -> int:
	return sigils.size()


## The rank a technique slot opens at.
static func slot_unlock_rank(slot: int) -> int:
	for net_id in rank_count():
		if rank(net_id).technique_slots > slot:
			return net_id
	return rank_count() - 1
