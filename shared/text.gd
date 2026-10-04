class_name Text
extends RefCounted
## Translatable messages. A message is [key, args]: key is the English format string
## (gettext-style, it's also the translation id) and args fill its %s / %d. Messages are
## built where the facts are (often the server) and rendered where they're shown, so each
## player reads them in their own language. String args are translated too, so content
## names ("Ember Hound") can be localized. tools/extract_strings.py collects every key.


static func message(key: String, args := []) -> Array:
	return [key, args]


## The rendered text, or "" for an empty message (meaning "no message", e.g. no error).
static func render(msg: Array) -> String:
	if msg.is_empty():
		return ""
	var args := []
	for arg in msg[1]:
		args.append(TranslationServer.translate(arg) if arg is String else arg)
	var key := TranslationServer.translate(msg[0])
	return key % args if not args.is_empty() else key
