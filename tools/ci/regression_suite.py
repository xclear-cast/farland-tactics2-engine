"""Platform-neutral synthetic runtime regression runner; never requires game data."""
from pathlib import Path
import argparse
import json
import os
import subprocess

ROOT=Path(__file__).resolve().parents[2]

REGRESSION_TESTS=(
    ('portrait_palette','palette'),
    ('actor_job_direction','direction'),
    ('actor_sprite_reset','sprite'),
    ('story_palette_snapshot','story-palette'),
    ('story_shadow','shadow'),
    ('cinematic_layer_keys','layer-keys'),
    ('story_unit_visibility','unit-visibility'),
    ('script_sprite_palette','script-palette'),
    ('save_tail_header','save-tail'),
    ('cinematic_reset_lifetime','scene-reset'),
    ('story_palette_wait','palette-wait'),
    ('scene_dispatch','scene-dispatch'),
    ('story_cleanup','cleanup'),
    ('system_palette_acquisition','system-palette'),
    ('story_shadow_handles','shadow-handles'),
    ('story_appearance_refresh','appearance'),
    ('actor_palette_acquisition','actor-palette'),
    ('script_whiten_palette','whiten'),
    ('cache_rebuild_mode','cache-rebuild'),
    ('exp_palette_scope','exp-palette'),
    ('selection_camera','selection-camera'),
    ('actor_job_start_failure','job-start'),
    ('placement_appearance','placement'),
    ('action_camera_and_mask','action-camera'),
    ('actor_job_wait','job-wait'),
    ('source_game_mode','game-mode'),
    ('next_party_presentation','next-party'),
    ('enemy_battle_hook_return','enemy-hook-return'),
)


def default_runner(output,records=None,timeout=90):
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    def run(name,command):
        result=subprocess.run([str(x)for x in command],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout,
                              env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1'))
        text=result.stdout+result.stderr
        (output/(name+'.log')).write_text(text,encoding='utf-8')
        diagnostics=[line for line in text.splitlines()if line.startswith(('ERROR:','SCRIPT ERROR:'))]
        if result.returncode!=0 or diagnostics:raise RuntimeError(f'{name} failed:\n{text[-7000:]}')
        if records is not None:records.append({'test':name,'exit_code':result.returncode,'passed':True})
        return text
    return run


def run_regression_suite(launcher,output,run=None,extra_args=()):
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    prefix=[launcher]if isinstance(launcher,(str,Path))else list(launcher)
    runner=run if run is not None else default_runner(output)
    results=[]
    for name,argument in REGRESSION_TESTS:
        regression_output=output/name;regression_output.mkdir(parents=True,exist_ok=True)
        runner(name,[*prefix,'--headless','--audio-driver','Dummy',*extra_args,'--script',ROOT/f'game/tests/test_{name}.gd','--',f'--{argument}-output={regression_output}'])
        regression_report=json.loads((regression_output/'result.json').read_text(encoding='utf-8'))
        if not regression_report.get('passed'):raise RuntimeError(name+' synthetic runtime regression did not pass')
        results.append({'test':name,'checks':regression_report.get('checks',0),'passed':True})
    return results


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',type=Path,required=True,help='Godot console/headless executable')
    parser.add_argument('--output',type=Path,default=ROOT/'private/regression-suite')
    parser.add_argument('--include-project-path',action='store_true',default=True)
    args=parser.parse_args()
    godot=args.godot.resolve();output=args.output.resolve()
    if not godot.is_file():raise FileNotFoundError(godot)
    launcher=[godot,'--path',ROOT/'game']if args.include_project_path else [godot]
    records=[]
    results=run_regression_suite(launcher,output,default_runner(output,records))
    summary={'passed':True,'suite_count':len(results),'total_checks':sum(int(r['checks'])for r in results),'results':results}
    (output/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps({'passed':True,'suite_count':len(results),'total_checks':summary['total_checks']}))


if __name__=='__main__':main()
