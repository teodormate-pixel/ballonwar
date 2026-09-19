// ============================================================
// Minimal OpenGL 3.3 core loader (no GLEW dependency)
//
// glcorearb.h (Khronos, MIT) provides the typedefs and enums but
// also declares the GL 1.x functions as prototypes, so the loaded
// pointers live under bw_* names and the usual gl* names are
// mapped onto them with macros. Call glLoadFunctions() after
// glfwMakeContextCurrent().
// ============================================================

#pragma once

#include "glcorearb.h"

// EXT_texture_filter_anisotropic (not part of the core header)
#ifndef GL_TEXTURE_MAX_ANISOTROPY_EXT
#define GL_TEXTURE_MAX_ANISOTROPY_EXT 0x84FE
#endif
#ifndef GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT
#define GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT 0x84FF
#endif

// resolves all pointers; call after glfwMakeContextCurrent()
bool glLoadFunctions();

extern PFNGLACTIVETEXTUREPROC bw_glActiveTexture;
extern PFNGLATTACHSHADERPROC bw_glAttachShader;
extern PFNGLBINDBUFFERPROC bw_glBindBuffer;
extern PFNGLBINDTEXTUREPROC bw_glBindTexture;
extern PFNGLBINDVERTEXARRAYPROC bw_glBindVertexArray;
extern PFNGLBLENDFUNCPROC bw_glBlendFunc;
extern PFNGLBUFFERDATAPROC bw_glBufferData;
extern PFNGLCLEARPROC bw_glClear;
extern PFNGLCLEARCOLORPROC bw_glClearColor;
extern PFNGLCOMPILESHADERPROC bw_glCompileShader;
extern PFNGLCREATEPROGRAMPROC bw_glCreateProgram;
extern PFNGLCREATESHADERPROC bw_glCreateShader;
extern PFNGLDEPTHFUNCPROC bw_glDepthFunc;
extern PFNGLDEPTHMASKPROC bw_glDepthMask;
extern PFNGLDISABLEPROC bw_glDisable;
extern PFNGLDRAWARRAYSPROC bw_glDrawArrays;
extern PFNGLDRAWELEMENTSPROC bw_glDrawElements;
extern PFNGLDRAWELEMENTSINSTANCEDPROC bw_glDrawElementsInstanced;
extern PFNGLENABLEPROC bw_glEnable;
extern PFNGLENABLEVERTEXATTRIBARRAYPROC bw_glEnableVertexAttribArray;
extern PFNGLGENBUFFERSPROC bw_glGenBuffers;
extern PFNGLGENERATEMIPMAPPROC bw_glGenerateMipmap;
extern PFNGLGENTEXTURESPROC bw_glGenTextures;
extern PFNGLGENVERTEXARRAYSPROC bw_glGenVertexArrays;
extern PFNGLGETERRORPROC bw_glGetError;
extern PFNGLGETFLOATVPROC bw_glGetFloatv;
extern PFNGLGETPROGRAMINFOLOGPROC bw_glGetProgramInfoLog;
extern PFNGLGETPROGRAMIVPROC bw_glGetProgramiv;
extern PFNGLGETSHADERINFOLOGPROC bw_glGetShaderInfoLog;
extern PFNGLGETSHADERIVPROC bw_glGetShaderiv;
extern PFNGLGETUNIFORMLOCATIONPROC bw_glGetUniformLocation;
extern PFNGLLINKPROGRAMPROC bw_glLinkProgram;
extern PFNGLPIXELSTOREIPROC bw_glPixelStorei;
extern PFNGLREADPIXELSPROC bw_glReadPixels;
extern PFNGLSHADERSOURCEPROC bw_glShaderSource;
extern PFNGLTEXIMAGE2DPROC bw_glTexImage2D;
extern PFNGLTEXIMAGE3DPROC bw_glTexImage3D;
extern PFNGLTEXPARAMETERFPROC bw_glTexParameterf;
extern PFNGLTEXPARAMETERIPROC bw_glTexParameteri;
extern PFNGLTEXSUBIMAGE3DPROC bw_glTexSubImage3D;
extern PFNGLUNIFORM1FPROC bw_glUniform1f;
extern PFNGLUNIFORM1IPROC bw_glUniform1i;
extern PFNGLUNIFORM2FPROC bw_glUniform2f;
extern PFNGLUNIFORM3FPROC bw_glUniform3f;
extern PFNGLUNIFORM3FVPROC bw_glUniform3fv;
extern PFNGLUNIFORMMATRIX4FVPROC bw_glUniformMatrix4fv;
extern PFNGLUSEPROGRAMPROC bw_glUseProgram;
extern PFNGLVERTEXATTRIBDIVISORPROC bw_glVertexAttribDivisor;
extern PFNGLVERTEXATTRIBPOINTERPROC bw_glVertexAttribPointer;
extern PFNGLVIEWPORTPROC bw_glViewport;

#define glActiveTexture bw_glActiveTexture
#define glAttachShader bw_glAttachShader
#define glBindBuffer bw_glBindBuffer
#define glBindTexture bw_glBindTexture
#define glBindVertexArray bw_glBindVertexArray
#define glBlendFunc bw_glBlendFunc
#define glBufferData bw_glBufferData
#define glClear bw_glClear
#define glClearColor bw_glClearColor
#define glCompileShader bw_glCompileShader
#define glCreateProgram bw_glCreateProgram
#define glCreateShader bw_glCreateShader
#define glDepthFunc bw_glDepthFunc
#define glDepthMask bw_glDepthMask
#define glDisable bw_glDisable
#define glDrawArrays bw_glDrawArrays
#define glDrawElements bw_glDrawElements
#define glDrawElementsInstanced bw_glDrawElementsInstanced
#define glEnable bw_glEnable
#define glEnableVertexAttribArray bw_glEnableVertexAttribArray
#define glGenBuffers bw_glGenBuffers
#define glGenerateMipmap bw_glGenerateMipmap
#define glGenTextures bw_glGenTextures
#define glGenVertexArrays bw_glGenVertexArrays
#define glGetError bw_glGetError
#define glGetFloatv bw_glGetFloatv
#define glGetProgramInfoLog bw_glGetProgramInfoLog
#define glGetProgramiv bw_glGetProgramiv
#define glGetShaderInfoLog bw_glGetShaderInfoLog
#define glGetShaderiv bw_glGetShaderiv
#define glGetUniformLocation bw_glGetUniformLocation
#define glLinkProgram bw_glLinkProgram
#define glPixelStorei bw_glPixelStorei
#define glReadPixels bw_glReadPixels
#define glShaderSource bw_glShaderSource
#define glTexImage2D bw_glTexImage2D
#define glTexImage3D bw_glTexImage3D
#define glTexParameterf bw_glTexParameterf
#define glTexParameteri bw_glTexParameteri
#define glTexSubImage3D bw_glTexSubImage3D
#define glUniform1f bw_glUniform1f
#define glUniform1i bw_glUniform1i
#define glUniform2f bw_glUniform2f
#define glUniform3f bw_glUniform3f
#define glUniform3fv bw_glUniform3fv
#define glUniformMatrix4fv bw_glUniformMatrix4fv
#define glUseProgram bw_glUseProgram
#define glVertexAttribDivisor bw_glVertexAttribDivisor
#define glVertexAttribPointer bw_glVertexAttribPointer
#define glViewport bw_glViewport
