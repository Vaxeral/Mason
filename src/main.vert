#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aColor;

uniform mat4 projection;
uniform mat4 view;

uniform vec3 va;
uniform vec3 vb;

uniform uint time;
out vec3 oColor;

void main()
{
    vec3 position;
    if (gl_VertexID == 1) {
        float a = (sin(float(time) / 1000.0) + 1.0) / 2.0;
        float b = 1.0 - a;
        // position = a * va + b * vb;
        position = mix(va, vb, a);
        position = normalize(position) * 5.0;
        // position = aPos;
    } else {
        position = aPos;
    }
    gl_Position = projection * view * vec4(position,  1.0);
    oColor = aColor;
}
