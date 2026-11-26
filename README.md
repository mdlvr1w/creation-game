# Creation game

This repository records the vision and design discussions for an open-source creation game. The project is in its first playable prototype. The game is still unnamed.

- [Game vision](VISION.md) records the goals and design principles established so far.
- [Design journal](DESIGN-JOURNAL.md) records discussion topics, illustrative ideas, and decisions still open.

When a discussion reaches an important conclusion, update the relevant section of the vision and add a dated journal entry with the decision and its rationale. Keep examples and unresolved ideas in the journal. When a decision changes, update the vision and record what changed. Use Git history to track revisions.

## Try the first prototype

After building, run `dist/linux/workspace.x86_64` on Linux or `dist/windows/workspace.exe` on Windows. Both builds target x86-64 and include the runtime.

1. In **Place & move**, click empty space to add points and drag existing points to reshape the figure.
2. In **Connect**, click two points to join them. Repeat for each link.
3. In **Swing link**, click a pivot, then drag a connected point to swing it while keeping that link's length. Right-click to pick a different pivot. This is a posing tool.
4. In **Place & move**, drag a selected point's arrow to grow a straight link or drag the ring to grow in any direction. Release to place and connect the new point. The handles follow it so you can keep building. Escape cancels the current pull.
5. Enable **Mirror extrusion** to preview and place matching links across the vertical centerline. Start on the line or at a point with a matching opposite point. While enabled, placing a point close to the line snaps it onto the line.
6. Use **Save** to write a `.figure.json` file and **Open** to continue working on it.

## Build and test

Install Godot **4.5.1 stable** and its matching export templates. Run `GODOT_BIN=/path/to/godot ./scripts/build.sh` from Linux. The script imports the project, runs the headless figure and workspace tests, and exports both builds to `dist/`.

`game/figure.gd` owns the saved points and connections. `game/workspace.gd` handles the in-game tools and draws the figure in a 3D viewport. The first workspace uses an orthographic camera, constrains new points to a plane, and uses Godot's Compatibility renderer. The saved format includes depth so the planar input tool need not define the format for later tools.

Godot is distributed under the MIT license. Engine attribution and third-party notices accompany the exports. [Godot license information](https://godotengine.org/license/)

## Contributing

Use GitHub issues for bugs and focused design proposals. For changes, include what you tried, what changed, and how someone else can verify it. Run the build and checks before merging source changes. Update the vision and design journal when a decision changes, and push the relevant documentation and code to GitHub together.

Project code and documentation are available under the [MIT License](LICENSE). Third-party license and attribution files are in [notices](notices/).
