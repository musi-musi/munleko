vf float light;
vf float fog_strength;
vf vec3 face_color;
vf vec2 uv_face;
vf vec2 uv_texture;
vf float texture_w;
flat vf float face_ao[4];

#ifdef STAGE_VERTEX
void main() {
    uint base = v_base;
    uint ao = base & 0xFFu;
    base >>= 8;
    uint n = base & 7u;
    base >>= 3;
    vec3 normal = cube_normals[n];
    vec3 local_position = vec3(
        float((base >> (2 * CHUNK_WIDTH_BITS)) & uint(CHUNK_WIDTH - 1)),
        float((base >> (1 * CHUNK_WIDTH_BITS)) & uint(CHUNK_WIDTH - 1)),
        float((base >> (0 * CHUNK_WIDTH_BITS)) & uint(CHUNK_WIDTH - 1))
    ) + cube_positions[n * uint(4) + uint(gl_VertexID)];
    vec4 world_position = vec4(u_chunk_origin + local_position, 1);
    gl_Position = u_proj * u_view * world_position;
    light = abs(dot(normal, u_light));
    vec4 camera_position = inverse(u_view) * vec4(0, 0, 0, 1);
    float dist = length(camera_position.xyz - world_position.xyz);
    dist = (dist - u_fog_start) / (u_fog_end - u_fog_start);
    dist = clamp(dist, 0, 1);
    fog_strength = pow(dist, u_fog_power);
    face_color = v_color;

    uv_face = cube_uvs_face[gl_VertexID];

    uv_texture.x = dot(world_position.xyz, cube_umat_texture[n]);
    uv_texture.y = dot(world_position.xyz, cube_vmat_texture[n]);
    uv_texture *= u_uv_scale;

    face_ao[0] = (3 - float(ao >> 0u & 0x3u)) / 3.0;
    face_ao[1] = (3 - float(ao >> 2u & 0x3u)) / 3.0;
    face_ao[2] = (3 - float(ao >> 4u & 0x3u)) / 3.0;
    face_ao[3] = (3 - float(ao >> 6u & 0x3u)) / 3.0;

    // texture_w = (float(v_texture_index) + 0.5) / float(textureSize(s_texture_atlas, 1).z);
    texture_w = float(v_texture_index);
}
#endif

#ifdef STAGE_FRAGMENT
void main() {
    float ao = mix(
        mix(face_ao[2], face_ao[3], uv_face.x),
        mix(face_ao[0], face_ao[1], uv_face.x),
        uv_face.y
    );

    vec3 texture_color = texture(s_texture_atlas, vec3(uv_texture, texture_w)).xyz;
    // vec3 color = mix(face_color * light, u_fog_color, fog_strength);
    vec3 color = mix(texture_color * face_color * mix(1, light, 0.5) * mix(1, ao, 0.5), u_fog_color, fog_strength);
    // f_color.xyz = texture_color;
    f_color.xyz = color;
    f_color.w = 1;
}
#endif