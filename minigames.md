# Mini Game: Integrate Mini-Game into Rakan Student Dashboard

## Context
You are tasked with building a complete, highly polished 2D lane-based racing mini-game using native Flutter widgets, and integrating it seamlessly into the existing `home_screen.dart` dashboard. The aesthetic should be modern, sleek, and match a dark-mode "Sim Racing" vibe.

## Phase 1: Dashboard Integration (`home_screen.dart`)
1. **The Game Bar UI:** Below the "Quick Overview" boxes, add a new, premium-looking UI Card called the "Focus Reward: Sprint Challenge".
2. **Styling:** The card should have a dark gradient background (e.g., deep charcoal to black) with an amber/neon accent border.
3. **Action:** Include a "Tap to Race" button or make the whole card clickable.
4. **Navigation:** When tapped, use `Navigator.push` with a smooth `PageRouteBuilder` (fade transition) to navigate to `sprint_game_screen.dart`.
5. **Callback:** Await the result from the `Navigator.push`. If it returns an integer (the score), show a `ScaffoldMessenger` SnackBar saying "Race Complete: Earned [X] Focus XP!".

## Phase 2: The Game Screen (`sprint_game_screen.dart`)
Create a new file containing a `StatefulWidget`. This must be a production-ready, 60fps-targeted mini-game.

### A. Game State & Logic
1. **The Track:** A 3-lane system represented by integers: Left (-1), Center (0), Right (1).
2. **Player Movement:** - Player starts at Lane 0, Y-alignment 0.8 (bottom of screen).
   - Use `GestureDetector` covering the whole screen. Tapping the left half (`details.globalPosition.dx < screenWidth / 2`) moves the player left. Tapping the right half moves them right.
3. **Enemy Spawning:** - Enemies spawn at Y-alignment -1.2 (off-screen top).
   - Pick a random lane (-1, 0, 1).
4. **The Game Loop:**
   - Use `Timer.periodic` set to ~16ms (for ~60fps smooth movement).
   - Enemy moves down the Y-axis by `gameSpeed`.
   - When Enemy Y > 1.2, increment `score`, reset Enemy Y to -1.2, pick a new random lane, and increase `gameSpeed` slightly to ramp up difficulty.
5. **Collision Detection:**
   - If the Enemy Lane == Player Lane AND Enemy Y is between 0.65 and 0.85 (tweakable hitbox), the player crashes.
   - Cancel the Timer immediately.

### B. Visual Polish & "Super Nice" UI
1. **Background:** A scrolling asphalt effect or a sleek `Colors.grey[900]` with glowing lane dividers (`Colors.white24`).
2. **Player Car:** Do not use basic boxes. Use `Icon(Icons.bolt, color: Colors.amberAccent, size: 50)` wrapped in an `AnimatedContainer` (duration ~150ms, curve easeOut) so lane switching looks like a realistic, smooth swerve.
3. **Traffic (Enemies):** Use `Icon(Icons.directions_car, color: Colors.redAccent, size: 50)`.
4. **HUD:** A clean, modern score display at the top of the screen (SafeArea) with a custom monospace or bold font.

### C. Lifecycle Safety (CRITICAL - DO NOT FAIL)
1. **Mounted Checks:** Inside the `Timer.periodic`, the VERY FIRST line must be `if (!mounted) { timer.cancel(); return; }`. ALL `setState` calls must be protected.
2. **Dispose:** Override `dispose()` to cancel the timer before `super.dispose()`.
3. **Game Over Dialog:** When crashed, show a custom blurred modal (using `BackdropFilter`) with the final score. Provide two buttons:
   - "RACE AGAIN": Resets state and restarts the timer.
   - "EXIT TO PITLANE": Calls `Navigator.pop(context, score)` to return the score to the dashboard.

## Required Output
1. The exact code snippet to inject into `home_screen.dart` for the Game Bar.
2. The FULL, COMPLETE, UNTRUNCATED code for `sprint_game_screen.dart`.
Do not leave comments like "// implement logic here". Write the actual code.