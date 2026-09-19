#include "glloader.h"

#ifndef GLFW_INCLUDE_NONE
#define GLFW_INCLUDE_NONE
#endif
#include <GLFW/glfw3.h>

PFNGLACTIVETEXTUREPROC bw_glActiveTexture = nullptr;
PFNGLATTACHSHADERPROC bw_glAttachShader = nullptr;
PFNGLBINDBUFFERPROC bw_glBindBuffer = nullptr;
PFNGLBINDTEXTUREPROC bw_glBindTexture = nullptr;
PFNGLBINDVERTEXARRAYPROC bw_glBindVertexArray = nullptr;
PFNGLBLENDFUNCPROC bw_glBlendFunc = nullptr;
PFNGLBUFFERDATAPROC bw_glBufferData = nullptr;
PFNGLCLEARPROC bw_glClear = nullptr;
PFNGLCLEARCOLORPROC bw_glClearColor = nullptr;
PFNGLCOMPILESHADERPROC bw_glCompileShader = nullptr;
PFNGLCREATEPROGRAMPROC bw_glCreateProgram = nullptr;
PFNGLCREATESHADERPROC bw_glCreateShader = nullptr;
PFNGLDEPTHFUNCPROC bw_glDepthFunc = nullptr;
PFNGLDEPTHMASKPROC bw_glDepthMask = nullptr;
PFNGLDISABLEPROC bw_glDisable = nullptr;
PFNGLDRAWARRAYSPROC bw_glDrawArrays = nullptr;
PFNGLDRAWELEMENTSPROC bw_glDrawElements = nullptr;
PFNGLDRAWELEMENTSINSTANCEDPROC bw_glDrawElementsInstanced = nullptr;
PFNGLENABLEPROC bw_glEnable = nullptr;
PFNGLENABLEVERTEXATTRIBARRAYPROC bw_glEnableVertexAttribArray = nullptr;
PFNGLGENBUFFERSPROC bw_glGenBuffers = nullptr;
PFNGLGENERATEMIPMAPPROC bw_glGenerateMipmap = nullptr;
PFNGLGENTEXTURESPROC bw_glGenTextures = nullptr;
PFNGLGENVERTEXARRAYSPROC bw_glGenVertexArrays = nullptr;
PFNGLGETERRORPROC bw_glGetError = nullptr;
PFNGLGETFLOATVPROC bw_glGetFloatv = nullptr;
PFNGLGETPROGRAMINFOLOGPROC bw_glGetProgramInfoLog = nullptr;
PFNGLGETPROGRAMIVPROC bw_glGetProgramiv = nullptr;
PFNGLGETSHADERINFOLOGPROC bw_glGetShaderInfoLog = nullptr;
PFNGLGETSHADERIVPROC bw_glGetShaderiv = nullptr;
PFNGLGETUNIFORMLOCATIONPROC bw_glGetUniformLocation = nullptr;
PFNGLLINKPROGRAMPROC bw_glLinkProgram = nullptr;
PFNGLPIXELSTOREIPROC bw_glPixelStorei = nullptr;
PFNGLREADPIXELSPROC bw_glReadPixels = nullptr;
PFNGLSHADERSOURCEPROC bw_glShaderSource = nullptr;
PFNGLTEXIMAGE2DPROC bw_glTexImage2D = nullptr;
PFNGLTEXIMAGE3DPROC bw_glTexImage3D = nullptr;
PFNGLTEXPARAMETERFPROC bw_glTexParameterf = nullptr;
PFNGLTEXPARAMETERIPROC bw_glTexParameteri = nullptr;
PFNGLTEXSUBIMAGE3DPROC bw_glTexSubImage3D = nullptr;
PFNGLUNIFORM1FPROC bw_glUniform1f = nullptr;
PFNGLUNIFORM1IPROC bw_glUniform1i = nullptr;
PFNGLUNIFORM2FPROC bw_glUniform2f = nullptr;
PFNGLUNIFORM3FPROC bw_glUniform3f = nullptr;
PFNGLUNIFORM3FVPROC bw_glUniform3fv = nullptr;
PFNGLUNIFORMMATRIX4FVPROC bw_glUniformMatrix4fv = nullptr;
PFNGLUSEPROGRAMPROC bw_glUseProgram = nullptr;
PFNGLVERTEXATTRIBDIVISORPROC bw_glVertexAttribDivisor = nullptr;
PFNGLVERTEXATTRIBPOINTERPROC bw_glVertexAttribPointer = nullptr;
PFNGLVIEWPORTPROC bw_glViewport = nullptr;

bool glLoadFunctions() {
    bool ok = true;
    auto get = [&ok](const char* name) -> void* {
        void* p = (void*)glfwGetProcAddress(name);
        if (!p)
            ok = false;
        return p;
    };
    bw_glActiveTexture = (PFNGLACTIVETEXTUREPROC)get("glActiveTexture");
    bw_glAttachShader = (PFNGLATTACHSHADERPROC)get("glAttachShader");
    bw_glBindBuffer = (PFNGLBINDBUFFERPROC)get("glBindBuffer");
    bw_glBindTexture = (PFNGLBINDTEXTUREPROC)get("glBindTexture");
    bw_glBindVertexArray = (PFNGLBINDVERTEXARRAYPROC)get("glBindVertexArray");
    bw_glBlendFunc = (PFNGLBLENDFUNCPROC)get("glBlendFunc");
    bw_glBufferData = (PFNGLBUFFERDATAPROC)get("glBufferData");
    bw_glClear = (PFNGLCLEARPROC)get("glClear");
    bw_glClearColor = (PFNGLCLEARCOLORPROC)get("glClearColor");
    bw_glCompileShader = (PFNGLCOMPILESHADERPROC)get("glCompileShader");
    bw_glCreateProgram = (PFNGLCREATEPROGRAMPROC)get("glCreateProgram");
    bw_glCreateShader = (PFNGLCREATESHADERPROC)get("glCreateShader");
    bw_glDepthFunc = (PFNGLDEPTHFUNCPROC)get("glDepthFunc");
    bw_glDepthMask = (PFNGLDEPTHMASKPROC)get("glDepthMask");
    bw_glDisable = (PFNGLDISABLEPROC)get("glDisable");
    bw_glDrawArrays = (PFNGLDRAWARRAYSPROC)get("glDrawArrays");
    bw_glDrawElements = (PFNGLDRAWELEMENTSPROC)get("glDrawElements");
    bw_glDrawElementsInstanced = (PFNGLDRAWELEMENTSINSTANCEDPROC)get("glDrawElementsInstanced");
    bw_glEnable = (PFNGLENABLEPROC)get("glEnable");
    bw_glEnableVertexAttribArray = (PFNGLENABLEVERTEXATTRIBARRAYPROC)get("glEnableVertexAttribArray");
    bw_glGenBuffers = (PFNGLGENBUFFERSPROC)get("glGenBuffers");
    bw_glGenerateMipmap = (PFNGLGENERATEMIPMAPPROC)get("glGenerateMipmap");
    bw_glGenTextures = (PFNGLGENTEXTURESPROC)get("glGenTextures");
    bw_glGenVertexArrays = (PFNGLGENVERTEXARRAYSPROC)get("glGenVertexArrays");
    bw_glGetError = (PFNGLGETERRORPROC)get("glGetError");
    bw_glGetFloatv = (PFNGLGETFLOATVPROC)get("glGetFloatv");
    bw_glGetProgramInfoLog = (PFNGLGETPROGRAMINFOLOGPROC)get("glGetProgramInfoLog");
    bw_glGetProgramiv = (PFNGLGETPROGRAMIVPROC)get("glGetProgramiv");
    bw_glGetShaderInfoLog = (PFNGLGETSHADERINFOLOGPROC)get("glGetShaderInfoLog");
    bw_glGetShaderiv = (PFNGLGETSHADERIVPROC)get("glGetShaderiv");
    bw_glGetUniformLocation = (PFNGLGETUNIFORMLOCATIONPROC)get("glGetUniformLocation");
    bw_glLinkProgram = (PFNGLLINKPROGRAMPROC)get("glLinkProgram");
    bw_glPixelStorei = (PFNGLPIXELSTOREIPROC)get("glPixelStorei");
    bw_glReadPixels = (PFNGLREADPIXELSPROC)get("glReadPixels");
    bw_glShaderSource = (PFNGLSHADERSOURCEPROC)get("glShaderSource");
    bw_glTexImage2D = (PFNGLTEXIMAGE2DPROC)get("glTexImage2D");
    bw_glTexImage3D = (PFNGLTEXIMAGE3DPROC)get("glTexImage3D");
    bw_glTexParameterf = (PFNGLTEXPARAMETERFPROC)get("glTexParameterf");
    bw_glTexParameteri = (PFNGLTEXPARAMETERIPROC)get("glTexParameteri");
    bw_glTexSubImage3D = (PFNGLTEXSUBIMAGE3DPROC)get("glTexSubImage3D");
    bw_glUniform1f = (PFNGLUNIFORM1FPROC)get("glUniform1f");
    bw_glUniform1i = (PFNGLUNIFORM1IPROC)get("glUniform1i");
    bw_glUniform2f = (PFNGLUNIFORM2FPROC)get("glUniform2f");
    bw_glUniform3f = (PFNGLUNIFORM3FPROC)get("glUniform3f");
    bw_glUniform3fv = (PFNGLUNIFORM3FVPROC)get("glUniform3fv");
    bw_glUniformMatrix4fv = (PFNGLUNIFORMMATRIX4FVPROC)get("glUniformMatrix4fv");
    bw_glUseProgram = (PFNGLUSEPROGRAMPROC)get("glUseProgram");
    bw_glVertexAttribDivisor = (PFNGLVERTEXATTRIBDIVISORPROC)get("glVertexAttribDivisor");
    bw_glVertexAttribPointer = (PFNGLVERTEXATTRIBPOINTERPROC)get("glVertexAttribPointer");
    bw_glViewport = (PFNGLVIEWPORTPROC)get("glViewport");
    return ok;
}
