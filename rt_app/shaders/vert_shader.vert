#version 450
#extension GL_ARB_separate_shader_objects : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable

#include "wavefront.glsl"

// clang-format off
layout(binding = 2, set = 0, scalar) buffer ScnDesc { sceneDesc i[]; } scnDesc;
// clang-format on

layout(binding = 0) uniform UniformBufferObject
{
  mat4 view;
  mat4 proj;
  mat4 viewI;
}
ubo;

layout(push_constant) uniform shaderInformation
{
  vec3  lightPosition;
  uint  instanceId;
  float lightIntensity;
  int   lightType;
}
pushC;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec3 inColor;
layout(location = 3) in vec2 inTexCoord;
// layout(location = 4) in vec3 inTangent;  //!
// layout(location = 5) in vec3 inBitangent;//!


//layout(location = 0) flat out int matIndex;
layout(location = 1) out vec2 fragTexCoord;
layout(location = 2) out vec3 fragNormal;
layout(location = 3) out vec3 viewDir;
layout(location = 4) out vec3 worldPos;
layout(location = 5) out vec3 normal; //?
// layout(location = 6) out mat3 TBN;
layout(location = 6) out vec3 T;
// layout(location = 8) out vec3 B;
// layout(location = 9) out vec3 N;

out gl_PerVertex
{
  vec4 gl_Position;
};


void main()
{
  mat4 objMatrix   = scnDesc.i[pushC.instanceId].transfo;
  mat4 objMatrixIT = scnDesc.i[pushC.instanceId].transfoIT;

  vec3 origin = vec3(ubo.viewI * vec4(0, 0, 0, 1));

  worldPos     = vec3(objMatrix * vec4(inPosition, 1.0));
  viewDir      = vec3(worldPos - origin);
  fragTexCoord = inTexCoord;
  fragNormal   = vec3(objMatrixIT * vec4(inNormal, 0.0));
  normal       = mat3(objMatrix) * inNormal;
  //  matIndex     = inMatID;



  // vec3 T = normalize(vec3(objMatrix * vec4(inTangent,   0.0)));
  // vec3 N = normalize(vec3(objMatrix * vec4(inNormal,    0.0)));
  // // re-orthogonalize T with respect to N
  // T = normalize(T - dot(T, N) * N);
  // // then retrieve perpendicular vector B with the cross product of T and N
  // vec3 B = cross(N, T);
  // // vec3 B = normalize(vec3(objMatrix * vec4(inBitangent, 0.0)));
  // TBN = mat3(T, B, N);

  // mat3 normal_matrix = mat3(objMatrixIT);

  // vec3 
  // T = inTangent;//*200.0;//normalize(normal_matrix * inTangent);
  // vec3 
  // N = normalize(normal_matrix * inNormal);

  // vec3 B = normalize(cross(N, T) * tangent.w);
  // vec3 
  // B = cross(N, T);
  // vec3 B = normalize(normal_matrix * inBitangent);

  // TBN = mat3(T, B, N);




  gl_Position = ubo.proj * ubo.view * vec4(worldPos, 1.0);
}
