vf float light;


#ifdef STAGE_VERTEX
void main() {
    uint base = v_base >> 8;
    uint n = base & uint(7);
    vec3 normal = cube_normals[n];
    base = base >> 3;
    vec3 local_position = vec3(
        float((base >> (2 * CHUNK_WIDTH_BITS)) & uint(CHUNK_WIDTH - 1)),
        float((base >> (1 * CHUNK_WIDTH_BITS)) & uint(CHUNK_WIDTH - 1)),
        float((base >> (0 * CHUNK_WIDTH_BITS)) & uint(CHUNK_WIDTH - 1))
    ) + cube_positions[n * uint(4) + uint(gl_VertexID)];
    vec4 world_position = vec4(u_chunk_origin + local_position, 1);
    gl_Position = u_proj * u_view * world_position;
    light = abs(dot(normal, u_light));
}
#endif

#ifdef STAGE_FRAGMENT
void main() {
    f_color.xyz = vec3(light);
    f_color.w = 1;
}
#endif