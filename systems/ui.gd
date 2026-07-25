class_name Ui
extends Object

## Shared constructors for UI that scripts build at runtime.
##
## The project theme (roots_theme.tres) dresses every Panel and Button in the
## textbox.png frame, and its default Label colour is LIGHT because bare labels
## sit on the dark full-screen backdrops each screen uses. A panel wearing that
## frame is tan, though, so any label inside one needs DARK text — which is what
## panel_content_theme.tres switches on for a subtree.
##
## Scenes authored in the editor set that theme on the PanelContainer node
## itself. Code that news up a PanelContainer has no such hook, and a plain
## `PanelContainer.new()` renders light-on-tan — invisible. Build cards through
## card() instead and the text comes out right.

const PANEL_CONTENT: Theme = preload("res://resources/ui/panel_content_theme.tres")


## A PanelContainer in the textbox frame, with dark-on-tan text for everything
## added under it.
static func card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme = PANEL_CONTENT
	return panel
