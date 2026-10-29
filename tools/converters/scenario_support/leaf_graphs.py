"""Rebuild cinematic controller graphs from a user's original executable.

Requires the Unicorn Python package, including its native Apple Silicon library
when run on an M1-or-later Mac. No Windows process or guest operating system runs.
"""
from pathlib import Path
from .core import digest,write_json,case_path

# Entry points are the supported executable's compatibility ABI. Scene commands,
# strings, imagery and machine-code bytes are never stored in this module.
OPENING=(0x420c70,0x420f50,0x421200,0x421470,0x421640,0x421bb0,
         0x421d60,0x421fc0,0x422110,0x422370,0x4224e0,0x422860,
         0x422ac0,0x422c80,0x422ef0,0x4230c0,0x423570,0x423760)
INTERLUDES=(0x424030,0x4241e0,0x424740,0x424a30,0x424bc0,0x424e10,
            0x4250c0,0x425290,0x425410,0x4255d0,0x4257f0,0x425b50)
ENDING=(0x4262a0,0x426410,0x426680,0x4267e0,0x426c60,0x426ed0)


def convert_leaf_graphs(source: Path,output: Path) -> dict:
    try:
        from .leaf_sandbox import GraphOracle,QUERY,UC_X86_REG_FPCW,UC_X86_REG_EIP,i32
    except ImportError as error:
        raise RuntimeError('Cinematic conversion requires unicorn>=2.1,<3 for this Python/CPU architecture')from error
    source,output=Path(source).resolve(),Path(output).resolve()
    if output.is_relative_to(source):raise ValueError('Output must be outside the original installation')
    exe=case_path(source,'FTO_O.EXE');before=digest(exe.read_bytes())
    oracle=GraphOracle(source);oracle.uc.reg_write(UC_X86_REG_FPCW,0x27f)
    target=output/'data/port_ready/scripts/cinematics/contracts'
    entries=[(0,phase,address)for phase,address in enumerate(OPENING)]
    entries += [(profile+1,0,address)for profile,address in enumerate(INTERLUDES)]
    entries += [(13,phase,address)for phase,address in enumerate(ENDING)]
    graphs=[];errors=[]
    for profile,phase,entry in entries:
        todo=[(0,0)];seen=set();edges=[];attempts=0
        while todo and len(seen)<128:
            state,aux=todo.pop(0)
            if(state,aux)in seen:continue
            seen.add((state,aux));decisions=[[]];paths=set()
            while decisions:
                attempts+=1
                if attempts>8192:raise RuntimeError('Symbolic path limit exceeded')
                choices=decisions.pop();oracle.path_cursor=0;oracle.commands=[];oracle.predicates=[];oracle.choices=choices
                oracle.write32(0x44aee8,profile);oracle.write32(0x44aef0,phase);oracle.write32(0x44aef4,state)
                oracle.write32(0x44aef8,0);oracle.write32(0x44b098,aux);oracle.write32(0x44af04,1000);oracle.write32(0x44af18,0)
                oracle.writes=[];oracle.events=[]
                try:ret=oracle.call(entry)
                except Exception as error:
                    errors.append({'profile':profile,'phase':phase,'state':state,'aux':aux,'entry':hex(entry),'error':str(error),
                                   'eip':hex(oracle.uc.reg_read(UC_X86_REG_EIP)),'predicates':oracle.predicates,'commands':oracle.commands.copy()})
                    continue
                used=tuple(predicate['value']for predicate in oracle.predicates)
                if used in paths:continue
                paths.add(used)
                for index,value in enumerate(used):
                    prefix=list(used[:index])+[1-value]
                    if tuple(prefix)not in paths and prefix not in decisions:decisions.append(prefix)
                after=(i32(oracle.read32(0x44aef4)),i32(oracle.read32(0x44b098)))
                commands=[command for command in oracle.commands if command['API']not in[hex(query)for query in QUERY]]
                edges.append({'input_local_state':state,'input_aux44B098':aux,'ordered_operations':oracle.events.copy(),
                              'guard_in_call_order':oracle.predicates.copy(),'ordered_commands':commands,'scalar_writes':oracle.writes.copy(),
                              'return':ret,'next_local_state':after[0],'next_aux44B098':after[1]})
                if ret and after not in seen and after not in todo:todo.append(after)
        if todo:raise RuntimeError(f'State limit exceeded in profile {profile}/{phase}')
        name=f'profile{profile:02d}_phase{phase:02d}.json'
        document={'source_sha256':before,'profile':profile,'phase':phase,'controller':hex(entry),
                  'status':'guarded_engine_predicate_transducer;notwholebackendvisualreplay',
                  'initial_state':{'44AEF4':0,'44B098':0},'reached_states':[{'local':state,'aux':aux}for state,aux in sorted(seen)],
                  'edge_count':len(edges),'edges':edges,'unexplored_state_queue':todo,
                  'preconditions':['Engine service side effects are abstracted; busy predicates are explored symbolically.',
                                   'Local elapsed scalar is zero; typed timeout predicates are explored independently.',
                                   'State BFS starts at zero; this is not a full native-renderer replay.'],
                  'original_exe_unchanged':digest(exe.read_bytes())==before}
        write_json(target/'leaf_graphs'/name,document)
        graphs.append({'file':name,'profile':profile,'phase':phase,'controller':hex(entry),'states':len(seen),'edges':len(edges),
                       'untyped_commands':sum(not command['typed']for edge in edges for command in edge['ordered_commands']),'unexplored_count':len(todo)})
    report={'source_sha256':before,'controller_count':len(graphs),'state_count':sum(row['states']for row in graphs),
            'edge_count':sum(row['edges']for row in graphs),'graphs':graphs,'errors':errors,
            'original_exe_unchanged':digest(exe.read_bytes())==before,
            'execution':'Bounded x86 emulation in private Unicorn memory; no OS process or guest I/O'}
    write_json(target/'leaf_graph_inventory.json',report)
    if errors:raise RuntimeError('Cinematic conversion failed: '+str(errors[:2]))
    if not report['original_exe_unchanged']:raise RuntimeError('Original executable changed during conversion')
    return report
