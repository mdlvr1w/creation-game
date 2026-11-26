# Design journal

## 2026-11-26

### Topics and conclusions

- **Project purpose.** Build an original, fully open-source creation game that can support independent communities over time. Establish Linux as the primary target and Windows as supported. Defer console ports.
- **Creative scope.** Center the game on its editor and player-made experiences. Start from layered platforming and leave room for top-down, plain 2D, and true 3D projects.
- **Starter experience.** Give the editor and the cartoon mannequin a playful visual identity and supply a ready-to-use kit of materials, shapes, logic, objects, and decorations. Give creators control over the look and behavior of their own games and characters.
- **Editing and play.** Make building feel like interacting with the game world. Aim for an enjoyable first five minutes and enough power and precision for years of creation.
- **Creator parity.** Treat starter content as working examples of the same creative capabilities players should have. Support inspection, disassembly, modification, and reuse across objects, character movement, and other starter content.

- **Editor identity.** A playable mannequin alone cannot make a conventional authoring workflow feel like a creation game. Judge the editor by what it feels like to build, test, and revise a playable thing. A useful early test would be to place a platform, make it react to a landing, try it, and tune it without losing your place in the world.

### Examples discussed

- Place a springboard, jump on it, and drag its launch arc to change the jump. Open the object to see the landing trigger, launch, sound, and animation. Reuse the trigger to make a collapsing floor, then package that floor with a few editable controls.
- Try a jump, move the ledge, and retry from the same spot. Drag for direct manipulation, snap to layers for alignment, and enter a value when exact placement matters. A reversible playtest could let someone try a destructive physics interaction safely.
- Step onto a switch and see which signal fired, what it carried, and where it stopped. Connect simple objects into multi-step puzzles using the same tools.
- Start by changing the mannequin's face or outfit, then adjust acceleration, landing, or layer switching. Open its behavior to understand grounded detection and animation triggers. Reuse layer switching on a vehicle or replace movement for a top-down game.
- Imagine independent communities with their own collections and publishing rules. Direct sharing, portable playable copies, and separately shareable editable projects are possible ways to support that model.

### Open questions

- Where should the boundary sit between foundational systems such as physics, rendering, and input, and the editable building blocks available to creators? How can the starter movement help reveal gaps in those tools?
- How should hands-on editing, exact controls, logic inspection, and playtest reset fit into a single workflow?
- Which tools can be shared across layered, top-down, 2D, and 3D projects, and what should each mode support first?
- How far should built-in character modeling and asset creation go, and what should creators be able to import?
- How should community hosting, discovery, moderation, portability, and editable project sharing work? Which licenses should apply to code, bundled assets, and creator-made work?

### Hardware accessibility and performance limits

LittleBigPlanet's thermometer prompted a decision about creative limits. In this game, performance feedback should help creators make tradeoffs while leaving the decision to continue building in their hands. The editor has baseline system requirements, and each project can add demands on top of them. A simple 2D arcade shooter could potentially be built and played on an older laptop. A 3D top-down level with dynamic lights, volumetric clouds, and other effects could require substantially more capable hardware for both editing and play. Specific hardware targets are open. Performance feedback should explain what someone is experiencing and what they can change in terms they can use.

Open questions include what baseline hardware to support and what smooth editing and play mean on it, which measurements make warnings useful, and how players can judge a creation's demands on their own hardware.

### How creation should feel

Vibecoding can feel like shaping Play-Doh. The creator shapes an idea, sees it take form, and wants to keep tinkering when the result matches what they imagined. The analogy describes the desired feedback loop and the pleasure of shaping something. In the editor, roaming through the world as a character while building it could make that loop feel like play.

An idea to explore is letting the level's creator expose selected editing tools during play. A puzzle could let players reshape designated blocks to make a bridge. The level author could decide which blocks are editable and which tools are available. A proposed model preserves the published level and gives each playthrough its own changes. Restarting can clear those changes. Authors could allow players to copy the baseline or save the state they reached, with sharing as a possible next step. A reshaped bridge could be a solution for the current run or, with the author's permission, part of a saved version that someone else can play.

This extends creative freedom into playing, creating during play, and sharing the result. An editing tool can supply the mechanic itself. The author decides what players can reshape and designs the challenge around that ability. The baseline model is one option to explore, and the exact permissions and sharing workflow remain open.

### Cursor play and character control

The editor can be a player's first encounter with the game. Treat the mouse cursor as a playful way to act on the world directly. A creator can build an entire level without simultaneously steering a character, and can take control of one whenever they want to experience the world from inside it.

Try a jump once, select the ledge's corners, and pull them toward the spot where the character landed. Pick up a character with the mouse, move it, and let it drop or throw it. Bring up a contextual menu where the cursor is working. These are examples of direct interaction to explore. LittleBigPlanet's Popit cursor and character-local menus are references for immediacy. The proposed workflow gives the cursor a central role of its own.

An author could also expose selected cursor interactions during play. The exact controls and the transition between cursor and character control remain open.

### Physics as a way to build

A creator can build a castle, collapse it in a physics experiment, and choose what happens next. They can restore the castle or preserve the resulting ruins. They could also keep selected results, such as the rubble by the gate, while restoring the rest of the castle. The design distinguishes the authored world from the live simulation and gives creators a deliberate way to bring results back into the authored world.

Explore how to make it clear which actions change the authored world, what will be kept when only part of a simulation is saved, and how to make those choices without interrupting play. Keep exact placement available in the same workflow. For example, a creator could enter an exact position and angle for a hinge, then grab and swing the gate to test it. The controls for moving between the cursor, camera, and character are still open.

### Playable forms beyond the mannequin

A creation could use a 2D side-scrolling character, a ship in a Space Invaders-style arcade game, or sprites in a 3D scene. Creators could also start with the mannequin and reshape it into something nonhumanoid, such as a T. rex or a centipede. Adding limbs and changing proportions should be playful, and creators should be able to change how the body moves and try it in the world.

These examples establish creative scope. How appearance, collision, animation, and movement work together for very different bodies remains a design question to revisit later.

### Character engine and community specialization

The character engine expands the earlier movement system concept to include anatomy, appearance, animation, physical properties, behavior, abilities, and input. The mannequin should be an example built with these systems. Different playable forms should use the capabilities they need.

Someone could browse community-made dragons, recolor one, change its anatomy or behavior, or build a creature of their own. Specialists could share animations, locomotion systems, logic, or mechanisms independently of a level or a complete character. Spending an evening with friends building ridiculous creatures and seeing how they move would count as a satisfying play session on its own.

Composable tools should help creators solve the locomotion and animation problems posed by unusual bodies. Automatic support for every body is outside the goal. How components express their requirements, what remains interchangeable after a body changes, and how to make incompatibilities understandable are questions for later exploration.

### Nested groups and object behavior

Explore organizing a world into objects and nested groups, drawing on Blender's collections. A castle could contain an arch made from individual stones or represented as one object. The creator could address the arch as a unit and give it behavior distinct from the rest of the castle. It could resist a collapse, have its own weight, disappear on contact, or resize in response to an event.

Grouping gives creators a way to select and organize parts of a world. How a group shares physical behavior, how its members can have individual rules, and how it interacts with surrounding objects remain open. In the castle example, an arch that resists damage could still fall when its supports disappear. Making it stay in place would express a different intention.

Prototypes should support meaningful hands-on evaluation by creators with no coding experience.

### Shared architecture for structures and characters

A castle and a dragon can both be assemblies of nested groups, physical parts, and behaviors. The castle's gate and the dragon's wing both offer cases where grouping, joint behavior, and event logic can be edited independently. Shared tools could make skills learned while building a mechanism transferable to creature creation.

Accessible abstractions without inaccessible foundations is the design principle. Someone can try a ready-made gait immediately. Someone who understands locomotion can open up the behavior, see how it drives the body, change it, or create a new one. How creators navigate these relationships and how deeply they can author new behaviors are questions to explore.

### Before the first prototype

The first development goal is to give the project owner enough in-game construction tools to make the starter mannequin. A stick figure assembled from points and lines can be the first test. Any missing capability the creator encounters can inform the next small change to the tools. The visual presentation can start flat while the choice of simulation space is evaluated separately. Recording a performed gesture over time and editing it as keyframes remains an idea for later exploration.

Develop publicly under an open-source license from the start of implementation. Prioritize readable code, documented technical decisions, automated checks, and a repeatable build that other developers can run and maintain. The project license and hosting destination remain open.

Godot 4 is a candidate for a first prototype, pending validation. An orthographic view of a 3D workspace would let the first figure look flat while leaving room to test depth and joints. That choice would apply to the first workspace. Future 2D projects could use dedicated 2D simulation and rendering. The initial workspace, available rendering features, and hardware baseline must be evaluated independently.

### First implementation

The project owner authorized implementation and chose to leave the game unnamed. The initial workspace uses Godot 4.5.1, Compatibility rendering, and an orthographic 3D view with planar editing. The first tools let the creator make a figure from points and links, reshape it, swing a link around a point, and save and reopen the result. This tests construction in the game itself. Swinging a link edits its pose. Physical joints, locomotion, and action recording remain future experiments.

### Public development

The project will be developed at [mdlvr1w/creation-game](https://github.com/mdlvr1w/creation-game) under the MIT License. The repository slug is a working identifier while the game remains unnamed. Publish code, build instructions, and current design decisions together. Keep GitHub current as development proceeds.

### First playtest and articulated construction

The project owner built a basic stick figure with little effort. Placing and connecting points felt intuitive. Manipulating the figure revealed four opportunities that apply to characters, mechanisms, and environments alike.

- **Rotation precision.** Preserve free swinging and explore optional angle increments and exact angle entry. The reference direction and the parts affected by the rotation should be visible.
- **Symmetry.** Explore a creator-defined centerline or plane that can mirror placement and connections. Mirroring during creation and keeping both sides synchronized over time are distinct ideas. Symmetry should apply to any suitable structure.
- **Transform hierarchy.** Explore explicit parent–child relationships so a creator can carry the forearm and hand when moving the upper arm. Transform relationships should be independently configurable alongside organizational, physical, and behavioral relationships. A visible link alone should not imply parenting or a physical joint.
- **Placement precision.** Preserve free placement and explore optional grid snapping, horizontal and vertical alignment guides relative to existing points, and temporary snapping through a modifier. Guides should make the active alignment clear.

The proposed next focus is making articulated construction natural, precise, and enjoyable before exploring locomotion. These observations guide the next design discussion. The controls, precedence between snap targets, and order of implementation are open.

### Building directly from the figure

Explore making the creation itself the interface. A selected point could show directional handles. Dragging one would preview a new point along that axis and its connection to the source. Releasing would place and connect the point in one gesture. Selection could then move to the new point, so the creator can immediately extend the structure again. Alignment guides, grid snapping, and numerical controls can complement extrusion when placing or adjusting points elsewhere.

The proposed interaction model keeps an idle object clear of controls, highlights it subtly on hover, and reveals a few relevant handles on selection. A contextual menu could offer naming, parenting, properties, and precise configuration. During a drag, the workspace could show only feedback relevant to the gesture, such as length or angle. Toolbars can support operations that apply to the whole workspace.

Points and connections could have optional names, such as Elbow and Forearm, to help creators identify them when inspecting larger structures. Names describe the creator's intent. Parenting and other relationships are configured independently.

A small next experiment could test the direct interaction loop by building a head, neck, and spine with repeated extrusion. Handle positioning, how selection transfers without crowding nearby points, and when naming should enter the prototype remain open.

### Focus for the next construction playtest

Explore mirroring as an optional modifier of creative actions. Extrusion is a first candidate, with placement, connections, rotation, and other actions to consider as their behavior becomes clearer. Preview both sides before committing a mirrored gesture. A new point on the centerline can be shared by both sides. Off-center naming conventions and persistent symmetry remain open.

Explore both directional and unrestricted extrusion in the same direct manipulation workflow. Directional extrusion gives a precise axis. Unrestricted extrusion lets the creator choose an angle by dragging. Both should support continuing from the new point. A small playtest could compare a straight spine with a bent arm, then return to the shoulder to start another branch. Evaluate how enjoyable and satisfying each gesture feels, as well as how easily it produces the intended shape. A limited mirrored extrusion test could follow once those gestures are easy to read.

### Second prototype

Selected points offer four directional pulls and one free pull in the existing placement tool. A pull previews a link and its length. Release creates the link and selects its endpoint. Escape cancels the gesture. Handles yield to nearby points so branching remains possible.

Mirror extrusion is a workspace toggle with a fixed vertical centerline for this build. New placements near the line snap to it while the toggle is active. A centered source can branch to both sides, and an off-center source needs a matching point across the line. Mirroring applies to extrusion as it happens. The figure format and its existing point and link semantics are unchanged.

### Contextual mirroring and hover help

Playtest feedback showed that the workspace mirror toggle and fixed centerline were hard to connect to the selected point. A missing opposite point could prevent extrusion outright. Mirroring now lives on a selected point's handles. Clicking it arms the next pull around that point, and a sideways pull grows two links from the same source. The arrows, ring, and mirror handle explain their actions on hover.
