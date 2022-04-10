#version 450
#extension GL_ARB_separate_shader_objects : enable
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_scalar_block_layout : enable

#include "wavefront.glsl"
#include "pbr.glsl"

layout(push_constant) uniform shaderInformation
{
  vec3  lightPosition;
  uint  instanceId;
  float lightIntensity;
  int   lightType; // 0: point, 1: infinite
}
pushC;

// clang-format off
// Incoming 
//layout(location = 0) flat in int matIndex;
layout(location = 1) in vec2 fragTexCoord;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec3 viewDir;
layout(location = 4) in vec3 worldPos;
layout(location = 5) in vec3 normal;
// layout(location = 6) in mat3 TBN;
layout(location = 6) in vec3 T;
// Outgoing
layout(location = 0) out vec4 outColor;
// Buffers
layout(binding = 1, scalar) buffer MatColorBufferObject { WaveFrontMaterial m[]; } materials[];
layout(binding = 2, scalar) buffer ScnDesc { sceneDesc i[]; } scnDesc;
layout(binding = 3) uniform sampler2D[] textureSamplers;
layout(binding = 4, scalar) buffer MatIndex { int i[]; } matIdx[];

// Easy trick to get tangent-normals to world-space to keep PBR code simplified.
// Don't worry if you don't get what's going on; you generally want to do normal 
// mapping the usual way for performance anways; I do plan make a note of this 
// technique somewhere later in the normal mapping tutorial.
vec3 getNormalFromMapA(vec3 tangentNormal, vec2 TexCoords, vec3 WorldPos, vec3 Normal)
{
    //!! vec3 tangentNormal = texture(normalMap, TexCoords).xyz * 2.0 - 1.0;

    tangentNormal = (2.0 * tangentNormal) - vec3(1.0, 1.0, 1.0);

    vec3 Q1  = dFdx(WorldPos);
    vec3 Q2  = dFdy(WorldPos);
    vec2 st1 = dFdx(TexCoords);
    vec2 st2 = dFdy(TexCoords);

    vec3 N   = normalize(Normal);
    vec3 T   = normalize(Q1*st2.t - Q2*st1.t);
    vec3 B   = -normalize(cross(N, T));

    T = normalize(T - dot(T, N) * N);
    if (dot(cross(N, T), B) < 0.0){
      T = T * -1.0;
    }

    mat3 TBN = mat3(T, B, N);

    return normalize(TBN * tangentNormal);
}
vec3 getNormalFromMapB(vec3 tangentNormal, vec2 TexCoords, vec3 WorldPos, vec3 Normal)
{
    //!! vec3 tangentNormal = texture(normalMap, TexCoords).xyz * 2.0 - 1.0;

    // tangentNormal = (2.0 * tangentNormal) - vec3(1.0, 1.0, 1.0);

    vec3 dp1 = dFdx(WorldPos);
    vec3 dp2 = dFdy(WorldPos);
    vec2 duv1 = dFdx(TexCoords);
    vec2 duv2 = dFdy(TexCoords);

    vec3 N   = normalize(Normal);

    // solve the linear system
    vec3 dp2perp = cross( dp2, N );
    vec3 dp1perp = cross( N, dp1 );
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
    
    // construct a scale-invariant frame
    float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
    mat3 TBN = mat3( T * invmax, B * invmax, N );

    // tangentNormal.y = -tangentNormal.y;
    return normalize(TBN * tangentNormal);
}

// clang-format on
void main()
{
  // Object of this instance
  int objId = scnDesc.i[pushC.instanceId].objId;

  // Material of the object
  int               matIndex = matIdx[nonuniformEXT(objId)].i[gl_PrimitiveID];
  WaveFrontMaterial mat      = materials[nonuniformEXT(objId)].m[matIndex];

  // Vector toward light
  vec3  L;
  float lightIntensity = pushC.lightIntensity;
  if(pushC.lightType == 0) // point
  {
    vec3  lDir     = pushC.lightPosition - worldPos;
    float d        = length(lDir);
    lightIntensity = pushC.lightIntensity / (d * d);
    L              = normalize(lDir);
  }
  else // (pushC.lightType == 1) // infinite/directional;
  {
    L = normalize(pushC.lightPosition - vec3(0));
  }


  if(mat.textureId >= 0)
  {
    int txtOffset = scnDesc.i[pushC.instanceId].txtOffset;

    // albedo/diffuse
    uint txtId  = txtOffset + mat.textureId;
    vec3 albedo = vec3(0.0);
    //albedo = pow(texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).rgb, vec3(2.2));
    vec4 albedoRGBA = texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord);
    
    // aplha
    if(albedoRGBA.a < 0.1) {
      //vec3 origin = worldPos;
      //prd.done      = 0;
      //prd.rayOrigin = origin;
      discard;
    }

    albedo = pow(albedoRGBA.rgb, vec3(2.2));

    // normal
    vec3 N = normalize(normal);
    if(mat.textureNormalId >= 0)
    {
      txtId = txtOffset + mat.textureNormalId;

      ////// A
      // vec3 tangentNormal = texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).xyz;
      // N = getNormalFromMapA(tangentNormal, fragTexCoord, worldPos, normal);

      ////// B
      vec3 tangentNormal = texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).xyz * 2.0 - 1.0;
      // tangentNormal.y = -tangentNormal.y;
      // tangentNormal = rgb_to_srgb(tangentNormal);
      // N = getNormalFromMapB(tangentNormal, fragTexCoord, viewDir, normal);
      // N = getNormalFromMapB(tangentNormal, fragTexCoord, worldPos, normal);

      // outColor = vec4(N, 1);
      // outColor = vec4(T, 1);
      // outColor = vec4(tangentNormal, 1);
      // outColor = vec4(normalize(TBN * tangentNormal), 1);
      // return;

      // N = getNormalFromMap(tangentNormal, TBN);
    }

    
    // metallic
    float metallic = 0.0;
    if(mat.textureMetallicId >= 0)
    {
      txtId    = txtOffset + mat.textureMetallicId;
      metallic = 1.0 - texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).b;
    }

    // roughness
    float roughness = 0.0;
    if(mat.textureRoughnessId >= 0)
    {
      txtId     = txtOffset + mat.textureRoughnessId;
      roughness = texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).g;
    }

    // calculate reflectance at normal incidence; if dia-electric (like plastic) use F0 
    // of 0.04 and if it's a metal, use the albedo color as F0 (metallic workflow)    
    vec3 F0 = vec3(0.04); 
    F0 = mix(F0, albedo, metallic);

    // reflectance equation
    vec3 Lo = vec3(0.0);

    vec3 V = normalize(-viewDir);

    if(pushC.lightType == 0) // point
    {
      Lo += calcPointLight(lightIntensity, L, V, N, F0, Lo, albedo, metallic, roughness);
    }
    else  // (pushC.lightType == 1) // infinite/directional;
    {
      // Lo += calcDirLight(dl, V, N, F0, Lo, albedo, metallic, roughness);
    }

    // ambient lighting
    //vec3 ambient = vec3(0.03) * albedo * ao;
    //Lo += ambient;

    vec3 color = Lo;

    // HDR tonemapping
    // color = color / (color + vec3(1.0));
    // gamma correct
    color = pow(color, vec3(1.0/2.2)); 

    outColor = vec4(color, 1.0);
    // outColor = vec4(lightIntensity * (diffuse + specular), 1);
  }
  else
  {
    vec3 N = normalize(fragNormal);
    vec3 diffuse = computeDiffuse(mat, L, N);
    // Specular
    vec3 specular = computeSpecular(mat, viewDir, L, N);

    // Result
    outColor = vec4(lightIntensity * (diffuse + specular), 1);
  }
}
