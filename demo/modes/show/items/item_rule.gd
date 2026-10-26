extends RefCounted
## The rules side of one show item or event (modes/show/items/items.gd): what it does on the authority. Extend this in `<id>_rules.gd`; the id is the catalog's (catalog.gd KINDS).
## A rule never touches a node and never reads a client file; the numbers it uses come from `items.tune(id, key)` (items.json, the cast's `tuning`). Everything it leaves for the views is an
## effect (`items.add_fx`), a projectile (`items.spawn`) or an announcement (`items.announce`); an effect that changes how its owner's courier moves is read by the owner's machine from the
## replicated effect (the view's `mods`, modes/show/items_ui/item_look.gd), the rule does not move couriers (it may `host.send_to` one).
var items ## modes/show/items/items.gd
var id := ""
var aimed := -1 ## set by `use()` of an item that flies at somebody: the slot it goes for (the USE event carries it, so the line names the victim before the shot lands)

func setup(system, kind_id: String) -> void:
	items = system
	id = kind_id

## A race round starts: forget what the last round left.
func begin() -> void:
	pass

## A held item (smash, call, flip, glitch, dance): `user` pressed ITEM. Return true when it was used up; false keeps the item with its player (nobody to hit).
func use(_user: int) -> bool:
	return false

## An event (boost, soar): the clock chose `slot` (a runner at the back).
func happen(_slot: int) -> void:
	pass

## Every play tick.
func tick(_dt: float) -> void:
	pass

## An effect of this kind ran its time out (not one taken off early).
func ended(_entry: Dictionary) -> void:
	pass
