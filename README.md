# Structure

- API backend related code is located at `/api`.
- Godot client related code is located at `/godot`
- Data analysis and API testing related code and data is located at `/api/tests`
- Final versions of the videogame are located at `/build`

# How to run

The API must be started **before** the game for correct working.

To run the API:

```bash
cd ./api
# Activate environment
conda activate venv
# Install dependencies
conda install --yes --file requirements.txt
# Run API
python ./src/main.py
```

To run the game:

```bash
cd build
# For voice-only version
./debug_logos_voice.exe
# For WASD controls version
./debug_logos_wasd.exe
```

# Game controls

## Voice actions

- Move
- Left/Right
- Shoot
- Crouch
- Jump
- Stand up
- Scan
- Interact
- **Spacebar**: Activates listening! Must be pressed in keyboard.

## WASD controls

- W: Jump
- A: Left
- D: Right
- S: Crouch
- Ctrl: Crouch
- Left Mouse Button: Shoot
- Q: Scan
- E: Interact
