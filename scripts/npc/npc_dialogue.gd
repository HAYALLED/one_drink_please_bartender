class_name NpcDialogue
extends RefCounted

## Speech lines for customers. Texts live in dictionary.csv as "say_<category>_<trait>_<n>" (n starts at 1).
## POOLS lists how many variants each category/trait has. New line = new csv row + bump the count here.
## "any" is the shared pool used by every trait; a trait pool is mixed in on top of it.

const TRAIT_POOL_CHANCE := 0.65

const POOLS := {
	"greet": {"any": 3, "neutral": 2, "innocent": 2, "hot_blooded": 2, "greedy": 2, "straight_forward": 2},
	"thanks": {"any": 2, "innocent": 2, "hot_blooded": 1, "greedy": 2, "straight_forward": 2},
	"wrong": {"any": 3, "innocent": 1, "hot_blooded": 2},
	"late": {"any": 3, "innocent": 2, "hot_blooded": 2, "greedy": 1, "straight_forward": 1},
	"smalltalk": {"any": 6, "innocent": 2, "hot_blooded": 1, "greedy": 2},
	"reply": {"any": 3},
	"drunk": {"any": 4},
	"provoked": {"any": 3},
	"whisper": {"greedy": 3},
	"threat": {"any": 3, "hot_blooded": 2},
	"brawl": {"any": 3},
	"plead": {"innocent": 2},
	"stay": {"any": 3, "innocent": 1, "greedy": 1},
	"objects": {"any": 2},
	"collector_greet": {"any": 3},
	"collector_forced": {"any": 3},
	"collector_paid": {"any": 3},
	"collector_borrow": {"any": 3},
	"collector_broke": {"any": 2},
	"collector_no_debt": {"any": 2},
}


static func has_pool(category: StringName) -> bool:
	return POOLS.has(String(category))


## Random line for a category, or "" when there is nothing to say.
static func line(category: StringName, trait_key: StringName) -> String:
	var pool: Dictionary = POOLS.get(String(category), {})
	if pool.is_empty():
		return ""
	var own := String(trait_key)
	var use_own := pool.has(own) and (not pool.has("any") or randf() < TRAIT_POOL_CHANCE)
	var chosen := own if use_own else "any"
	if not pool.has(chosen):
		return ""
	var count := int(pool[chosen])
	if count <= 0:
		return ""
	return Loc.t("say_%s_%s_%d" % [category, chosen, randi_range(1, count)])