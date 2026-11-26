# Game vision

Build a fully open-source game where playing, tinkering, and creating feel like parts of the same experience. LittleBigPlanet and Restitched are creative reference points. The project responds to the loss of continuity when a game or service is discontinued and to the value of developing around an open community.

## Platforms and community

Linux is the primary target and Windows is supported. Console ports are outside the current scope. Sharing and discovery should be decentralized so independent communities can host and sustain their own projects. Long-term access to community creations should be independent of a single central service.

## Hardware accessibility and creative limits

The base game and editor will have minimum system requirements. Keep that baseline modest enough that someone could potentially build and play a simple 2D arcade shooter on an older laptop. Beyond that baseline, hardware needs should scale with the project. Building, previewing, and playing a 3D top-down level with dynamic lights, volumetric clouds, and other effects may call for substantially more capable hardware. Specific requirements remain open until they can be tested.

Let each creation set its own performance demands. Warn creators when their work reaches meaningful performance thresholds and let them decide whether to simplify it or keep building. Avoid a universal content cap enforced through a performance meter. Players should be able to understand a creation's likely hardware demands before choosing to play it.

## The editor is the game

The creation tools are the main experience. The project has no built-in story campaign. Players can build their own levels, stories, and games, deciding how they look, feel, and play. Include usable materials, shapes, tools, logic, objects, and decorations from the start, so a new player can immediately make and try something.

Keep editing and playing closely connected. Working in the editor should feel tactile, intuitive, playful, and satisfying. A complete beginner should be able to enjoy a meaningful creation or modification within five minutes. An experienced creator should have the precision and depth to work for years, including on projects that depart substantially from the starter gameplay.

Design the creation workflow around interacting with a playable world. Placing an object, changing what it does, and trying it should feel like a continuous activity. Bring precise controls and deeper inspection into that workflow when creators need them. Use this as a design constraint when borrowing features from general-purpose tools such as Blender, Unreal Engine, or Godot.

Aim for the feeling of shaping Play-Doh. A creator can try an idea, feel the result quickly, and keep reshaping it as their idea develops. Let creators build directly with a cursor and also control a character in the same world. Building should work without controlling a character at the same time. The cursor is itself a way to play with the world. Creators can shape objects directly, reposition a character, or grab and release something to see how it moves. Make it easy to move between direct manipulation, camera control, and taking control of a character.

Protect the authored world during live physics experiments. Creators should be able to restore its previous state or deliberately keep selected results of the simulation as part of the authored world. Explore how to make that choice in place with minimal interruption. Physics can become a way to construct the world. Give creators precise placement and adjustment alongside physical grabbing and throwing, so they can build mechanisms that depend on exact positions and alignment.

Explore letting creators carry selected editing capabilities into their playable projects. A creator could choose which tools players get and what those tools can affect. The editing tools can become gameplay mechanics in their own right, giving authors ways to build interactions from the same tools they use to create the world.

One model keeps the published level as the baseline and applies edits to the player's own playthrough. Restarting can restore the baseline. The author could allow players to copy the published version, save the version they made while playing, or share a resulting creation.

## Worlds and visual identity

The starting play style is a layered platformer built around a classic three-layer or multilayer world. Creators should also be able to make sophisticated top-down games and explore plain 2D and true 3D as the tools develop. The scope and sequencing of those modes remain open.

Give the starter editor and character a playful cartoon identity. The default character is an original mannequin-like figurine with an oversized head and small limbs. That visual direction gives the game an approachable starting point. Creators should be free to choose their own art direction and develop or replace character models and assets. How much model and asset authoring happens directly in the editor is an open design question.

## Composable objects

Explore a shared object architecture for characters, vehicles, mechanisms, and structures. Creators should be able to configure three kinds of relationships independently.

- **Organizational relationships** let creators select, manipulate, and inspect objects as a group, including nested groups.
- **Physical relationships** describe how objects connect, constrain, support, or otherwise interact with each other.
- **Behavioral relationships** describe how objects share, inherit, or respond to rules and logic.

A creator can group a vehicle for easy placement and give its wheels joints that let them turn. A creator can give an arch resistance to damage and separately decide how it responds to gravity or loss of support. Grouping should never implicitly impose physical connections or shared behavior.

Make reusable components approachable and keep their underlying logic inspectable and editable. A beginner should be able to assemble and try a creature using existing locomotion. An experienced creator should be able to develop and share a new locomotion system. How the shared architecture and its editing tools support these workflows remains open.

## Character engine

Build toward a character engine with reusable, composable capabilities for anatomy, appearance, animation, physical properties, behavior, abilities, input, and movement. The starter mannequin should demonstrate what those capabilities can do. A humanoid, centipede, dragon, spaceship, and 2D sprite should each be able to draw on the capabilities appropriate to their form. Creators should be able to reshape or replace bodies and experiment with how they move in a playable world.

Make character creation an enjoyable sandbox in its own right, including the possibility of building and trying creatures with friends. Creators should be able to share complete characters and individual components that others can inspect, modify, and reuse. A creator could build on a community-made dragon or use its procedural locomotion in another creature where it fits. Characters, animation, movement, mechanical constructions, and logic can each be contributions to the community in their own right.

Treat arbitrary bodies as a long-term design challenge. Give creators tools to assemble, tune, and test how anatomy, animation, physics, and locomotion work together. The initial scope and the ways components declare what they need from a body remain open.

## Shared creative tools

Aim for developer and player parity in content creation. The default mannequin, its movement behavior, materials, and objects should demonstrate the tools available to players. Players should be able to inspect how starter content works, take it apart, modify it, and reuse the pieces in creations of their own.

A working object should be approachable at first and reveal more detail as needed. The tools should let a creator turn a sophisticated creation into a reusable object that someone else can place and adjust quickly, then open up and learn from.
