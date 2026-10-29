/* Optional, explicitly identified GM soundfont output adapter.
 * Game MIDI parsing/timing stays in GDScript. This is not a Win95 FM/MPU emulator.
 * Godot interface and TinySoundFont licenses accompany the unmodified headers.
 * A separate one-shot startup adapter reads only the fixed Shift/Ctrl modifiers.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#ifdef _WIN32
/* Avoid windows.h's SHORT typedef colliding with the existing MIDI method ID.
 * This is the Win32 GetAsyncKeyState signature; x64 uses the platform ABI. */
__declspec(dllimport) short __stdcall GetAsyncKeyState(int virtual_key);
#elif defined(__linux__)
#include <dlfcn.h>
#elif defined(__APPLE__)
#include <CoreGraphics/CoreGraphics.h>
#endif
#include "include/gdextension_interface.h"
#define TSF_NO_STDIO
#define TSF_IMPLEMENTATION
#include "include/tsf.h"

#ifdef _WIN32
#define FT2_EXPORT __declspec(dllexport)
#else
#define FT2_EXPORT __attribute__((visibility("default")))
#endif

typedef union { long double align; unsigned char data[64]; } Opaque;
typedef struct { GDExtensionObjectPtr owner; tsf *bank; int rate; float gain; int modifiers_sampled, modifiers_mask; } Synth;
static GDExtensionClassLibraryPtr library;
static Opaque class_name, base_name, empty_name, empty_string, size_name, resize_name;
static GDExtensionInterfaceStringNameNewWithLatin1Chars sn_new;
static GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
static GDExtensionInterfaceVariantGetPtrConstructor get_constructor;
static GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
static GDExtensionInterfaceGetVariantToTypeConstructor to_type;
static GDExtensionInterfaceVariantNewNil new_nil;
static GDExtensionInterfaceVariantDestroy destroy_variant;
static GDExtensionInterfaceVariantCall variant_call;
static GDExtensionInterfaceClassdbRegisterExtensionClass2 register_class;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbConstructObject construct_object;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst bytes_at;
static GDExtensionInterfacePackedVector2ArrayOperatorIndex vectors_at;

static int64_t as_int(GDExtensionConstVariantPtr value) {
    int64_t out=0; to_type(GDEXTENSION_VARIANT_TYPE_INT)(&out,(GDExtensionVariantPtr)value); return out;
}
static double as_float(GDExtensionConstVariantPtr value) {
    double out=0; to_type(GDEXTENSION_VARIANT_TYPE_FLOAT)(&out,(GDExtensionVariantPtr)value); return out;
}
static void result_bool(GDExtensionVariantPtr result, int yes) {
    GDExtensionBool value=(GDExtensionBool)(yes!=0); destroy_variant(result); from_type(GDEXTENSION_VARIANT_TYPE_BOOL)(result,&value);
}
static void result_int(GDExtensionVariantPtr result, int64_t value) {
    destroy_variant(result); from_type(GDEXTENSION_VARIANT_TYPE_INT)(result,&value);
}
static int sample_startup_modifiers(void) {
#ifdef _WIN32
    return ((GetAsyncKeyState(0x10)&0x8000)?1:0) |
           ((GetAsyncKeyState(0x11)&0x8000)?2:0);
#elif defined(__APPLE__)
    /* One bounded modifier query; no event tap or global input monitoring. */
    CGEventFlags flags=CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
    return ((flags&kCGEventFlagMaskShift)?1:0) | ((flags&kCGEventFlagMaskControl)?2:0);
#elif defined(__linux__)
    /* No connection or library load for missing DISPLAY. Main also skips this
     * method under headless. X11 is lazy so the synth has no hard X11 dependency. */
    const char *display_name=getenv("DISPLAY");
    if(!display_name || !*display_name)return -1;
    void *module=dlopen("libX11.so.6",RTLD_NOW|RTLD_LOCAL);
    if(!module)return -1;
    typedef void *(*OpenDisplay)(const char *);
    typedef unsigned long (*StringToKeysym)(const char *);
    typedef unsigned char (*KeysymToKeycode)(void *,unsigned long);
    typedef int (*QueryKeymap)(void *,char *);
    typedef int (*CloseDisplay)(void *);
    OpenDisplay open_display=(OpenDisplay)dlsym(module,"XOpenDisplay");
    StringToKeysym string_to_keysym=(StringToKeysym)dlsym(module,"XStringToKeysym");
    KeysymToKeycode keysym_to_keycode=(KeysymToKeycode)dlsym(module,"XKeysymToKeycode");
    QueryKeymap query_keymap=(QueryKeymap)dlsym(module,"XQueryKeymap");
    CloseDisplay close_display=(CloseDisplay)dlsym(module,"XCloseDisplay");
    int mask=-1;
    void *display=NULL;
    if(!open_display || !string_to_keysym || !keysym_to_keycode || !query_keymap || !close_display)goto done;
    display=open_display(display_name);
    if(!display)goto done;
    const char *names[4]={"Shift_L","Shift_R","Control_L","Control_R"};
    unsigned char codes[4],state[32]={0};
    for(int i=0;i<4;i++) {
        codes[i]=keysym_to_keycode(display,string_to_keysym(names[i]));
        if(!codes[i])goto done;
    }
    query_keymap(display,(char *)state);
    mask=0;
    for(int i=0;i<4;i++)if(state[codes[i]>>3]&(1u<<(codes[i]&7)))mask|=i<2?1:2;
done:
    if(display)close_display(display);
    dlclose(module);
    return mask;
#else
    return -1;
#endif
}
static int64_t array_size(GDExtensionConstVariantPtr array) {
    Opaque value; GDExtensionCallError error={0};
    variant_call((GDExtensionVariantPtr)array,&size_name,NULL,0,&value,&error);
    int64_t size=error.error==GDEXTENSION_CALL_OK?as_int(&value):0; destroy_variant(&value); return size;
}
static void reset_voices(Synth *s) {
    if(!s->bank)return;
    for(int channel=0;channel<16;channel++) {
        tsf_channel_set_sustain(s->bank,channel,0);
        tsf_channel_sounds_off_all(s->bank,channel);
    }
    /* TinySoundFont's public sounds-off keeps a short anti-click release.
     * A transport reset must instead cut queued voices without changing programs. */
    for(int voice=0;voice<s->bank->voiceNum;voice++)tsf_voice_kill(&s->bank->voices[voice]);
}
static void short_message(Synth *s,uint32_t word) {
    if(!s->bank)return;
    unsigned status=word&255,channel=status&15,a=(word>>8)&127,b=(word>>16)&127;
    switch(status&240) {
        case 0x80:tsf_channel_note_off(s->bank,channel,a);break;
        case 0x90:if(b)tsf_channel_note_on(s->bank,channel,a,b/127.0f);else tsf_channel_note_off(s->bank,channel,a);break;
        case 0xB0:tsf_channel_midi_control(s->bank,channel,a,b);break;
        case 0xC0:tsf_channel_set_presetnumber(s->bank,channel,a,channel==9);break;
        case 0xE0:tsf_channel_set_pitchwheel(s->bank,channel,a|(b<<7));break;
        default:break; /* Poly/channel pressure is not implemented by the named GM adapter. */
    }
}
static int sysex_message(Synth *s,const unsigned char *data,int size) {
    if(!s->bank || size<1)return 0;
    int start=data[0]==0xF0?1:0;
    if(size-start>=4 && data[start]==0x7E && data[start+2]==0x09 && (data[start+3]==1||data[start+3]==3)) {
        reset_voices(s);
        for(int c=0;c<16;c++) {tsf_channel_midi_control(s->bank,c,121,0);tsf_channel_set_presetnumber(s->bank,c,0,c==9);}
        return 1;
    }
    if(size-start>=6 && data[start]==0x7F && data[start+2]==4 && data[start+3]==1) {
        float gain=(data[start+4]|(data[start+5]<<7))/16383.0f;
        tsf_set_volume(s->bank,s->gain*gain);return 1;
    }
    if(size-start>=9 && data[start]==0x41 && data[start+2]==0x42 && data[start+3]==0x12 && data[start+4]==0x40 && data[start+5]==0 && data[start+6]==0x7F) {
        reset_voices(s);
        for(int c=0;c<16;c++){tsf_channel_midi_control(s->bank,c,121,0);tsf_channel_set_presetnumber(s->bank,c,0,c==9);}
        return 1;
    }
    return 0; /* Unrecognized vendor SysEx remains explicit at the adapter boundary. */
}
static void render(Synth *s,int frames,GDExtensionVariantPtr result) {
    if(frames<0)frames=0;if(frames>65536)frames=65536;
    Opaque packed,argument,resize_result,copy;
    get_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY,0)(&packed,NULL);
    destroy_variant(result);from_type(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY)(result,&packed);
    int64_t count=frames;from_type(GDEXTENSION_VARIANT_TYPE_INT)(&argument,&count);
    GDExtensionConstVariantPtr args[]={&argument};GDExtensionCallError error={0};
    variant_call(result,&resize_name,args,1,&resize_result,&error);
    destroy_variant(&resize_result);destroy_variant(&argument);
    to_type(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY)(&copy,result);
    float *pcm=(float*)calloc((size_t)frames*2,sizeof(float));
    if(pcm && s->bank)tsf_render_float(s->bank,pcm,frames,0);
    for(int i=0;i<frames;i++) {
        float *xy=(float*)vectors_at(&copy,i);
        xy[0]=pcm?pcm[2*i]:0.0f;xy[1]=pcm?pcm[2*i+1]:0.0f;
    }
    free(pcm);destroy_variant(result);from_type(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY)(result,&copy);
    get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY)(&copy);
    get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY)(&packed);
}
enum { LOAD=1,SHORT,SYSEX,RESET,GAIN,RENDER,SAMPLE_MODIFIERS };
static void call_method(void *userdata,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr result,GDExtensionCallError *error) {
    Synth *s=(Synth*)instance;intptr_t method=(intptr_t)userdata;error->error=GDEXTENSION_CALL_OK;
    int required=method==LOAD?2:(method==RESET || method==SAMPLE_MODIFIERS)?0:1;
    if(argc!=required){error->error=argc<required?GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS:GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;error->expected=required;return;}
    if(method==SAMPLE_MODIFIERS) {
        /* Cache even unavailable: one bounded query per startup instance,
         * never an audio-transport poll or a keyboard event stream. */
        if(!s->modifiers_sampled){s->modifiers_mask=sample_startup_modifiers();s->modifiers_sampled=1;}
        result_int(result,s->modifiers_mask);
    } else if(method==LOAD) {
        int64_t length=array_size(args[0]);Opaque bytes;to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&bytes,(GDExtensionVariantPtr)args[0]);
        int rate=(int)as_int(args[1]);if(rate<8000||rate>192000)rate=44100;
        tsf *bank=length>=12&&length<=128*1024*1024?tsf_load_memory(bytes_at(&bytes,0),(int)length):NULL;
        get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&bytes);
        if(bank){if(s->bank)tsf_close(s->bank);s->bank=bank;s->rate=rate;tsf_set_output(bank,TSF_STEREO_INTERLEAVED,rate,0);tsf_set_volume(bank,s->gain);for(int c=0;c<16;c++)tsf_channel_set_presetnumber(bank,c,0,c==9);}
        result_bool(result,bank!=NULL);
    } else if(method==SHORT) short_message(s,(uint32_t)as_int(args[0]));
    else if(method==SYSEX) {
        int64_t length=array_size(args[0]);Opaque bytes;to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&bytes,(GDExtensionVariantPtr)args[0]);
        int handled=length>0&&length<65536?sysex_message(s,bytes_at(&bytes,0),(int)length):0;
        get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&bytes);result_bool(result,handled);
    } else if(method==RESET) reset_voices(s);
    else if(method==GAIN){s->gain=(float)as_float(args[0]);if(!isfinite(s->gain)||s->gain<0)s->gain=0;if(s->gain>4)s->gain=4;if(s->bank)tsf_set_volume(s->bank,s->gain);}
    else if(method==RENDER)render(s,(int)as_int(args[0]),result);
}
static GDExtensionObjectPtr create_instance(void *userdata) {
    (void)userdata;Synth *s=(Synth*)calloc(1,sizeof(Synth));if(!s)return NULL;
    s->rate=44100;s->gain=1.0f;s->owner=construct_object(&base_name);set_instance(s->owner,&class_name,s);return s->owner;
}
static void free_instance(void *userdata,GDExtensionClassInstancePtr instance) {
    (void)userdata;Synth *s=(Synth*)instance;if(s){if(s->bank)tsf_close(s->bank);free(s);}
}
static void bind(const char *name,int id,GDExtensionVariantType returns,int argc,GDExtensionVariantType first,GDExtensionVariantType second) {
    Opaque method_name;sn_new(&method_name,name,0);
    GDExtensionPropertyInfo result={0};result.type=returns;result.name=&empty_name;result.class_name=&empty_name;result.hint_string=&empty_string;result.usage=6;
    GDExtensionPropertyInfo arguments[2]={result,result};arguments[0].type=first;arguments[1].type=second;
    GDExtensionClassMethodArgumentMetadata metadata[2]={0,0};
    GDExtensionClassMethodInfo info={0};info.name=&method_name;info.method_userdata=(void*)(intptr_t)id;info.call_func=call_method;
    info.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_VARARG;
    info.has_return_value=returns!=GDEXTENSION_VARIANT_TYPE_NIL;info.return_value_info=&result;info.argument_count=argc;info.arguments_info=arguments;info.arguments_metadata=metadata;
    register_method(library,&class_name,&info);get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&method_name);
}
static void initialize(void *userdata,GDExtensionInitializationLevel level) {
    (void)userdata;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    sn_new(&class_name,"FT2NativeSynth",0);sn_new(&base_name,"RefCounted",0);sn_new(&empty_name,"",0);sn_new(&size_name,"size",0);sn_new(&resize_name,"resize",0);
    get_constructor(GDEXTENSION_VARIANT_TYPE_STRING,0)(&empty_string,NULL);
    GDExtensionClassCreationInfo2 info={0};info.is_exposed=1;info.create_instance_func=create_instance;info.free_instance_func=free_instance;
    register_class(library,&class_name,&base_name,&info);
    bind("load_bank",LOAD,GDEXTENSION_VARIANT_TYPE_BOOL,2,GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,GDEXTENSION_VARIANT_TYPE_INT);
    bind("dispatch_short",SHORT,GDEXTENSION_VARIANT_TYPE_NIL,1,GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_NIL);
    bind("dispatch_sysex",SYSEX,GDEXTENSION_VARIANT_TYPE_BOOL,1,GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,GDEXTENSION_VARIANT_TYPE_NIL);
    bind("reset_voices",RESET,GDEXTENSION_VARIANT_TYPE_NIL,0,GDEXTENSION_VARIANT_TYPE_NIL,GDEXTENSION_VARIANT_TYPE_NIL);
    bind("set_gain",GAIN,GDEXTENSION_VARIANT_TYPE_NIL,1,GDEXTENSION_VARIANT_TYPE_FLOAT,GDEXTENSION_VARIANT_TYPE_NIL);
    bind("render_frames",RENDER,GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY,1,GDEXTENSION_VARIANT_TYPE_INT,GDEXTENSION_VARIANT_TYPE_NIL);
    bind("sample_startup_modifiers",SAMPLE_MODIFIERS,GDEXTENSION_VARIANT_TYPE_INT,0,GDEXTENSION_VARIANT_TYPE_NIL,GDEXTENSION_VARIANT_TYPE_NIL);
}
static void deinitialize(void *userdata,GDExtensionInitializationLevel level) {
    (void)userdata;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
    unregister_class(library,&class_name);Opaque *names[]={&class_name,&base_name,&empty_name,&size_name,&resize_name};
    for(int i=0;i<5;i++)get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(names[i]);get_destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&empty_string);
}
#define LOAD_API(field,type,name) field=(type)get_proc(name)
FT2_EXPORT GDExtensionBool ft2_synth_library_init(GDExtensionInterfaceGetProcAddress get_proc,GDExtensionClassLibraryPtr class_library,GDExtensionInitialization *initialization) {
    library=class_library;
    LOAD_API(sn_new,GDExtensionInterfaceStringNameNewWithLatin1Chars,"string_name_new_with_latin1_chars");
    LOAD_API(get_destructor,GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor");
    LOAD_API(get_constructor,GDExtensionInterfaceVariantGetPtrConstructor,"variant_get_ptr_constructor");
    LOAD_API(from_type,GDExtensionInterfaceGetVariantFromTypeConstructor,"get_variant_from_type_constructor");
    LOAD_API(to_type,GDExtensionInterfaceGetVariantToTypeConstructor,"get_variant_to_type_constructor");
    LOAD_API(new_nil,GDExtensionInterfaceVariantNewNil,"variant_new_nil");
    LOAD_API(destroy_variant,GDExtensionInterfaceVariantDestroy,"variant_destroy");
    LOAD_API(variant_call,GDExtensionInterfaceVariantCall,"variant_call");
    LOAD_API(register_class,GDExtensionInterfaceClassdbRegisterExtensionClass2,"classdb_register_extension_class2");
    LOAD_API(unregister_class,GDExtensionInterfaceClassdbUnregisterExtensionClass,"classdb_unregister_extension_class");
    LOAD_API(register_method,GDExtensionInterfaceClassdbRegisterExtensionClassMethod,"classdb_register_extension_class_method");
    LOAD_API(construct_object,GDExtensionInterfaceClassdbConstructObject,"classdb_construct_object");
    LOAD_API(set_instance,GDExtensionInterfaceObjectSetInstance,"object_set_instance");
    LOAD_API(bytes_at,GDExtensionInterfacePackedByteArrayOperatorIndexConst,"packed_byte_array_operator_index_const");
    LOAD_API(vectors_at,GDExtensionInterfacePackedVector2ArrayOperatorIndex,"packed_vector2_array_operator_index");
    initialization->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;initialization->initialize=initialize;initialization->deinitialize=deinitialize;initialization->userdata=NULL;
    return 1;
}
