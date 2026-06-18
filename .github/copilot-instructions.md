# FlowKit Development Guide

FlowKit is a Godot 4 editor plugin for visual event-driven programming, inspired by Clickteam Fusion/Construct event sheets.

## Architecture Overview

**Plugin Structure**: FlowKit is a dual-mode system with editor-time visual authoring and runtime execution:

- **Editor side** (`flowkit.gd`, `ui/`): Godot `@tool` plugin that adds a bottom panel for visual event editing
- **Runtime side** (`runtime/flowkit_engine.gd`, `runtime/flowkit_system.gd`): Autoloaded singletons that execute event sheets during gameplay
- **Registry system** (`registry.gd`): Auto-discovers and instantiates provider scripts at plugin load
- **Generator system** (`generator.gd`): Automatically generates actions, conditions, and events from scene node types and their properties/methods/signals

**Event Sheet Model**: Scene-specific `.tres` resources saved to `saved/event_sheet/{scene_name}.tres`:

```
FKEventSheet
  └─ events: Array[FKEventBlock]
      ├─ event_id: String (e.g., "on_process")
      ├─ target_node: NodePath (node to poll event from)
      ├─ conditions: Array[FKEventCondition] (all must pass)
      └─ actions: Array[FKEventAction] (executed sequentially)
```

**Provider Pattern**: All events/conditions/actions extend base classes (`FKEvent`, `FKCondition`, `FKAction`) implementing:

- `get_id()`: Unique identifier string
- `get_name()`: Display name for UI
- `get_supported_types()`: Array of compatible node class names (e.g., `["CharacterBody2D"]`)
- `get_inputs()`: Array of `{"name": String, "type": String}` dictionaries for parameters
- Execution method: `poll(node)`, `check(node, inputs)`, or `execute(node, inputs)`

## Critical Workflows

**Creating New Providers**:

1. Add `.gd` file to `actions/{NodeType}/`, `conditions/{NodeType}/`, or `events/{NodeType}/`
2. Extend `FKAction`, `FKCondition`, or `FKEvent`
3. Implement required methods (see base classes in `resources/` directory)
4. Registry auto-discovers on plugin reload (no manual registration needed)
5. **Alternative**: Use `generator.gd` to auto-generate providers from scene nodes - it introspects node properties, methods, and signals to create boilerplate providers

**Event Sheet Execution** (runtime):

- FlowKit engine detects scene changes via `get_tree().current_scene`
- Loads matching `.tres` from `saved/event_sheet/{scene_name}.tres`
- Each `_process()` frame:
  1. Polls event triggers (`registry.poll_event()`)
  2. Evaluates conditions (`registry.check_condition()`)
  3. Executes actions if all conditions pass (`registry.execute_action()`)

**Editor UI Flow** (adding actions):

1. User clicks "Add Action" → `select_action_node_modal` shows scene tree
2. Select target node → `select_action_modal` filters actions by `get_supported_types()`
3. Select action → `expression_editor_modal` for input parameters (if needed)
4. Save to `.tres` → UI refreshes with new action node

**Modal Dialog Chain** (detailed workflow):

```
Add Action Flow:
  _on_add_action_button_pressed()
  ↓ (stores pending_action_node_path)
  select_action_node_modal.popup_centered()
  ↓ emits node_selected(node_path, node_class)
  _on_select_action_node_selected()
  ↓ (stores pending_action_id, pending_action_inputs)
  select_action_modal.popup_centered()
  ↓ emits action_selected(node_path, action_id, inputs)
  _on_select_action_modal_action_selected()
  ↓ (if inputs.size() > 0)
  expression_editor_modal.popup_centered()
  ↓ emits expressions_confirmed(node_path, action_id, expressions)
  _on_expression_editor_confirmed()
  ↓ calls _create_action_with_expressions() or _update_action_with_expressions()

Add Condition Flow:
  _on_insert_condition_requested(node)
  ↓ (stores pending_condition_node_index, pending_condition_index)
  select_condition_node_modal → select_condition_modal → condition_expression_editor_modal
  ↓ follows same signal chain pattern
  _create_condition_with_expressions() or _update_condition_with_expressions()
```

Each modal step stores context in `pending_*` variables (e.g., `pending_action_node_path`, `pending_condition_index`) to maintain state across the workflow. Editing workflows reuse the same modals but set `is_editing_action` / `is_editing_condition` flags.

## Project Conventions

**Resource Naming**: Event sheets MUST match scene filename: `world.tscn` → `world.tres`

**Node Path Resolution**: All `target_node` paths are relative to scene root (`get_tree().current_scene`). Use `get_node_or_null()` to handle missing references.

**Typed Arrays**: Use strict typing for resource arrays:

```gdscript
@export var events: Array[FKEventBlock] = []  # Not Array
```

**Provider Discovery**: Registry uses recursive directory scanning. Organize providers by node type (e.g., `actions/CharacterBody2D/`) for clarity, but structure doesn't affect registration.

**Editor Interface Pattern**: Custom modals receive `EditorInterface` via `set_editor_interface()` to access scene tree and node icons. See `ui/modals/select_action.gd`.

**State Management**: Editor UI uses pending variables (e.g., `pending_action_node_path`) to track multi-step workflows across modal dialogs.

## Code Style and Naming Conventions

**Variable Naming**:

- **Snake case** for all variables: `event_index`, `action_providers`, `selected_node_path`
- **Resource members** prefixed by purpose: `pending_action_*` (workflow state), `selected_*` (current selection)
- **Node references** suffixed with type: `label`, `context_menu`, `item_list` (not `labelNode`)

**Function Naming**:

- **Private helpers**: Prefix with `_` (e.g., `_load_folder`, `_scan_directory_recursive`, `_update_label`)
- **Signal handlers**: Use pattern `_on_{emitter}_{signal_name}` (e.g., `_on_context_menu_id_pressed`)
- **Public API methods**: No prefix (e.g., `set_action_data`, `populate_inputs`)
- **Provider interface**: Use `get_*` pattern (e.g., `get_id()`, `get_name()`, `get_supported_types()`)

**Signal Naming**:

- Use past tense for events: `node_selected`, `action_selected`, `expressions_confirmed`
- Use `_requested` suffix for UI actions: `insert_action_requested`, `delete_condition_requested`

**Type Hints**:

- Always specify return types: `func get_id() -> String:`
- Use typed variables where possible: `var dir: DirAccess = DirAccess.open(path)`
- Prefer Godot class names over `Variant`: `var instance: Variant` (when dynamic), `var node: Node` (when known)

**Scene Tree Access**:

- Use `get_node_or_null()` for optional nodes: `var label = get_node_or_null("Panel/MarginContainer/HBoxContainer/Label")`
- Defer node access in `_ready()` when needed: `call_deferred("_setup_context_menu")`
- Use `@onready` for guaranteed child nodes: `@onready var menubar := $ScrollContainer/MarginContainer/VBoxContainer/MenuBar`

## Key Integration Points

**Runtime Autoloads**: Two singletons added in `_enter_tree()`:

```gdscript
add_autoload_singleton("FlowKitSystem", "res://addons/flowkit/runtime/flowkit_system.gd")
add_autoload_singleton("FlowKit", "res://addons/flowkit/runtime/flowkit_engine.gd")
```

- `FlowKitSystem`: System-level utilities and global state management
- `FlowKit`: Main execution engine for event sheet processing

**Scene Detection**: Engine uses deferred `_check_current_scene()` + `_process()` polling to handle scene changes robustly (works even if scene loads before engine ready).

**UI-Resource Sync**: Editor saves via `ResourceSaver.save()`, then calls `_display_sheet()` to rebuild UI from saved resource (single source of truth).

## Common Pitfalls

- **Forgetting `@tool`**: Editor scripts must have `@tool` directive
- **Node path timing**: Use `get_node_or_null()` since nodes may not exist if sheets reference deleted objects
- **Array assignment**: Godot requires creating NEW typed arrays when modifying resources (can't append to existing)
- **Modal workflow**: Multi-step dialogs need pending state variables to pass data between steps

## File References

- Provider examples: `actions/Node/print.gd`, `events/on_process.gd`
- Resource schemas: `resources/event_sheet.gd`, `resources/event_block.gd`
- Editor workflow: `ui/editor.gd` (\_on_add_action_button_pressed → \_create_action_with_expressions)
- Runtime loop: `runtime/flowkit_engine.gd` (\_run_sheet)
- Generator system: `generator.gd` (auto-generates providers from node introspection)
- Expression evaluator: `runtime/expression_evaluator.gd` (evaluates GDScript expressions in action/condition inputs)
