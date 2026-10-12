"""Affected game-shell/launch gate with a private, restored settings directory."""
from pathlib import Path
import build


def main():
    config = build.ROOT / 'game/project.godot'
    original = config.read_bytes()
    isolated = original.decode('utf-8').replace(
        '[application]', '[application]\nconfig/use_custom_user_dir=true\n'
        'config/custom_user_dir_name="blockfield-game-ui-check"', 1)
    config.write_text(isolated, encoding='utf-8')
    try:
        build.run('ui-final-import', ['--editor', '--import', '--quit'], timeout=300)
        suites = [
            ('game-shell', 'tests/ui/test_game_shell.gd'),
            ('game-launch', 'tests/integration/test_game_launch.gd'),
            ('ui', 'tests/ui/test_ui.gd'),
            ('combat-hud', 'tests/ui/test_combat_hud.gd'),
            ('mobile-controls', 'tests/ui/test_mobile_controls.gd'),
            ('mobile-look', 'tests/integration/test_mobile_look.gd'),
            ('source-input', 'tests/integration/test_source_input.gd'),
            ('lab', 'tests/integration/test_lab.gd'),
            ('offline-tdm', 'tests/session/test_offline_tdm.gd'),
            ('offline-tdm-scene', 'tests/integration/test_offline_tdm_scene.gd'),
            ('native-map-main', 'tests/integration/test_native_map_main.gd'),
            ('vxl-main', 'tests/integration/test_vxl_main.gd'),
        ]
        for name, path in suites:
            build.run('ui-gate-' + name, ['--fixed-fps', '60', '--script', str(build.ROOT / path)], timeout=300)
        build.run('ui-shell-smoke', ['--quit-after', '120'])
    finally:
        config.write_bytes(original)


if __name__ == '__main__':
    main()
