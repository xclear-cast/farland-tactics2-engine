"""File-format grammar and independently documented operation signatures."""
from .core import *
MAIN_ROWS = [('system', 'N', '43D3F8', 'Dispatch to43F1C0; system selector has its own signature.'), ('wait_ticks', 'N', '43EDFC', 'deadline462160=frame_argument+N; yield.'), ('surface_transition_yield', 'N', '43EE1D', '4180D0(0,10,236,N,N!=0); yield.'), ('surface_transition', 'N', '43D417', '4180D0(global464570,10,236,N,N!=0); continue.'), ('dialogue_top', 'NV?', '43D445', 'speaker4621AC=N; top4621C8=1. N=0 consumes no V; otherwise consumes exactly two raw bytes, variant=byte0-a. Clears top640x240. Portrait-change wait rewinds whole command.'), ('dialogue_bottom', 'NV?', '43D5CB', 'speaker4621AC=N; top4621C8=0. N=0 consumes no V; otherwise consumes exactly two raw bytes. Clears bottom640x240. Portrait-change wait rewinds whole command.'), ('dialogue_text', 'S', '43D746', 'NUL text; DBCS CharNextA span drawing. [Cdigits] calls42F800(-1,value_or30,-1); [Sdigits] calls42F800(value_or16,-1,-1). Other bracket tags consumed. End advances text Y by max glyph height+5.'), ('actor_resource_variant', 'AV', '43DA1B', '419750(actor,variant_char); replace U+6C resource and U+70 sprite. Missing actor skips remaining V consumption.'), ('actor_animation', 'ASN', '43DB13', '42DF50(actor.U70,label,flags,1), flags=1 or17 from N; leading* strips* and adds2. Missing actor skips S,N.'), ('wait_surface_transition', '', '43DBD7', '417F40 nonzero rewinds command by2 and yields.'), ('load_map_number', 'N', '43DBF0', '402E10(N),406BC0(1). Callee linkage separately verified.'), ('load_placement_number', 'N', '43DC1D', '41AA00(N); destroys20 script sprite handles.'), ('camera_center_cell', 'NN', '43DC79', '403540(x,y,&px,&py);4034B0(px,py,0,0).'), ('camera_center_actor', 'A', '43DCD8', 'Project actor.U08/U0C then4034B0(px,py,0,0).'), ('music_select', 'N', '43DD2A', '404100(N);431EE0(0,1).'), ('music_transition', 'NN', '43DD50', '46215C=second;431EE0(first,second).'), ('wave_play', 'S', '43DD80', 'resource15 wave/%s.wav;408FA0(path,0,loop). Leading* removes prefix and loop=1; empty string path=null.'), ('wait_actor_action', 'A', '43DDD8', 'Waits42D680(sprite),42E350(sprite),4124A0(actor),U78; busy rewinds command then yields. Ready restores actor/shadow.'), ('camera_motion', 'NNNNN', '43DE74', '4620C0=arg0,4620C4=arg1; project arg2/3 except(0,0)->(-1,-1);462614=arg4,4625DC=frame_argument.'), ('create_script_sprite', 'SNNN', '43DF1A', 'S->resource9 sprite/%s.apd; shared43DF4C/43EB16..43EBDA creates kind in U00 from firstN, X/Y from followingNs when>0.'), ('create_actor', 'NNN', '43DF4C', 'Temporary124-byte unit U00=firstN,U02=7,U12=1; X/Y from followingNs when>0;41A7F0; shared sprite creation.'), ('remove_actor', 'A', '43DFB8', '41A9E0(actor), only if actor lookup succeeds.'), ('give_party0_item', 'NN', '43DFDD', '4199D0(unit_array_base462930,arg0,arg1).'), ('item_operation', 'NN', '43E017', '419AB0(arg0,arg1); callee contract pending.'), ('wait_dialogue_input', 'N', '43EE78', 'N>0 sets deadline=frame_argument+N;462158=1, window timer400 period600; yields.'), ('actor_path_action', 'ASS', '43E04C', 'S0 action label; S1 chars build direction sequence followed by4;4117C0(actor,sequence,label),4122A0(actor). Missing actor skips both strings.'), ('resolve_actor_only', 'A', '43E186', 'Actor lookup assigned local EBP; no other action before next fetch.'), ('wait_music', '', '43E19A', '432060 nonzero rewinds2/yields; otherwise if46215C==0 resets404100(-1),431EE0(0,1).'), ('actor_set_cell', 'ANN', '43E1CD', 'actor.U08=x,actor.U0C=y;41AE20(). Missing actor skips Ns.'), ('restore_all_and_battle_ready', '', '43E20E', 'For50 units: HPcurrent=HPmax,MPcurrent=trunc0(MPmax/2); falls through35 reset. See semantics notes.'), ('complete_stage_deferred', '', '43E31D', 'Set44C384=1; clear200 bytes event vars; remove units indices10..49 with nonzero kind;44921C=0. At script cleanup flag triggers next event begin (orForcedStage reset branch); this is not only visual cleanup.'), ('actor_face_direction', 'AN', '43E35F', 'IfN!=4 write WORD actor.U06=N;4196F0(actor).'), ('jump_label', 'S', '43EC01', 'Case-insensitive same-file label jump; no call stack.'), ('ensure_actor_resource', 'A', '43DA58', 'Lookup actor; if absent rewind operand and read number into temp U00, U02=7,U12=1 then41A7F0; create resource/sprite.'), ('wait_camera_motion', '', '43EEE7', 'If unsigned462614>0 rewind2; always yield.'), ('scene_clear_visuals', '', '43E3A2', '41AB80; destroy20 script handles; occupied50 units U5C=U60=1;419790.'), ('end_resume_action', '', '43ECBF', 'Free script and objects; restore previous mode; if opcode24 specifically call414CF0(-1).'), ('actor_face_actor', 'AA', '43E40B', 'Second actor direction=41A1E0(second.xy,first.xy);4196F0(second). Invalid lookup stops remaining operand consumption.'), ('actor_sprite_set_screen_xy', 'ANN', '43E473', '42DFC0(actor.U70,arg1,arg2); missing actor skips Ns.'), ('jump_if_equalflag', 'NS', '43E4C3', 'normalized=(unsignedN>=1); if normalized==462624 jump label else consume label and continue.'), ('jump_if_greaterflag', 'NS', '43E4C3', 'normalized=(unsignedN>=1); if normalized==4620B8 jump label else consume label and continue.'), ('var_assign', 'NN', '43E50B', 'event_var[index]=int16(value), base462840,100 WORD capacity.'), ('var_add', 'NN', '43E54C', 'event_var[index]=int16(event_var[index]+value).'), ('var_subtract', 'NN', '43E594', 'event_var[index]=int16(event_var[index]-value).'), ('var_compare', 'NN', '43E5DC', 'arg0=index,arg1=value; equalflag=(value==int16(var[index])); greaterflag=(value>int16(var[index])) signed.'), ('vars_clear', '', '43E649', 'Clear200 bytes at462840.'), ('call_label', 'S', '43EBDF', 'return_PC4621C4=PC+strlen(label)+1 then same-file jump. One slot only, not a return stack.'), ('return_label', '', '43E65C', 'PC=4621C4;4621C4=0.'), ('battle_mode_initialize', '', '43E671', 'Previousmode=1, mode1 temporarily;41AB80,419790,41AC40(1); mode4 resumes script.'), ('shop_inventory_dialog', 'L', '43EF00', 'DialogBoxParam(resource150,4410D0,0); WM_INITDIALOG44143F..441461 reads encoded itemIDs until first signedN<=0 (terminator consumed), appends positive IDs to shop list; yield.'), ('show_centered_bitmap', 'SN', '43E6B9', 'resource7 bmp/%s.bmp loaded417B60 and centered(640-W)/2,(480-H)/2; N passed4180D0 transition. Not a map opcode.'), ('restore_bitmap_scene', '', '43E7D5', 'Palette/scene restore;41AC10(1),4186F0(global44A288/4499D0),462610=0.'), ('start_visual_sequence', 'N', '43EF24', '427060(N);462610=1;game mode8; returns1.'), ('battle_reset', '', '43E239', 'Occupied50 units: dead/status1 HP=1,state0; preserve state9 else0; U60/U5C/U64 DWORD=0; U4C..54 WORD=0. Center first non-state9 unit;41E530(30).'), ('exit_to_mode9', '', '43EF7D', 'Free script;mode9;clear transient state;402E10(-1),442370(1),44921C=-1;returns0.'), ('var_bit_set', 'NN', '43E81A', 'WORD var[index] |= low16(1<<(bit&31)).'), ('var_bit_clear', 'NN', '43E86B', 'WORD var[index] &= low16(~(1<<(bit&31))).'), ('var_bit_toggle', 'NN', '43E8BF', 'WORD var[index] ^= low16(1<<(bit&31)).'), ('var_bit_test', 'NN', '43E910', 'equalflag = (uint32(signextendedWORD(var[index])) & (1<<(bit&31))) !=0.'), ('set_text_global462810', 'SN', '43E977', 'Copy S->462810; ifN!=0 call4420B0().'), ('chain_event', 'NS', '43E9E6', 'Copy label before freeing file;43CFB0(event_number,label); continues fetch in new file.'), ('set_custom_speaker_name', 'S', '43EA32', 'Copy S->462168; dialogue speaker14 uses it.'), ('message_formatted', 'S', '43EA5B', 'Copy S->4627E0;430750(0,S). Formatting directives remain raw.'), ('wait_actor_animation', 'A', '43EA92', 'Wait42D680/42E350/4124A0; restore4196F0 and shadow. Unlike11 does not poll actor.U78.')]
assert len(MAIN_ROWS) == 64
MAIN_ROWS[2] = ('palette_restore_yield', 'N', '43EE1D', '4180D0(NULL,10,236,N,N!=0): restorebasepalette; N ismsper1/128progressstep,notfullfade duration; yield.')
MAIN_ROWS[3] = ('palette_black', 'N', '43D417', '4180D0(blackBGRpalette464570,10,236,N,N!=0); continue. N ismsper1/128progressstep.')
MAIN_ROWS[9] = ('wait_palette_fade', '', '43DBD7', '417F40 returnsprogressWORD44A278!=128;busy rewindscommand2bytes/yields.')
MAIN_ROWS[59] = ('set_stage_title', 'SN', '43E977', 'CopyS->462810 (SAVEheader+06 title). IfN!=0 showtitle4420B0().')
MAIN_ROWS[62] = ('set_battle_objective_text', 'S', '43EA5B', 'CopyS->4627E0 (SAVEheader+1B4 missioncaption) andshow430750(0,S). Textisdisplayonly;actualvictorypredicatesareC/EVENThooks.')
SYS_SIG = ['', 'AN', 'AN', 'NN', 'A', 'N', 'N', 'S', 'NN', 'N', 'A', '', 'AN', 'AN', 'AN', 'A', 'A', 'N', '', '', '', 'N', 'N', 'N', 'N', 'AS', '', 'N', 'NN', 'N', 'A', '', 'AN', 'N', '', 'A', 'AN', 'N', '', '', '', '', 'A', 'N', 'N', 'A', 'A', 'A', 'N', '', 'N', 'N', '', '', '', '', '']
assert len(SYS_SIG) == 57
SYS_NAMES = ['remove_spawn_class1', 'actor_shadow_visible', 'actor_action_markers', 'system442360', 'show_only_actor', 'event_number_from_var', 'palette_transition', 'choice_string', 'reward_dialog', 'system442300', 'actor_overlay', 'remove_dead_nonparty', 'actor_effect8', 'actor_effect0', 'actor_visible', 'party_face_actor', 'actor_dead_kind8', 'all_actor_visible', 'system_message_and_clear', 'scene_reset_event0', 'screen_clear', 'transition_surface464170', 'set_global44923C', 'screen_fill16', 'palette_warm', 'actor_path_string', 'clock_start', 'clock_wait_seconds', 'palette_range_transition', 'screen_fill64', 'actor_sprite_raise32', 'map_flag_query', 'actor_sprite_mode', 'system442350', 'party01_status_query', 'actor_state8', 'give_actor_item', 'palette_transition0', 'hide_shadows', 'restore_all_halfmp', 'context_morph_target', 'context_definition64', 'actor_kill', 'party_money_change', 'palette_cool', 'context_target_equals', 'actor_alive_query', 'actor_heal', 'palette_tint', 'palette_tint_range', 'system41E530', 'money_to_var', 'palette_whiten_and_fades', 'palette_whiten_and_fades2', 'system42F730', 'actor_flag128_set', 'actor_flag128_clear']
SYS_NAMES[0] = 'remove_units_rawU12_1'
SYS_NAMES[30] = 'actor_sprite_first_coordinate_minus32'
SYS_NAMES[55] = 'actor_sprite_flags128'
SYS_NAMES[56] = 'actor_sprite_flags1'
SYS_NAMES[3] = 'set_control_flag442360'
SYS_NAMES[9] = 'control_mode442300'
SYS_NAMES[33] = 'set_global44C72C'
SYS_NAMES[50] = 'save_slot'
SYS_NAMES[51] = 'control_mode_to_var'

def primitive(b, p, k):
    if k in 'NA':
        v, p = read_number(b, p)
        v['kind'] = 'actor_reference' if k == 'A' else 'encoded_integer'
    elif k == 'S':
        v, p = cstring(b, p)
        v['kind'] = 'nul_string'
    elif k == 'V':
        v = {'kind': 'raw_variant_pair', 'offset': p, 'raw_hex': b[p:p + 2].hex(), 'variant_byte': b[p], 'ignored_byte': b[p + 1]}
        p += 2
    else:
        raise ValueError(k)
    return (v, p)

def decode_command(b, p):
    start = p
    if b[p] != 255:
        return ({'offset': p, 'end_offset': p + 1, 'opcode': None, 'opcode_hex': None, 'name': 'non_command_restore_previous_mode', 'operands': [], 'raw_hex': b[p:p + 1].hex(), 'semantic_status': 'C_verified', 'operation': '43D3C0..43D3D7 consumes nonFF byte and43ECA6 restores prior game mode/returns0 without file cleanup. Linear archival node; reachability must not be assumed.'}, p + 1)
    op = b[p + 1]
    p += 2
    if op > 63:
        return ({'offset': start, 'end_offset': p, 'opcode': op, 'opcode_hex': f'{op:02x}', 'name': 'end_cleanup_default', 'operands': [], 'raw_hex': b[start:p].hex(), 'semantic_status': 'C_verified'}, p)
    name, sig, va, note = MAIN_ROWS[op]
    args = []
    if op == 0:
        v, p = primitive(b, p, 'N')
        args.append(v)
        sid = v['value']
        sig = SYS_SIG[sid - 1] if 1 <= sid <= 57 else ''
    for k in sig:
        if k == '?':
            continue
        if k == 'V' and op in (4, 5) and (args[0]['value'] == 0):
            continue
        if k == 'L':
            values = []
            while True:
                v, p = primitive(b, p, 'N')
                values.append(v)
                if v['value'] <= 0:
                    break
            args.append({'kind': 'positive_integer_list_with_nonpositive_terminator', 'values': values, 'offset': values[0]['offset']})
            continue
        v, p = primitive(b, p, k)
        args.append(v)
        guarded = op in (7, 8, 13, 17, 21, 25, 28, 31, 37, 38, 63) or (op == 0 and 1 <= sid <= 57 and ('A' in sig))
        if k == 'A' and v['value'] == 0 and guarded:
            break
    item = {'offset': start, 'end_offset': p, 'opcode': op, 'opcode_hex': f'{op:02x}', 'name': name, 'handler_va': '0x' + va, 'operands': args, 'raw_hex': b[start:p].hex(), 'signature_status': 'C_verified_valid_actor_path', 'semantic_status': 'C_operation_verified; callee details may remain', 'operation': note}
    guarded = op in (7, 8, 13, 17, 21, 25, 28, 31, 37, 38, 63) or (op == 0 and 1 <= sid <= 57 and ('A' in sig))
    if guarded:
        item['runtime_actor_guards'] = [{'operand_index': i, 'on_null': 'resume fetch immediately, do not consume remaining operands', 'failure_next_pc_offset': x['offset'] + len(bytes.fromhex(x['raw_hex']))} for i, x in enumerate(args) if x['kind'] == 'actor_reference']
    if op == 0:
        item['system_id'] = sid
        item['system_name'] = SYS_NAMES[sid - 1] if 1 <= sid <= 57 else 'default_no_action'
    return (item, p)
