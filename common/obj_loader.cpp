/******************************************************************************
 * Copyright 1998-2018 NVIDIA Corp. All Rights Reserved.
 *****************************************************************************/

// This file exist only to do the implementation of tiny obj loader
#define TINYOBJLOADER_IMPLEMENTATION
#include "fileformats/tiny_obj_loader.h"
#include "obj_loader.h"
#include "nvh/nvprint.hpp"

//-----------------------------------------------------------------------------
// Extract the directory component from a complete path.
//
#ifdef WIN32
#define CORRECT_PATH_SEP "\\"
#define WRONG_PATH_SEP '/'
#else
#define CORRECT_PATH_SEP "/"
#define WRONG_PATH_SEP '\\'
#endif

static inline std::string get_path(const std::string& file)
{
  std::string dir;
  size_t      idx = file.find_last_of("\\/");
  if(idx != std::string::npos)
    dir = file.substr(0, idx);
  if(!dir.empty())
  {
    dir += CORRECT_PATH_SEP;
  }
  return dir;
}

void ObjLoader::loadModel(const std::string& filename, bool useMat)
{
  tinyobj::ObjReader reader;
  reader.ParseFromFile(filename);
  if(!reader.Valid())
  {
    LOGE(reader.Error().c_str());
    std::cerr << "Cannot load: " << filename << std::endl;
    assert(reader.Valid());
  }

  // Collecting the material in the scene
  if ( useMat )
  {
    for ( const auto& material : reader.GetMaterials() )
    {
      MaterialObj m;
      m.ambient = nvmath::vec3f( material.ambient[0], material.ambient[1], material.ambient[2] );
      m.diffuse = nvmath::vec3f( material.diffuse[0], material.diffuse[1], material.diffuse[2] );
      m.specular = nvmath::vec3f( material.specular[0], material.specular[1], material.specular[2] );
      m.emission = nvmath::vec3f( material.emission[0], material.emission[1], material.emission[2] );
      m.transmittance = nvmath::vec3f( material.transmittance[0], material.transmittance[1],
        material.transmittance[2] );
      m.dissolve = material.dissolve;
      m.ior = material.ior;
      m.shininess = material.shininess;
      m.illum = material.illum;
      if ( !material.diffuse_texname.empty() )
      {
        m_textures.push_back( material.diffuse_texname );
        m.textureID = static_cast<int>(m_textures.size()) - 1;
      }
      if ( !material.bump_texname.empty() )
      {
        m_textures.push_back( material.bump_texname );
        m.textureNormalId = static_cast<int>(m_textures.size()) - 1;
      }
      if ( !material.specular_highlight_texname.empty() )
      {
        m_textures.push_back( material.specular_highlight_texname );
        m.textureRoughnessId = static_cast<int>(m_textures.size()) - 1;
      }
      if ( !material.reflection_texname.empty() )
      {
        m_textures.push_back( material.reflection_texname );
        m.textureMetallicId = static_cast<int>(m_textures.size()) - 1;
      }

      m_materials.emplace_back( m );
    }
  }

  // If there were none, add a default
  if(m_materials.empty())
    m_materials.emplace_back(MaterialObj());

  const tinyobj::attrib_t& attrib = reader.GetAttrib();

  for(const auto& shape : reader.GetShapes())
  {
    m_vertices.reserve(shape.mesh.indices.size() + m_vertices.size());
    m_indices.reserve(shape.mesh.indices.size() + m_indices.size());
    m_matIndx.insert(m_matIndx.end(), shape.mesh.material_ids.begin(),
                     shape.mesh.material_ids.end());

    for(const auto& index : shape.mesh.indices)
    {
      VertexObj    vertex = {};
      const float* vp     = &attrib.vertices[3 * index.vertex_index];
      vertex.pos          = {*(vp + 0), *(vp + 1), *(vp + 2)};

      if(!attrib.normals.empty() && index.normal_index >= 0)
      {
        const float* np = &attrib.normals[3 * index.normal_index];
        vertex.nrm      = {*(np + 0), *(np + 1), *(np + 2)};
      }

      if(!attrib.texcoords.empty() && index.texcoord_index >= 0)
      {
        const float* tp = &attrib.texcoords[2 * index.texcoord_index + 0];
        vertex.texCoord = {*tp, 1.0f - *(tp + 1)};
      }

      if(!attrib.colors.empty())
      {
        const float* vc = &attrib.colors[3 * index.vertex_index];
        vertex.color    = {*(vc + 0), *(vc + 1), *(vc + 2)};
      }

      m_vertices.push_back(vertex);
      m_indices.push_back(static_cast<int>(m_indices.size()));
    }
  }


  // Fixing material indices
  for(auto& mi : m_matIndx)
  {
    if(mi < 0 || mi > m_materials.size())
      mi = 0;
  }


  // Compute normal when no normal were provided.
  if(attrib.normals.empty())
  {
    for(size_t i = 0; i < m_indices.size(); i += 3)
    {
      VertexObj& v0 = m_vertices[m_indices[i + 0]];
      VertexObj& v1 = m_vertices[m_indices[i + 1]];
      VertexObj& v2 = m_vertices[m_indices[i + 2]];

      nvmath::vec3f n = nvmath::normalize(nvmath::cross((v1.pos - v0.pos), (v2.pos - v0.pos)));
      v0.nrm          = n;
      v1.nrm          = n;
      v2.nrm          = n;
    }
  }

  // ===============================================================================================
  //! tangents & bitangent
  for ( int i = 0; i < m_vertices.size(); i += 3 )
  {
      VertexObj* v0 = &m_vertices[m_indices[i + 0]];
      VertexObj* v1 = &m_vertices[m_indices[i + 1]];
      VertexObj* v2 = &m_vertices[m_indices[i + 2]];

      // Edges of the triangle : position delta
      nvmath::vec3f deltaPos1 = v1->pos - v0->pos;
      nvmath::vec3f deltaPos2 = v2->pos - v0->pos;

      // UV delta
      nvmath::vec3f deltaUV1 = v1->texCoord - v0->texCoord;
      nvmath::vec3f deltaUV2 = v2->texCoord - v0->texCoord;

      float r = 1.0f / (deltaUV1.x * deltaUV2.y - deltaUV1.y * deltaUV2.x);
      nvmath::vec3f tangent = (deltaPos1 * deltaUV2.y - deltaPos2 * deltaUV1.y) * r;
      //tangent = nvmath::normalize( tangent );
      nvmath::vec3f bitangent = (deltaPos2 * deltaUV1.x - deltaPos1 * deltaUV2.x) * r;
      //bitangent = nvmath::normalize( bitangent );

      v0->tangent = tangent;
      v1->tangent = tangent;
      v2->tangent = tangent;

      v0->bitangent = bitangent;
      v1->bitangent = bitangent;
      v2->bitangent = bitangent;
  }

  for ( int i = 0; i < m_vertices.size(); i += 1 )
  {
      VertexObj& v = m_vertices[i];

      // Gram-Schmidt orthogonalize
      v.tangent = nvmath::normalize( v.tangent - v.nrm * nvmath::dot( v.nrm, v.tangent ) );

      // Calculate handedness
      //if ( nvmath::dot( nvmath::cross( v.nrm, v.tangent ), v.bitangent ) < 0.0f )
      //if ( nvmath::dot( nvmath::cross( v.nrm, v.tangent ), v.bitangent ) > 0.0f )
      //{
          //v.tangent = v.tangent * -1.0f;
      //}
  }
  // ===============================================================================================
}
