/* Native arm64 app entry point. No game bytes or shell command evaluation. */
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char *join(const char *base,const char *suffix){
    size_t size=strlen(base)+strlen(suffix)+2;
    char *path=malloc(size);
    if(path)snprintf(path,size,"%s/%s",base,suffix);
    return path;
}

int main(int argc,char **argv){
    /* Finder has a minimal PATH. Keep an explicitly activated venv authoritative,
       otherwise make the usual Apple Silicon/Homebrew Python locations visible. */
    if(!getenv("VIRTUAL_ENV")){
        const char *existing=getenv("PATH");
        const char *prefix="/opt/homebrew/bin:/usr/local/bin:";
        size_t length=strlen(prefix)+(existing?strlen(existing):0)+1;
        char *path=malloc(length);
        if(!path)return 70;
        snprintf(path,length,"%s%s",prefix,existing?existing:"");
        setenv("PATH",path,1);
        free(path);
    }
    uint32_t size=0;
    _NSGetExecutablePath(NULL,&size);
    char *raw=malloc((size_t)size+1);
    if(!raw||_NSGetExecutablePath(raw,&size)!=0)return 71;
    char *resolved=realpath(raw,NULL);
    if(!resolved)return 72;
    char *slash=strrchr(resolved,'/');
    if(!slash)return 73;
    *slash='\0';
    char *runtime=join(resolved,"GodotRuntime");
    char *resources=join(resolved,"../Resources");
    char *pack=resources?join(resources,"FT2-External.pck"):NULL;
    char **arguments=calloc((size_t)argc+6,sizeof(char *));
    if(!runtime||!resources||!pack||!arguments)return 74;
    arguments[0]=runtime;
    arguments[1]="--path";arguments[2]=resources;
    arguments[3]="--main-pack";arguments[4]=pack;
    for(int i=1;i<argc;i++)arguments[i+4]=argv[i];
    if(chdir(resources)!=0)return 75;
    execv(runtime,arguments);
    perror("FT2 External Engine could not start");
    return 76;
}
