# Creation game

This repository records the vision and design discussions for an open-source creation game. The project starts with a viewer for the starter figurine and includes an earlier point-editor prototype. The game is still unnamed.

- [Game vision](VISION.md) records the goals and design principles established so far.
- [Design journal](DESIGN-JOURNAL.md) records discussion topics, illustrative ideas, and decisions still open.

When a discussion reaches an important conclusion, update the relevant section of the vision and add a dated journal entry with the decision and its rationale. Keep examples and unresolved ideas in the journal. When a decision changes, update the vision and record what changed. Use Git history to track revisions.

## Try the figurine

After building, run `dist/linux/workspace.x86_64` on Linux or `dist/windows/workspace.exe` on Windows. Both builds target x86-64 and include the runtime. Use **Front**, **Three-quarter**, and **Side** to inspect the white mannequin in its neutral pose.

Click the head, neck, torso, or any arm or leg segment to adjust it. The controls appear to the right of the silhouette. Selecting a limb segment highlights its counterpart and applies each adjustment to both sides. **Size** scales all dimensions together, **Length** adjusts joint spacing, and **Thickness** adjusts width. **Height offset** raises or lowers a limb at its attachment while keeping the joints connected. For the head, neck, and torso, **Height** changes the vertical dimension. The head stays attached as the neck or torso changes. Drag a slider or type an exact percentage.

**Save proportions** writes all eleven parts to `user://mannequin-proportions.json` and replaces the previous local preset. The viewer loads it automatically, including after a full restart and accepts earlier limb-only and torso presets. Previously saved side-to-side differences are kept until you adjust those controls. The preset lives outside the repository.

## Try movement

Choose **Try movement** in the figurine viewer. Move with **A/D**, **←/→**, or a controller's **left stick**. Tap or hold **Space** or the controller's **bottom face button** to jump. The keyboard uses full movement speed. The stick blends between the minimum walking speed just beyond its dead zone and the maximum at full tilt.

Adjust **Min walk speed**, **Max walk speed**, **Tap jump strength**, **Hold jump strength**, **Forward lean**, **Gravity strength**, and **Air inertia** with the sliders, by typing values, or with the number fields’ arrows. Higher gravity pulls downward faster. Higher air inertia carries more momentum and slows midair turns. At 100%, releasing movement preserves horizontal momentum in the air and steering still responds. **Save movement** writes the current settings to `user://mannequin-movement.json` and reloads them on the next preview, including after restarting the game. The preview has four boxes of increasing height for testing takeoff and landing. Tilt a supported controller to move the head, and use **Center head** to set your current grip as neutral. **Back to proportions** returns to the proportions you were viewing, including unsaved changes.

The orange physics cube starts to the left. Walk into it to nudge it, or hold **R1** on the controller or **E** on the keyboard while nearby to grab it. Move toward it to push or back away to pull. The figurine faces the cube while holding it, and the cube's mass slows movement. Release the button to let go. You can jump while holding the cube or grab a reachable side during a jump. The held face lifts first, the cube can tip and tumble in the side-scrolling plane, and its mass reduces your jump. A low step farther left gives you a place to try hauling it up from the far side. **Reset positions** puts the figure and cube back at their starting positions.

The viewer starts from the project preset in `game/default_proportions.json`. A local saved preset takes precedence. Movement uses the displayed proportions and blends the limbs according to horizontal speed and whether the character is on the ground.

## Try the point editor

Choose **Point editor** in the viewer to open the earlier construction prototype.

1. In **Place & move**, click empty space to add points and drag existing points to reshape the figure.
2. In **Connect**, click two points to join them. Repeat for each link.
3. In **Swing link**, click a pivot, then drag a connected point to swing it while keeping that link's length. Right-click to pick a different pivot. This is a posing tool.
4. In **Place & move**, drag a selected point's arrow to grow a straight link or drag the ring to grow in any direction. Release to place and connect the new point. The handles follow it so you can keep building. Escape cancels the current pull.
5. Hover over any handle for a short explanation. Click the **mirror handle** (two arrows pointing away from a line) beside a selected point, then drag an arrow or the ring. The next pull mirrors across a vertical line through that point. Pull sideways to see both previews.
6. Use **Save** to write a `.figure.json` file and **Open** to continue working on it.

## Build and test

Install Godot **4.7.2 stable** and its matching export templates. Run `GODOT_BIN=/path/to/godot ./scripts/build.sh` from Linux. The script imports the project, runs the headless figure, workspace, mannequin, movement, and grab tests, and exports both builds to `dist/`.

`game/figure.gd` owns the saved points and connections. `game/workspace.gd` handles the in-game tools and draws the figure in a 3D viewport. The first workspace uses an orthographic camera, constrains new points to a plane, and uses Godot's Compatibility renderer. The saved format includes depth so the planar input tool need not define the format for later tools.

Godot is distributed under the MIT license. Engine attribution and third-party notices accompany the exports. [Godot license information](https://godotengine.org/license/)

## Contributing

Use GitHub issues for bugs and focused design proposals. For changes, include what you tried, what changed, and how someone else can verify it. Run the build and checks before merging source changes. Update the vision and design journal when a decision changes, and push the relevant documentation and code to GitHub together.

Project code and documentation are available under the [MIT License](LICENSE). Third-party license and attribution files are in [notices](notices/).
