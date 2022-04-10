#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable
#extension GL_NV_compute_shader_derivatives : enable
#include "raycommon.glsl"
#include "wavefront.glsl"
#include "pbr.glsl"

hitAttributeEXT vec2 attribs;

// clang-format off
layout(location = 0) rayPayloadInEXT hitPayload prd;
layout(location = 1) rayPayloadEXT bool isShadowed;

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;

layout(binding = 2, set = 1, scalar) buffer ScnDesc { sceneDesc i[]; } scnDesc;
layout(binding = 5, set = 1, scalar) buffer Vertices { Vertex v[]; } vertices[];
layout(binding = 6, set = 1) buffer Indices { uint i[]; } indices[];

layout(binding = 1, set = 1, scalar) buffer MatColorBufferObject { WaveFrontMaterial m[]; } materials[];
layout(binding = 3, set = 1) uniform sampler2D textureSamplers[];
layout(binding = 4, set = 1)  buffer MatIndexColorBuffer { int i[]; } matIndex[];

// clang-format on

layout(push_constant) uniform Constants
{
  vec4  clearColor;
  vec3  lightPosition;
  float lightIntensity;
  int   lightType;
}
pushC;

const float ATTENUATION = 0.1;

void main()
{
  // Object of this instance
  uint objId = scnDesc.i[gl_InstanceCustomIndexEXT].objId;

  // Indices of the triangle
  ivec3 ind = ivec3(indices[nonuniformEXT(objId)].i[3 * gl_PrimitiveID + 0],   //
                    indices[nonuniformEXT(objId)].i[3 * gl_PrimitiveID + 1],   //
                    indices[nonuniformEXT(objId)].i[3 * gl_PrimitiveID + 2]);  //
  // Vertex of the triangle
  Vertex v0 = vertices[nonuniformEXT(objId)].v[ind.x];
  Vertex v1 = vertices[nonuniformEXT(objId)].v[ind.y];
  Vertex v2 = vertices[nonuniformEXT(objId)].v[ind.z];

  const vec3 barycentrics = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);

  // Computing the normal at hit position
  vec3 normal = v0.nrm * barycentrics.x + v1.nrm * barycentrics.y + v2.nrm * barycentrics.z;
  // Transforming the normal to world space
  normal = normalize(vec3(scnDesc.i[gl_InstanceCustomIndexEXT].transfoIT * vec4(normal, 0.0)));


  // Computing the coordinates of the hit position
  vec3 worldPos = v0.pos * barycentrics.x + v1.pos * barycentrics.y + v2.pos * barycentrics.z;
  // Transforming the position to world space
  worldPos = vec3(scnDesc.i[gl_InstanceCustomIndexEXT].transfo * vec4(worldPos, 1.0));

  // Vector toward the light
  vec3  L;
  float lightIntensity = pushC.lightIntensity;
  float lightDistance  = 100000.0;
  // Point light
  if(pushC.lightType == 0)
  {
    vec3 lDir      = pushC.lightPosition - worldPos;
    lightDistance  = length(lDir);
    lightIntensity = pushC.lightIntensity / (lightDistance * lightDistance);
    L              = normalize(lDir);
  }
  else  // Directional light
  {
    L = normalize(pushC.lightPosition - vec3(0));
  }

  // Material of the object
  int               matIdx = matIndex[nonuniformEXT(objId)].i[gl_PrimitiveID];
  WaveFrontMaterial mat    = materials[nonuniformEXT(objId)].m[matIdx];

  // PBR
  if(mat.textureId >= 0)
  {
    vec2 fragTexCoord = v0.texCoord * barycentrics.x + v1.texCoord * barycentrics.y + v2.texCoord * barycentrics.z;
    int txtOffset = scnDesc.i[gl_InstanceCustomIndexEXT].txtOffset;
    
    // albedo/diffuse
    uint txtId  = txtOffset + mat.textureId;
    vec4 albedoRGBA = texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord);
    
    // aplha
    if(albedoRGBA.a < 0.1) {
      vec3 origin = worldPos;
      prd.done      = 0;
      prd.rayOrigin = origin;
      prd.depth--;
      return;
    }

    vec3 albedo = pow(albedoRGBA.rgb, vec3(2.2));


    // Normal Map
    vec3 N;
    if(mat.textureNormalId >= 0)
    {
      
      txtId = txtOffset + mat.textureNormalId;
      vec3 tangentNormal = texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).xyz * 2.0 - 1.0;
      // prd.hitValue = tangentNormal;
      // return;
      //TBN
      vec3 T = normalize(vec3(scnDesc.i[gl_InstanceCustomIndexEXT].transfo * vec4(v0.tangent,  0.0)));
      // prd.hitValue = T;
      // return;
      vec3 N = normalize(vec3(scnDesc.i[gl_InstanceCustomIndexEXT].transfo * vec4(v0.nrm,      0.0)));
      // prd.hitValue = N;
      // return;
      // re-orthogonalize T with respect to N
      // T = normalize(T - dot(T, N) * N);
      // prd.hitValue = T;
      // return;
      // then retrieve perpendicular vector B with the cross product of T and N
      vec3 B = cross(N, T);
      // vec3 B = normalize(vec3(scnDesc.i[gl_InstanceCustomIndexEXT].transfo * vec4(v0.bitangent, 0.0)));
      // prd.hitValue = B;
      // return;
      mat3 TBN = mat3(T, B, N);
      //TBN

      // N = getNormalFromMap(tangentNormal, TBN);
      N = normalize(TBN * tangentNormal);
      prd.hitValue = normal;//N; //! hack because N is invalid out of this if scope
      // prd.hitValue = N; //! hack because N is invalid out of this if scope
      // prd.hitValue = v0.tangent;//N; //! hack because N is invalid out of this if scope
      // return;
      
    } else {
      N = normal;
      prd.hitValue = N;
      // return;
    }

    // metallic
    float metallic = 0.0;
    if(mat.textureMetallicId >= 0)
    {
      txtId    = txtOffset + mat.textureMetallicId;
      metallic = 1.0 - texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).b;
      // prd.hitValue = vec3(metallic);//albedo * metallic;
      // return;
    }
    // roughness
    float roughness = 0.0;
    if(mat.textureRoughnessId >= 0)
    {
      txtId     = txtOffset + mat.textureRoughnessId;
      roughness = texture(textureSamplers[nonuniformEXT(txtId)], fragTexCoord).g;
      // prd.hitValue = albedo * roughness;
      // return;
    }

    // calculate reflectance at normal incidence; if dia-electric (like plastic) use F0 
    // of 0.04 and if it's a metal, use the albedo color as F0 (metallic workflow)    
    vec3 F0 = vec3(0.04); 
    F0 = mix(F0, albedo, metallic);

    // reflectance equation
    vec3 Lo = vec3(0.0);

    vec3 V = normalize(-prd.rayDir);

    if(pushC.lightType == 0) // point
    {
      Lo += calcPointLight(lightIntensity, L, V, prd.hitValue/*normal value*/, F0, Lo, albedo, metallic, roughness);
    }
    else  // (pushC.lightType == 1) // infinite/directional;
    {
      // Lo += calcDirLight(dl, V, N, F0, Lo, albedo, metallic, roughness);
    }

    // ambient lighting
    //vec3 ambient = vec3(0.03) * albedo * ao;
    //Lo += ambient;

    vec3 color = Lo;

    //!
    // Tracing shadow ray only if the light is visible from the surface
    if(dot(normal, L) > 0)
    {
      float tMin   = 0.001;
      float tMax   = lightDistance;
      vec3  origin = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
      vec3  rayDir = L;
      uint  flags  = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT
                  | gl_RayFlagsSkipClosestHitShaderEXT;
      isShadowed = true;
      traceRayEXT(topLevelAS,  // acceleration structure
                  flags,       // rayFlags
                  0xFF,        // cullMask
                  0,           // sbtRecordOffset
                  0,           // sbtRecordStride
                  1,           // missIndex
                  origin,      // ray origin
                  tMin,        // ray min range
                  rayDir,      // ray direction
                  tMax,        // ray max range
                  1            // payload (location = 1)
      );

      if(isShadowed)
      {
        // attenuation = 0.3;
        prd.attenuation = vec3(ATTENUATION);
      }
    }
    //!

    // HDR tonemapping
    // color = color / (color + vec3(1.0));
    // gamma correct
    color = pow(color, vec3(1.0/2.2)); 

    prd.hitValue = color;

    // ...
  }
  // Lambert
  else
  {
    // Diffuse
    vec3 diffuse = computeDiffuse(mat, L, normal);
    if(mat.textureId >= 0)
    {
      uint txtId = mat.textureId + scnDesc.i[gl_InstanceCustomIndexEXT].txtOffset;
      vec2 texCoord =
          v0.texCoord * barycentrics.x + v1.texCoord * barycentrics.y + v2.texCoord * barycentrics.z;
      diffuse *= texture(textureSamplers[nonuniformEXT(txtId)], texCoord).xyz;
    }

    vec3  specular    = vec3(0);
    float attenuation = 1;

    // Tracing shadow ray only if the light is visible from the surface
    if(dot(normal, L) > 0)
    {
      float tMin   = 0.001;
      float tMax   = lightDistance;
      vec3  origin = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
      vec3  rayDir = L;
      uint  flags  = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT
                  | gl_RayFlagsSkipClosestHitShaderEXT;
      isShadowed = true;
      traceRayEXT(topLevelAS,  // acceleration structure
                  flags,       // rayFlags
                  0xFF,        // cullMask
                  0,           // sbtRecordOffset
                  0,           // sbtRecordStride
                  1,           // missIndex
                  origin,      // ray origin
                  tMin,        // ray min range
                  rayDir,      // ray direction
                  tMax,        // ray max range
                  1            // payload (location = 1)
      );

      if(isShadowed)
      {
        attenuation = ATTENUATION;
      }
      else
      {
        // Specular
        specular = computeSpecular(mat, gl_WorldRayDirectionEXT, L, normal);
      }
    }

    // Reflection
    if(mat.illum == 3)
    {
      vec3 origin      = worldPos;
      vec3 rayDir      = reflect(gl_WorldRayDirectionEXT, normal);
      prd.rayOrigin    = origin;
      prd.rayDir       = rayDir;
      prd.attenuation *= mat.specular;
      prd.done         = 0;
    }

    prd.hitValue = vec3(attenuation * lightIntensity * (diffuse + specular));
  }
}
