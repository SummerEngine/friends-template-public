extends RefCounted
## What the menus share: the tagline, and the template's own menu art loaded through the client's asset reader. The clean
## look ships no menu picture: the backdrop is drawn (client/menu_backdrop.gd) unless the cast brings its own title art.
## Look and layout live in menu_skin.gd; type and colours in friends_ui.gd.
const TAGLINE := "Two players · one painting · don't drop it"
static var _asset_reader: Callable

static func set_asset_reader(reader: Callable) -> void:
	_asset_reader = reader

static func fetch_asset(path: String) -> Resource:
	assert(_asset_reader.is_valid(), "Client presentation bootstrap must precede UI construction")
	return _asset_reader.call(path) if _asset_reader.is_valid() else null

## The template's title picture: none (the drawn backdrop shows).
static func backdrop_texture() -> Texture2D: return null
## The template's loading picture: none (the drawn backdrop shows).
static func loading_texture() -> Texture2D: return null
