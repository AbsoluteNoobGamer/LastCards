#version 460 core
#include <flutter/runtime_effect.glsl>

// Sweeps a soft diagonal gold band across the card and loops.
// Uniform order is consumed by GoldShimmer (special_card_fx.dart):
//   setFloat 0..1 -> uSize, 2 -> uTime, 3 -> uIntensity, setImageSampler 0.
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;

  vec4 base = texture(uTexture, uv);

  // Position of the band sweeps along the top-left -> bottom-right diagonal and
  // loops every cycle. The 1.5 range lets the band travel fully off both edges.
  float diagonal = (uv.x + uv.y) * 0.5;
  float sweep = fract(uTime * 0.6) * 1.5 - 0.25;
  float dist = abs(diagonal - sweep);

  // Soft band falloff (wider center, feathered edges).
  float band = smoothstep(0.18, 0.0, dist);

  // Add gold only where the card is actually drawn (base.a > 0), scaled by
  // intensity and faded toward the card edges by the base alpha.
  vec3 gold = vec3(1.0, 0.84, 0.40);
  float mask = step(0.001, base.a) * base.a;
  vec3 shimmer = gold * band * uIntensity * mask;

  fragColor = vec4(base.rgb + shimmer, base.a);
}
