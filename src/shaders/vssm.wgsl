      const PI = 3.14159265358979323846;
      const INV_PI = 1.0/3.14159265358979323846;
      const EPSILON = 1e-6;
      struct LightSource {
        position: vec3<f32>,
        intensity: f32,
        color: vec3<f32>,
        angle: f32,
        spot: vec3<f32>,
        rayTracedShadows: u32,
      };

      struct Material {
        albedo: vec3<f32>,
        roughness: f32,
        metalness: f32,
        noiseOctave: f32,
        noiseScale: f32 
      };

      struct Camera {
        modelMat: mat4x4<f32>,
        viewMat: mat4x4<f32>,
        invViewMat: mat4x4<f32>,
        transInvViewMat: mat4x4<f32>,
        projMat: mat4x4<f32>,
        fov: f32,
        aspectRatio: f32,
        _pad: vec2<f32>
      };
      
      struct Mesh {
          posOffset: u32,
          triOffset: u32,
          numOfTriangles: u32,  
          materialIndex: u32,
      };

      struct Scene {
        camera: Camera,
        numOfMeshes: f32,
        numOfLightSources: f32,
        _pad: vec2<f32>
      };

      struct ShadowUniforms {
        lightViewProj: mat4x4<f32>,
        lightView: mat4x4<f32>,
        controlA: vec4<f32>,
        controlB: vec4<f32>,
        controlC: vec4<f32>,
        controlD: vec4<f32>,
      };

      struct ShadingSample {
        worldPosition: vec3f,
        viewPosition: vec3f, 
        normal: vec3f, 
        worldNormal: vec3f,
        material: Material,
        lightSource: LightSource, 
      };

      struct VssmAdaptiveResult {
        visibility: f32,
        litRatio: f32,
        vsmRatio: f32,
        pcfRatio: f32,
      };

      
      @group(0) @binding(0)
      var<uniform> scene : Scene;

      @group(0) @binding(1)
      var<storage, read> positions : array<f32>;

      @group(0) @binding(2)
      var<storage, read> normals : array<f32>;

      @group(0) @binding(3)
      var<storage, read> texCoords : array<f32>;

      @group(0) @binding(4)
      var<storage, read> triangles : array<u32>;

      @group(0) @binding(5)
      var<storage, read> meshes : array<Mesh>;

      @group(0) @binding(6)
      var<storage, read> materials : array<Material>;

      @group(0) @binding(7)
      var<storage, read> lightSources : array<LightSource>;

      @group(0) @binding(8)
      var<uniform> shadowUniforms : ShadowUniforms;

      @group(1) @binding(0) var albedoSampler: sampler;
      @group(1) @binding(1) var albedoTexture: texture_2d<f32>; 
      @group(1) @binding(2) var shadowSampler: sampler_comparison;
      @group(1) @binding(3) var shadowDepthTexture: texture_depth_2d;
      @group(1) @binding(4) var shadowMomentsTexture: texture_2d<f32>;
      @group(1) @binding(5) var shadowSatTexture: texture_2d<f32>;
      @group(1) @binding(6) var shadowMinMaxTexture: texture_2d<f32>;
      
      struct RasterVertexInput {
        @builtin(vertex_index) vertexIndex: u32,
        @builtin(instance_index) meshIndex: u32
      };
  
      struct RasterVertexOutput {
        @builtin(position) builtInPos : vec4f,
        @location(0) worldPosition: vec3f,
        @location(1) viewPosition: vec3f,
        @location(2) normal: vec3f,
        @location(3) texCoord: vec2f,
        @location(4) @interpolate(flat) materialIndex: u32,
      };

      fn getVertPos(vertIndex: u32) -> vec3f {
        return vec3f (positions[3*vertIndex], positions[3*vertIndex+1], positions[3*vertIndex+2]);
      }

      fn getVertNormal(vertIndex: u32) -> vec3f {
        return vec3f (normals[3*vertIndex], normals[3*vertIndex+1], normals[3*vertIndex+2]);
      }

      fn getVertTexCoord(vertIndex: u32) -> vec2f {
        return vec2f (texCoords[2*vertIndex], texCoords[2*vertIndex+1]);
      }

      fn getTriangle(triIndex: u32) -> vec3u {
        return vec3u (triangles[3*triIndex], triangles[3*triIndex+1], triangles[3*triIndex+2]);
      }





      fn sqr(x: f32) -> f32 { 
        return x*x; 
      }





      fn fade(t: vec3f) -> vec3f {
          return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
      }

      fn hash(p: vec3i) -> f32 {
          let h = p.x * 7385 + p.y * 1934 + p.z * 8349;
          return fract(sin(f32(h)) * 43758.5453);
      }

      fn grad(p: vec3i, f: vec3f) -> f32 {
          let h = hash(p)*16.0;
          let g = vec3f(
              select(-f.x, f.x, h < 8.0),
              select(-f.y, f.y, h < 4.0 || h > 12.0),
              select(-f.z, f.z, h < 2.0 || h > 10.0)
          );
          return dot(g, vec3f(1.0));
      }

      fn perlinNoise3(p: vec3f) -> f32 {
          let i = vec3i(floor(p));
          let f = fract(p);
          let u = fade(f);

          let n000 = grad(i + vec3i(0,0,0), f - vec3f(0,0,0));
          let n100 = grad(i + vec3i(1,0,0), f - vec3f(1,0,0));
          let n010 = grad(i + vec3i(0,1,0), f - vec3f(0,1,0));
          let n110 = grad(i + vec3i(1,1,0), f - vec3f(1,1,0));
          let n001 = grad(i + vec3i(0,0,1), f - vec3f(0,0,1));
          let n101 = grad(i + vec3i(1,0,1), f - vec3f(1,0,1));
          let n011 = grad(i + vec3i(0,1,1), f - vec3f(0,1,1));
          let n111 = grad(i + vec3i(1,1,1), f - vec3f(1,1,1));

          let nx00 = mix(n000, n100, u.x);
          let nx10 = mix(n010, n110, u.x);
          let nx01 = mix(n001, n101, u.x);
          let nx11 = mix(n011, n111, u.x);

          let nxy0 = mix(nx00, nx10, u.y);
          let nxy1 = mix(nx01, nx11, u.y);

          return mix(nxy0, nxy1, u.z);
      }

      fn FBM(p: vec3f, numOfOctaves: u32, scale: f32) -> f32 {
        var noise = 0f;
        var amplitude = 0.5f;
        var x = scale * p;
        for (var octave = 0u; octave < numOfOctaves; octave++) {
          noise += amplitude * perlinNoise3(x);
          amplitude *= 0.5f;
          x *= 2.f;
        }
        return noise;
      }


      fn genProceduralMaterial(material: Material, position: vec3f, texCoord: vec2f) -> Material {
        var procMat = material;
        let texAlbedo = textureSampleLevel(albedoTexture, albedoSampler, texCoord, 0);
        let noiseVal = 0.5 + 0.5 * FBM(position, u32(procMat.noiseOctave), procMat.noiseScale);
        procMat.albedo = mix (texAlbedo.rgb, procMat.albedo, noiseVal);
        procMat.roughness = noiseVal * procMat.roughness;
        return procMat;
      }





      fn attenuation(dist: f32, coneDecay: f32) -> f32 {
        return coneDecay * (1.0 / sqr(dist));
      }

      fn TrowbridgeReitzNDF(wh : vec3f, n : vec3f, roughness: f32) -> f32 {
        let alpha2 = sqr(roughness);
        return alpha2 / (PI * sqr(1.0 + (alpha2 - 1.0) * sqr(dot (n, wh))));
      }

      fn SchlickFresnel(wi: vec3f, wh: vec3f, F0: vec3f) -> vec3f {
          return F0 + (1.0 - F0) * pow(1.0 - max(0.0, dot(wi, wh)), 5.0);
      }

      fn SmithG1(w: vec3f, n : vec3f, roughness: f32) -> f32 {
        let NdotW = dot(n,w);
        let alpha2 = sqr (roughness);
        return (2.0 * NdotW) / (NdotW + sqrt(alpha2 + (1-alpha2)*sqr(NdotW)));
      }
      
      fn SmithGGX(wi : vec3f, wo : vec3f, n: vec3f, roughness : f32) -> f32 {
        return SmithG1(wi, n, roughness) * SmithG1(wo, n, roughness);
      }
      
      fn BRDF(
        wi: vec3f, 
        wo: vec3f, 
        n: vec3f, 
        albedo: vec3f, 
        roughness: f32, 
        metalness: f32
      ) -> vec3f {
        let diffuseColor = albedo * (1.0 - metalness);
        let specularColor = mix(vec3f(0.08), albedo, metalness);
        let alpha = roughness * roughness;
        let NdotL = max(0.0, dot(n, wi));
        let NdotV = max(0.0, dot(n, wo));

        if (NdotL <= 0.0) {
          return vec3f (0.0); 
        }
        
        let wh = normalize(wi + wo);
        let NdotH = max(0.0, dot(n, wh));
        let VdotH = max(0.0, dot(wo, wh));
        

        let D = TrowbridgeReitzNDF(wh, n, alpha);


        let F = SchlickFresnel(wi, wh, specularColor);


        let G = SmithGGX(wi, wo, n, alpha);


        let fd = diffuseColor * (vec3f(1.0) - specularColor) / PI;
        let fs = F * D * G / max(4.0 * NdotL * NdotV, 0.0001);
  
        return (fd + fs);
      }
      

      fn lightShade(shadingSample: ShadingSample) -> vec3f {
        let light = shadingSample.lightSource;
        let cam = scene.camera;
        let viewLightPos = cam.viewMat * vec4(light.position, 1.0);
        let viewLightTarget = cam.viewMat * vec4(light.spot, 1.0);
        let viewLightDir = normalize(viewLightTarget.xyz - viewLightPos.xyz);
        var wi = viewLightPos.xyz - shadingSample.viewPosition;
        var wo = normalize (-shadingSample.viewPosition);
        let di = length(wi);
        wi = normalize(wi);
        var spotConeDecay = dot(-wi, viewLightDir) - light.angle;
        
        if (spotConeDecay <= 0.0) {
          return vec3f(0.0);
        }
        let att = attenuation(di, spotConeDecay);
        let ir = light.color * light.intensity * att;
        let m = shadingSample.material;
        let fr = BRDF(wi, wo, shadingSample.normal, m.albedo, m.roughness, m.metalness);
        let colorResponse = ir * fr * max (0.0, dot (wi, shadingSample.normal));
        return colorResponse;
      }

      fn loadShadowDepth(shadowUV: vec2f) -> f32 {
        let dimsU = textureDimensions(shadowDepthTexture);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        let texel = clamp(vec2i(shadowUV * vec2f(dims)), vec2i(0), dims - vec2i(1));
        return textureLoad(shadowDepthTexture, texel, 0);
      }

      fn compareShadowDepth(shadowUV: vec2f, compareDepth: f32) -> f32 {
        if (compareDepth <= loadShadowDepth(shadowUV)) {
          return 1.0;
        }
        return 0.0;
      }

      fn compareShadowDepthBilinear(shadowUV: vec2f, compareDepth: f32) -> f32 {
        let dimsU = textureDimensions(shadowDepthTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let texelCoord = shadowUV * dims - vec2f(0.5);
        let baseCoord = floor(texelCoord);
        let fracCoord = fract(texelCoord);
        let uv00 = (baseCoord + vec2f(0.5, 0.5)) / dims;
        let uv10 = (baseCoord + vec2f(1.5, 0.5)) / dims;
        let uv01 = (baseCoord + vec2f(0.5, 1.5)) / dims;
        let uv11 = (baseCoord + vec2f(1.5, 1.5)) / dims;
        let s00 = compareShadowDepth(uv00, compareDepth);
        let s10 = compareShadowDepth(uv10, compareDepth);
        let s01 = compareShadowDepth(uv01, compareDepth);
        let s11 = compareShadowDepth(uv11, compareDepth);
        let sx0 = mix(s00, s10, fracCoord.x);
        let sx1 = mix(s01, s11, fracCoord.x);
        return mix(sx0, sx1, fracCoord.y);
      }

      fn hash21(p: vec2f) -> f32 {
        let h = dot(p, vec2f(127.1, 311.7));
        return fract(sin(h) * 43758.5453123);
      }

      fn loadShadowMoments(shadowUV: vec2f) -> vec2f {
        let clampedUV = clamp(shadowUV, vec2f(0.001), vec2f(0.999));
        return denormalizeMomentsFromUnit(textureSampleLevel(shadowMomentsTexture, albedoSampler, clampedUV, 0.0).xy);
      }

      fn loadShadowMomentsPoint(shadowUV: vec2f) -> vec2f {
        let dimsU = textureDimensions(shadowMomentsTexture);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        let texel = clamp(vec2i(shadowUV * vec2f(dims)), vec2i(0), dims - vec2i(1));
        return denormalizeMomentsFromUnit(textureLoad(shadowMomentsTexture, texel, 0).xy);
      }

      fn normalizeLinearDepthToUnit(depth: f32) -> f32 {
        let nearPlane = shadowUniforms.controlB.z;
        let farPlane = shadowUniforms.controlB.w;
        return clamp((depth - nearPlane) / max(farPlane - nearPlane, 0.0001), 0.0, 1.0);
      }

      fn denormalizeMomentsFromUnit(normMoments: vec2f) -> vec2f {
        let nearPlane = shadowUniforms.controlB.z;
        let farPlane = shadowUniforms.controlB.w;
        let depthRange = max(farPlane - nearPlane, 0.0001);
        let mean = nearPlane + normMoments.x * depthRange;
        let secondMoment = nearPlane * nearPlane + 2.0 * nearPlane * depthRange * normMoments.x + depthRange * depthRange * normMoments.y;
        return vec2f(mean, secondMoment);
      }

      fn loadShadowSAT(coord: vec2i) -> vec2f {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        if (coord.x < 0 || coord.y < 0) {
          return vec2f(0.0);
        }
        let texel = clamp(coord, vec2i(0), dims - vec2i(1));
        return textureLoad(shadowSatTexture, texel, 0).xy;
      }

      fn loadShadowSATLinear(coord: vec2f) -> vec2f {
        let base = floor(coord);
        let frac = fract(coord);
        let c00 = loadShadowSAT(vec2i(base));
        let c10 = loadShadowSAT(vec2i(base) + vec2i(1, 0));
        let c01 = loadShadowSAT(vec2i(base) + vec2i(0, 1));
        let c11 = loadShadowSAT(vec2i(base) + vec2i(1, 1));
        let cx0 = mix(c00, c10, frac.x);
        let cx1 = mix(c01, c11, frac.x);
        return mix(cx0, cx1, frac.y);
      }

      fn sampleShadowSATUv(shadowUV: vec2f) -> vec2f {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let coord = shadowUV * dims - vec2f(0.5);
        return loadShadowSATLinear(coord);
      }

      fn decodeShadowSatAverage(normAverage: vec2f) -> vec2f {
        return denormalizeMomentsFromUnit(normAverage);
      }

      fn averageShadowMomentsSatUv(minUV: vec2f, maxUV: vec2f) -> vec2f {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let clampedMin = clamp(minUV, vec2f(0.0), vec2f(1.0));
        let clampedMax = clamp(max(maxUV, clampedMin + vec2f(1e-5)), vec2f(0.0), vec2f(1.0));
        let a = sampleShadowSATUv(clampedMin);
        let b = sampleShadowSATUv(vec2f(clampedMax.x, clampedMin.y));
        let c = sampleShadowSATUv(vec2f(clampedMin.x, clampedMax.y));
        let d = sampleShadowSATUv(clampedMax);
        let extent = max((clampedMax - clampedMin) * dims, vec2f(1e-4));
        let area = extent.x * extent.y;
        let average = (d + a - b - c) / area;
        return decodeShadowSatAverage(average);
      }

      fn loadShadowMinMax(coord: vec2i, level: i32) -> vec2f {
        let dimsU = textureDimensions(shadowMinMaxTexture, level);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        if (coord.x < 0 || coord.y < 0) {
          return vec2f(shadowUniforms.controlB.w, shadowUniforms.controlB.z);
        }
        let texel = clamp(coord, vec2i(0), dims - vec2i(1));
        return textureLoad(shadowMinMaxTexture, texel, level).xy;
      }

      fn filterShadowMoments(shadowUV: vec2f, radius: i32) -> vec2f {
        let texelSize = 1.0 / shadowUniforms.controlA.x;
        var moments = vec2f(0.0);
        var count = 0.0;
        for (var y = -radius; y <= radius; y++) {
          for (var x = -radius; x <= radius; x++) {
            let sampleUV = shadowUV + vec2f(f32(x), f32(y)) * texelSize;
            if (sampleUV.x > 0.0 && sampleUV.x < 1.0 && sampleUV.y > 0.0 && sampleUV.y < 1.0) {
              moments += loadShadowMoments(sampleUV);
              count += 1.0;
            }
          }
        }
        return moments / max(count, 1.0);
      }

      fn filterShadowMomentsPoint(shadowUV: vec2f, radius: i32) -> vec2f {
        if (radius <= 0) {
          return loadShadowMomentsPoint(shadowUV);
        }
        let texelSize = 1.0 / shadowUniforms.controlA.x;
        var moments = vec2f(0.0);
        var count = 0.0;
        for (var y = -radius; y <= radius; y++) {
          for (var x = -radius; x <= radius; x++) {
            let sampleUV = shadowUV + vec2f(f32(x), f32(y)) * texelSize;
            if (sampleUV.x > 0.0 && sampleUV.x < 1.0 && sampleUV.y > 0.0 && sampleUV.y < 1.0) {
              moments += loadShadowMomentsPoint(sampleUV);
              count += 1.0;
            }
          }
        }
        return moments / max(count, 1.0);
      }

      fn filterShadowMomentsSAT(shadowUV: vec2f, radius: i32) -> vec2f {
        if (radius <= 0) {
          return loadShadowMoments(shadowUV);
        }
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let radiusUV = vec2f(f32(radius)) / dims;
        return averageShadowMomentsSatUv(shadowUV - radiusUV, shadowUV + radiusUV);
      }

      fn sampleShadowMinMaxRect(shadowUV: vec2f, radius: i32) -> vec2f {
        let baseDimsU = textureDimensions(shadowMinMaxTexture, 0);
        let baseDims = vec2i(i32(baseDimsU.x), i32(baseDimsU.y));
        let center = clamp(vec2i(shadowUV * vec2f(baseDims)), vec2i(0), baseDims - vec2i(1));
        let minCoord = max(center - vec2i(radius), vec2i(0));
        let maxCoord = min(center + vec2i(radius), baseDims - vec2i(1));
        let kernelSize = max(maxCoord - minCoord + vec2i(1), vec2i(1));
        let kernelDiameter = max(kernelSize.x, kernelSize.y);
        let maxLevel = i32(max(round(shadowUniforms.controlD.z) - 1.0, 0.0));
        let level = clamp(i32(floor(log2(f32(max(kernelDiameter, 1))))), 0, maxLevel);
        let levelScale = i32(1u << u32(level));
        let levelMin = minCoord / levelScale;
        let levelMax = maxCoord / levelScale;
        var minDepth = shadowUniforms.controlB.w;
        var maxDepth = shadowUniforms.controlB.z;
        for (var y = 0; y < 4; y = y + 1) {
          let sy = levelMin.y + y;
          if (sy > levelMax.y) {
            continue;
          }
          for (var x = 0; x < 4; x = x + 1) {
            let sx = levelMin.x + x;
            if (sx > levelMax.x) {
              continue;
            }
            let depthRange = loadShadowMinMax(vec2i(sx, sy), level);
            minDepth = min(minDepth, depthRange.x);
            maxDepth = max(maxDepth, depthRange.y);
          }
        }
        return vec2f(minDepth, maxDepth);
      }

      fn sampleShadowMinMaxRectEdges(minEdge: vec2f, maxEdge: vec2f) -> vec2f {
        let baseDimsU = textureDimensions(shadowMinMaxTexture, 0);
        let baseDims = vec2i(i32(baseDimsU.x), i32(baseDimsU.y));
        let clampedMin = clamp(minEdge, vec2f(0.0), vec2f(f32(baseDims.x), f32(baseDims.y)));
        let clampedMax = clamp(maxEdge, vec2f(0.0), vec2f(f32(baseDims.x), f32(baseDims.y)));
        let minCoord = clamp(vec2i(i32(floor(clampedMin.x)), i32(floor(clampedMin.y))), vec2i(0), baseDims - vec2i(1));
        let maxCoord = clamp(vec2i(i32(ceil(clampedMax.x)) - 1, i32(ceil(clampedMax.y)) - 1), vec2i(0), baseDims - vec2i(1));
        let kernelSize = max(maxCoord - minCoord + vec2i(1), vec2i(1));
        let kernelDiameter = max(kernelSize.x, kernelSize.y);
        let maxLevel = i32(max(round(shadowUniforms.controlD.z) - 1.0, 0.0));
        let level = clamp(i32(floor(log2(f32(max(kernelDiameter, 1))))), 0, maxLevel);
        let levelScale = i32(1u << u32(level));
        let levelMin = minCoord / levelScale;
        let levelMax = maxCoord / levelScale;
        var minDepth = shadowUniforms.controlB.w;
        var maxDepth = shadowUniforms.controlB.z;
        for (var y = 0; y < 4; y = y + 1) {
          let sy = levelMin.y + y;
          if (sy > levelMax.y) {
            continue;
          }
          for (var x = 0; x < 4; x = x + 1) {
            let sx = levelMin.x + x;
            if (sx > levelMax.x) {
              continue;
            }
            let depthRange = loadShadowMinMax(vec2i(sx, sy), level);
            minDepth = min(minDepth, depthRange.x);
            maxDepth = max(maxDepth, depthRange.y);
          }
        }
        return vec2f(minDepth, maxDepth);
      }

      fn classifyVssmKernelWithHsm(shadowUV: vec2f, radius: i32, linearCompareDepth: f32) -> i32 {
        let depthRange = sampleShadowMinMaxRect(shadowUV, radius);
        if (linearCompareDepth <= depthRange.x) {
          return 1;
        }
        if (linearCompareDepth > depthRange.y) {
          return -1;
        }
        return 0;
      }

      fn reduceLightBleeding(visibility: f32, amount: f32) -> f32 {
        return clamp((visibility - amount) / max(1.0 - amount, 0.0001), 0.0, 1.0);
      }

      fn filterShadowContactPCF(shadowCoord: vec3f, compareDepth: f32, radius: i32) -> f32 {
        let texelSize = 1.0 / shadowUniforms.controlA.x;
        var visibility = 0.0;
        for (var sy = 0; sy < 3; sy = sy + 1) {
          for (var sx = 0; sx < 3; sx = sx + 1) {
            let local = (vec2f(f32(sx), f32(sy)) - vec2f(1.0)) * f32(radius) * texelSize;
            let sampleUV = clamp(shadowCoord.xy + local, vec2f(0.001), vec2f(0.999));
            visibility += compareShadowDepthBilinear(sampleUV, compareDepth);
          }
        }
        return visibility / 9.0;
      }

      fn chebyshevUpperBoundRaw(moments: vec2f, compareDepth: f32) -> f32 {
        let mean = moments.x;
        if (compareDepth <= mean) {
          return 1.0;
        }
        var variance = moments.y - mean * mean;
        variance = max(variance, 0.00002);
        let delta = compareDepth - mean;
        return clamp(variance / (variance + delta * delta), 0.0, 1.0);
      }

      fn chebyshevUpperBound(moments: vec2f, compareDepth: f32) -> f32 {
        let upperBound = chebyshevUpperBoundRaw(moments, compareDepth);
        return reduceLightBleeding(upperBound, shadowUniforms.controlC.z);
      }

      fn momentVariance(moments: vec2f) -> f32 {
        return max(moments.y - moments.x * moments.x, 0.0);
      }

      fn estimateBlockerDepthVSSM(moments: vec2f, compareDepth: f32) -> vec2f {
        let mean = moments.x;
        let litFraction = chebyshevUpperBoundRaw(moments, compareDepth);
        let blockedFraction = 1.0 - litFraction;
        if (blockedFraction <= 0.001 || litFraction >= 0.999 || compareDepth <= mean) {
          return vec2f(0.0, 0.0);
        }
        let blockerDepth = (mean - litFraction * compareDepth) / blockedFraction;
        if (blockerDepth != blockerDepth || blockerDepth <= shadowUniforms.controlB.z || blockerDepth >= compareDepth) {
          return vec2f(0.0, 0.0);
        }
        return vec2f(blockerDepth, blockedFraction);
      }

      fn linearizeShadowDepth(depth: f32) -> f32 {
        let nearPlane = shadowUniforms.controlB.z;
        let farPlane = shadowUniforms.controlB.w;
        let denom = max(farPlane - depth * (farPlane - nearPlane), 0.0001);
        return (nearPlane * farPlane) / denom;
      }

      fn averageBlockerDepth(shadowCoord: vec3f, receiverLinearDepth: f32, linearDepthBias: f32, searchRadius: i32) -> vec2f {
        let texelSize = 1.0 / shadowUniforms.controlA.x;
        var blockerDepthSum = 0.0;
        var blockerCount = 0.0;
        for (var y = -12; y <= 12; y++) {
          for (var x = -12; x <= 12; x++) {
            if (abs(x) <= searchRadius && abs(y) <= searchRadius) {
              let sampleUV = shadowCoord.xy + vec2f(f32(x), f32(y)) * texelSize;
              if (sampleUV.x > 0.0 && sampleUV.x < 1.0 && sampleUV.y > 0.0 && sampleUV.y < 1.0) {
                let sampleDepth = loadShadowDepth(sampleUV);
                let linearSampleDepth = linearizeShadowDepth(sampleDepth);
                if (linearSampleDepth < receiverLinearDepth - linearDepthBias) {
                  blockerDepthSum += linearSampleDepth;
                  blockerCount += 1.0;
                }
              }
            }
          }
        }
        return vec2f(blockerDepthSum, blockerCount);
      }

      fn filterShadow(shadowCoord: vec3f, compareDepth: f32, radius: i32) -> f32 {
        let texelSize = 1.0 / shadowUniforms.controlA.x;
        var visibility = 0.0;
        var count = 0.0;
        for (var y = -12; y <= 12; y++) {
          for (var x = -12; x <= 12; x++) {
            if (abs(x) <= radius && abs(y) <= radius) {
              visibility += compareShadowDepth(shadowCoord.xy + vec2f(f32(x), f32(y)) * texelSize, compareDepth);
              count += 1.0;
            }
          }
        }
        return visibility / max(count, 1.0);
      }

      fn averageShadowMomentsRectSmall(nodeMin: vec2i, nodeMax: vec2i) -> vec2f {
        let dimsU = textureDimensions(shadowMomentsTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        var sum = vec2f(0.0);
        var count = 0.0;
        for (var ly = 0; ly < 8; ly = ly + 1) {
          let y = nodeMin.y + ly;
          if (y > nodeMax.y) { break; }
          for (var lx = 0; lx < 8; lx = lx + 1) {
            let x = nodeMin.x + lx;
            if (x > nodeMax.x) { break; }
            let uv = (vec2f(f32(x), f32(y)) + vec2f(0.5)) / dims;
            sum += loadShadowMomentsPoint(uv);
            count += 1.0;
          }
        }
        return sum / max(count, 1.0);
      }

      fn averageShadowMomentsRect(minCoord: vec2i, maxCoord: vec2i) -> vec2f {
        return averageShadowMomentsRectFloat(vec2f(minCoord), vec2f(maxCoord));
      }

      fn averageShadowMomentsRectFloat(minCoord: vec2f, maxCoord: vec2f) -> vec2f {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let clampedMax = max(maxCoord, minCoord);
        let minUV = minCoord / dims;
        let maxUV = (clampedMax + vec2f(1.0)) / dims;
        return averageShadowMomentsSatUv(minUV, maxUV);
      }

      fn averageShadowMomentsRectEdges(minEdge: vec2f, maxEdge: vec2f) -> vec2f {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let rectMin = clamp(minEdge, vec2f(0.0), dims);
        let rectMax = clamp(max(maxEdge, rectMin + vec2f(1e-4)), vec2f(0.0), dims);
        return averageShadowMomentsSatUv(rectMin / dims, rectMax / dims);
      }

      fn sampleRectDepthBlockers(minCoord: vec2i, maxCoord: vec2i, receiverLinearDepth: f32, linearDepthBias: f32) -> vec2f {
        let dimsU = textureDimensions(shadowDepthTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let extent = vec2f(maxCoord - minCoord + vec2i(1));
        var blockerDepthSum = 0.0;
        var blockerCount = 0.0;
        for (var sy = 0; sy < 3; sy = sy + 1) {
          for (var sx = 0; sx < 3; sx = sx + 1) {
            let sampleTexel = vec2i(
              minCoord.x + min(i32(floor((f32(sx) + 0.5) * extent.x / 3.0)), maxCoord.x - minCoord.x),
              minCoord.y + min(i32(floor((f32(sy) + 0.5) * extent.y / 3.0)), maxCoord.y - minCoord.y)
            );
            let sampleUV = (vec2f(sampleTexel) + vec2f(0.5)) / dims;
            let sampleDepth = loadShadowDepth(sampleUV);
            let linearSampleDepth = linearizeShadowDepth(sampleDepth);
            if (linearSampleDepth < receiverLinearDepth - linearDepthBias) {
              blockerDepthSum += linearSampleDepth;
              blockerCount += 1.0;
            }
          }
        }
        return vec2f(blockerDepthSum, blockerCount);
      }

      fn sampleRectVisibilityExactPCFEdges(minEdge: vec2f, maxEdge: vec2f, receiverLinearDepth: f32, linearDepthBias: f32) -> f32 {
        let dimsU = textureDimensions(shadowDepthTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let rectMin = clamp(minEdge, vec2f(0.0), vec2f(dimsU));
        let rectMax = clamp(max(maxEdge, rectMin + vec2f(1e-4)), vec2f(0.0), vec2f(dimsU));
        let minTexel = clamp(vec2i(floor(rectMin)), vec2i(0), vec2i(dimsU) - vec2i(1));
        let maxTexel = clamp(vec2i(ceil(rectMax) - vec2f(1.0)), vec2i(0), vec2i(dimsU) - vec2i(1));
        var visibility = 0.0;
        var weightedArea = 0.0;
        for (var sy = 0; sy < 64; sy = sy + 1) {
          let y = minTexel.y + sy;
          if (y > maxTexel.y) {
            break;
          }
          let texelMinY = f32(y);
          let texelMaxY = f32(y + 1);
          let overlapY = max(0.0, min(rectMax.y, texelMaxY) - max(rectMin.y, texelMinY));
          if (overlapY <= 0.0) {
            continue;
          }
          for (var sx = 0; sx < 64; sx = sx + 1) {
            let x = minTexel.x + sx;
            if (x > maxTexel.x) {
              break;
            }
            let texelMinX = f32(x);
            let texelMaxX = f32(x + 1);
            let overlapX = max(0.0, min(rectMax.x, texelMaxX) - max(rectMin.x, texelMinX));
            let weight = overlapX * overlapY;
            if (weight <= 0.0) {
              continue;
            }
            let sampleUV = (vec2f(f32(x), f32(y)) + vec2f(0.5)) / dims;
            let sampleDepth = loadShadowDepth(sampleUV);
            let linearSampleDepth = linearizeShadowDepth(sampleDepth);
            let lit = select(0.0, 1.0, receiverLinearDepth - linearDepthBias <= linearSampleDepth);
            visibility += lit * weight;
            weightedArea += weight;
          }
        }
        return visibility / max(weightedArea, 1e-4);
      }

      fn sampleRectVisibilityContactPCF(minCoord: vec2i, maxCoord: vec2i, compareDepth: f32) -> f32 {
        let dimsU = textureDimensions(shadowDepthTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let extent = vec2f(maxCoord - minCoord + vec2i(1));
        var visibility = 0.0;
        for (var sy = 0; sy < 3; sy = sy + 1) {
          for (var sx = 0; sx < 3; sx = sx + 1) {
            let localUV = vec2f((f32(sx) + 0.5) / 3.0, (f32(sy) + 0.5) / 3.0);
            let sampleUV = clamp((vec2f(minCoord) + localUV * extent) / dims, vec2f(0.001), vec2f(0.999));
            visibility += compareShadowDepthBilinear(sampleUV, compareDepth);
          }
        }
        return visibility / 9.0;
      }

      fn estimateBlockerDepthVSSMSubdivided(shadowUV: vec2f, compareDepth: f32, receiverLinearDepth: f32, linearDepthBias: f32, searchRadius: i32) -> vec2f {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        let centerF = clamp(shadowUV * vec2f(dims) - vec2f(0.5), vec2f(0.0), vec2f(dims - vec2i(1)));
        let center = clamp(vec2i(floor(centerF)), vec2i(0), dims - vec2i(1));
        let centerFrac = fract(centerF);
        let minCoord = max(center - vec2i(searchRadius), vec2i(0));
        let maxCoord = min(center + vec2i(searchRadius), dims - vec2i(1));
        let extent = maxCoord - minCoord + vec2i(1);
        let subdivision = i32(clamp(round(shadowUniforms.controlD.x), 2.0, 8.0));
        let varianceThreshold = max(shadowUniforms.controlD.y, 0.0);
        let blockerSafetyFloor = max(shadowUniforms.controlD.w * 0.5, linearDepthBias * 4.0);
        let classificationEpsilon = max(shadowUniforms.controlD.w * 0.25, linearDepthBias * 2.0);
        var vsmEx = 0.0;
        var vsmEx2 = 0.0;
        var vsmArea = 0.0;
        var pcfBlockerSum = 0.0;
        var pcfBlockerCount = 0.0;
        for (var subY = 0; subY < 8; subY = subY + 1) {
          if (subY >= subdivision) {
            continue;
          }
          for (var subX = 0; subX < 8; subX = subX + 1) {
            if (subX >= subdivision) {
              continue;
            }
            let subMin = vec2i(
              minCoord.x + (extent.x * subX) / subdivision,
              minCoord.y + (extent.y * subY) / subdivision
            );
            let subMax = vec2i(
              minCoord.x + (extent.x * (subX + 1)) / subdivision - 1,
              minCoord.y + (extent.y * (subY + 1)) / subdivision - 1
            );
            if (subMax.x < subMin.x || subMax.y < subMin.y) {
              continue;
            }
            let subExtent = subMax - subMin + vec2i(1);
            let subArea = f32(subExtent.x * subExtent.y);
            let subMoments = select(
              averageShadowMomentsRectFloat(vec2f(subMin) + centerFrac, vec2f(subMax) + centerFrac),
              averageShadowMomentsRectSmall(subMin, subMax),
              subExtent.x <= 8 && subExtent.y <= 8
            );
            let subVariance = momentVariance(subMoments);
            let subDepthDelta = compareDepth - subMoments.x;
            let blockerSafetyMargin = max(blockerSafetyFloor, 2.0 * sqrt(max(subVariance, 0.0)));
            if (subVariance <= varianceThreshold) {
              if (subExtent.x <= 8 && subExtent.y <= 8 && subMoments.x >= compareDepth - classificationEpsilon) {
                continue;
              }
              if (subDepthDelta > blockerSafetyMargin) {
                vsmEx += subMoments.x * subArea;
                vsmEx2 += subMoments.y * subArea;
                vsmArea += subArea;
              } else {
                let blockerSamples = sampleRectDepthBlockers(subMin, subMax, receiverLinearDepth, linearDepthBias);
                pcfBlockerSum += blockerSamples.x;
                pcfBlockerCount += blockerSamples.y;
              }
            } else {
              let blockerSamples = sampleRectDepthBlockers(subMin, subMax, receiverLinearDepth, linearDepthBias);
              pcfBlockerSum += blockerSamples.x;
              pcfBlockerCount += blockerSamples.y;
            }
          }
        }
        var blockerDepthWeighted = 0.0;
        var blockerWeight = 0.0;
        if (vsmArea > 0.0) {
          let groupedMoments = vec2f(vsmEx / vsmArea, vsmEx2 / vsmArea);
          let groupedEstimate = estimateBlockerDepthVSSM(groupedMoments, compareDepth);
          if (groupedEstimate.x > 0.0 && groupedEstimate.y > 0.0) {
            let groupedBlockedArea = groupedEstimate.y * vsmArea;
            blockerDepthWeighted += groupedEstimate.x * groupedBlockedArea;
            blockerWeight += groupedBlockedArea;
          }
        }
        if (pcfBlockerCount > 0.0) {
          blockerDepthWeighted += pcfBlockerSum;
          blockerWeight += pcfBlockerCount;
        }
        if (blockerWeight <= 0.0) {
          return vec2f(0.0, 0.0);
        }
        return vec2f(blockerDepthWeighted / blockerWeight, blockerWeight);
      }

      fn estimateBlockerDepthVSSMPaper(shadowUV: vec2f, compareDepth: f32, receiverLinearDepth: f32, linearDepthBias: f32, searchRadius: i32) -> vec2f {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        let center = clamp(vec2i(floor(clamp(shadowUV * vec2f(dims) - vec2f(0.5), vec2f(0.0), vec2f(dims - vec2i(1))))), vec2i(0), dims - vec2i(1));
        let minCoord = max(center - vec2i(searchRadius), vec2i(0));
        let maxCoord = min(center + vec2i(searchRadius), dims - vec2i(1));
        let varianceThreshold = max(shadowUniforms.controlD.y, 0.0);
        let kernelMoments = averageShadowMomentsRect(minCoord, maxCoord);
        if (kernelMoments.x < compareDepth && momentVariance(kernelMoments) <= varianceThreshold) {
          return estimateBlockerDepthVSSM(kernelMoments, compareDepth);
        }
        let extent = maxCoord - minCoord + vec2i(1);
        let subdivision = i32(clamp(round(shadowUniforms.controlD.x), 2.0, 8.0));
        var blockerDepthWeighted = 0.0;
        var blockerWeight = 0.0;
        for (var subY = 0; subY < 8; subY = subY + 1) {
          if (subY >= subdivision) {
            continue;
          }
          for (var subX = 0; subX < 8; subX = subX + 1) {
            if (subX >= subdivision) {
              continue;
            }
            let subMin = vec2i(
              minCoord.x + (extent.x * subX) / subdivision,
              minCoord.y + (extent.y * subY) / subdivision
            );
            let subMax = vec2i(
              minCoord.x + (extent.x * (subX + 1)) / subdivision - 1,
              minCoord.y + (extent.y * (subY + 1)) / subdivision - 1
            );
            if (subMax.x < subMin.x || subMax.y < subMin.y) {
              continue;
            }
            let subMoments = averageShadowMomentsRect(subMin, subMax);
            let subVariance = momentVariance(subMoments);
            if (subMoments.x >= compareDepth) {
              continue;
            }
            let subArea = f32((subMax.x - subMin.x + 1) * (subMax.y - subMin.y + 1));
            if (subVariance > varianceThreshold) {
              let blockerSamples = sampleRectDepthBlockers(subMin, subMax, receiverLinearDepth, linearDepthBias);
              blockerDepthWeighted += blockerSamples.x;
              blockerWeight += blockerSamples.y;
            } else {
              let blockerEstimate = estimateBlockerDepthVSSM(subMoments, compareDepth);
              if (blockerEstimate.x <= 0.0 || blockerEstimate.y <= 0.0) {
                continue;
              }
              let blockedArea = blockerEstimate.y * subArea;
              blockerDepthWeighted += blockerEstimate.x * blockedArea;
              blockerWeight += blockedArea;
            }
          }
        }
        if (blockerWeight <= 0.0) {
          return vec2f(0.0, 0.0);
        }
        return vec2f(blockerDepthWeighted / blockerWeight, blockerWeight);
      }

      fn filterShadowVSSMPaperResult(shadowCoord: vec3f, compareDepth: f32, linearCompareDepth: f32, filterRadius: i32) -> VssmAdaptiveResult {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        let center = clamp(vec2i(floor(clamp(shadowCoord.xy * vec2f(dims) - vec2f(0.5), vec2f(0.0), vec2f(dims - vec2i(1))))), vec2i(0), dims - vec2i(1));
        let minCoord = max(center - vec2i(filterRadius), vec2i(0));
        let maxCoord = min(center + vec2i(filterRadius), dims - vec2i(1));
        let varianceThreshold = max(shadowUniforms.controlD.y, 0.0);
        let kernelMoments = averageShadowMomentsRect(minCoord, maxCoord);
        var result: VssmAdaptiveResult;
        if (kernelMoments.x < linearCompareDepth && momentVariance(kernelMoments) <= varianceThreshold) {
          result.visibility = chebyshevUpperBound(kernelMoments, linearCompareDepth);
          result.litRatio = 0.0;
          result.vsmRatio = 1.0;
          result.pcfRatio = 0.0;
          return result;
        }
        let extent = maxCoord - minCoord + vec2i(1);
        let subdivision = i32(clamp(round(shadowUniforms.controlD.x), 2.0, 8.0));
        var visibilityWeighted = 0.0;
        var totalArea = 0.0;
        var litArea = 0.0;
        var vsmVisibilityWeighted = 0.0;
        var vsmArea = 0.0;
        var pcfVisibilityWeighted = 0.0;
        var pcfArea = 0.0;
        for (var subY = 0; subY < 8; subY = subY + 1) {
          if (subY >= subdivision) {
            continue;
          }
          for (var subX = 0; subX < 8; subX = subX + 1) {
            if (subX >= subdivision) {
              continue;
            }
            let subMin = vec2i(
              minCoord.x + (extent.x * subX) / subdivision,
              minCoord.y + (extent.y * subY) / subdivision
            );
            let subMax = vec2i(
              minCoord.x + (extent.x * (subX + 1)) / subdivision - 1,
              minCoord.y + (extent.y * (subY + 1)) / subdivision - 1
            );
            if (subMax.x < subMin.x || subMax.y < subMin.y) {
              continue;
            }
            let subArea = f32((subMax.x - subMin.x + 1) * (subMax.y - subMin.y + 1));
            let subMoments = averageShadowMomentsRect(subMin, subMax);
            let subVariance = momentVariance(subMoments);
            totalArea += subArea;
            if (subMoments.x >= linearCompareDepth) {
              litArea += subArea;
              visibilityWeighted += subArea;
            } else {
              let subVisibility = select(
                chebyshevUpperBound(subMoments, linearCompareDepth),
                sampleRectVisibilityContactPCF(subMin, subMax, compareDepth),
                subVariance > varianceThreshold
              );
              if (subVariance > varianceThreshold) {
                pcfVisibilityWeighted += subVisibility * subArea;
                pcfArea += subArea;
              } else {
                vsmVisibilityWeighted += subVisibility * subArea;
                vsmArea += subArea;
              }
              visibilityWeighted += subVisibility * subArea;
            }
          }
        }
        if (totalArea <= 0.0) {
          result.visibility = 1.0;
          result.litRatio = 1.0;
          result.vsmRatio = 0.0;
          result.pcfRatio = 0.0;
          return result;
        }
        result.visibility = visibilityWeighted / totalArea;
        result.litRatio = litArea / totalArea;
        result.vsmRatio = vsmArea / totalArea;
        result.pcfRatio = pcfArea / totalArea;
        return result;
      }

      fn filterShadowVSSMAdaptiveResult(shadowCoord: vec3f, compareDepth: f32, linearCompareDepth: f32, linearDepthBias: f32, filterRadius: f32) -> VssmAdaptiveResult {
        let dimsU = textureDimensions(shadowSatTexture);
        let dims = vec2i(i32(dimsU.x), i32(dimsU.y));
        let centerF = clamp(shadowCoord.xy * vec2f(dims) - vec2f(0.5), vec2f(0.0), vec2f(dims - vec2i(1)));
        let rectMinEdge = clamp(centerF - vec2f(filterRadius), vec2f(0.0), vec2f(dims));
        let rectMaxEdge = clamp(centerF + vec2f(filterRadius) + vec2f(1.0), rectMinEdge + vec2f(1e-4), vec2f(dims));
        let minCoord = clamp(vec2i(floor(rectMinEdge)), vec2i(0), dims - vec2i(1));
        let maxCoord = clamp(vec2i(ceil(rectMaxEdge) - vec2f(1.0)), vec2i(0), dims - vec2i(1));
        let varianceThreshold = max(shadowUniforms.controlD.y, 0.0);
        let contactThreshold = max(shadowUniforms.controlD.w, 0.0001);
        let pcfLinearDepthBias = linearDepthBias * 1.5;
        let maxDepth = 4;
        var minStack: array<vec2i, 341>;
        var maxStack: array<vec2i, 341>;
        var depthStack: array<i32, 341>;
        var stackSize = 1;
        minStack[0] = minCoord;
        maxStack[0] = maxCoord;
        depthStack[0] = 0;
        var vsmVisibilityWeighted = 0.0;
        var vsmArea = 0.0;
        var litArea = 0.0;
        var pcfVisibilityWeighted = 0.0;
        var pcfArea = 0.0;
        loop {
          if (stackSize <= 0) {
            break;
          }
          stackSize = stackSize - 1;
          let nodeMin = minStack[stackSize];
          let nodeMax = maxStack[stackSize];
          let nodeDepth = depthStack[stackSize];
          if (nodeMax.x < nodeMin.x || nodeMax.y < nodeMin.y) {
            continue;
          }
          let nodeMinEdge = max(vec2f(nodeMin), rectMinEdge);
          let nodeMaxEdge = min(vec2f(nodeMax + vec2i(1)), rectMaxEdge);
          let nodeArea = max(nodeMaxEdge.x - nodeMinEdge.x, 0.0) * max(nodeMaxEdge.y - nodeMinEdge.y, 0.0);
          if (nodeArea <= 0.0) {
            continue;
          }
          let nodeExtent = nodeMax - nodeMin + vec2i(1);
          let isLeaf = nodeDepth >= maxDepth || (nodeExtent.x <= 1 && nodeExtent.y <= 1);
          if (isLeaf) {
            pcfVisibilityWeighted += sampleRectVisibilityExactPCFEdges(nodeMinEdge, nodeMaxEdge, linearCompareDepth, pcfLinearDepthBias) * nodeArea;
            pcfArea += nodeArea;
            continue;
          }
          let nodeMoments = averageShadowMomentsRectEdges(nodeMinEdge, nodeMaxEdge);
          let nodeDepthRange = sampleShadowMinMaxRectEdges(nodeMinEdge, nodeMaxEdge);
          let nodeVariance = momentVariance(nodeMoments);
          let depthDelta = linearCompareDepth - nodeMoments.x;
          let depthRangeSpan = max(nodeDepthRange.y - nodeDepthRange.x, 0.0);
          let vsmSafetyMargin = max(contactThreshold, 2.0 * sqrt(max(nodeVariance, 0.0)));
          let nodeFullyBeforeReceiver = nodeDepthRange.y < (linearCompareDepth - vsmSafetyMargin);
          let nodeRangeIsCompact = depthRangeSpan <= (2.0 * vsmSafetyMargin);
          let nodeVisibility = chebyshevUpperBoundRaw(nodeMoments, linearCompareDepth);
          let nodeLooksResolved = nodeVisibility <= 0.1 || nodeVisibility >= 0.9;
          if (nodeVariance <= varianceThreshold && nodeFullyBeforeReceiver && nodeRangeIsCompact && depthDelta > vsmSafetyMargin && nodeLooksResolved) {
            vsmVisibilityWeighted += nodeVisibility * nodeArea;
            vsmArea += nodeArea;
            continue;
          }
          let halfExtent = max((nodeExtent + vec2i(1)) / 2, vec2i(1));
          for (var childY = 0; childY < 2; childY = childY + 1) {
            for (var childX = 0; childX < 2; childX = childX + 1) {
              let childMin = vec2i(
                nodeMin.x + childX * halfExtent.x,
                nodeMin.y + childY * halfExtent.y
              );
              let childMax = min(
                vec2i(childMin.x + halfExtent.x - 1, childMin.y + halfExtent.y - 1),
                nodeMax
              );
              if (childMax.x < childMin.x || childMax.y < childMin.y || stackSize >= 341) {
                continue;
              }
              minStack[stackSize] = childMin;
              maxStack[stackSize] = childMax;
              depthStack[stackSize] = nodeDepth + 1;
              stackSize = stackSize + 1;
            }
          }
        }
        var visibilityWeighted = 0.0;
        var totalArea = 0.0;
        if (litArea > 0.0) {
          visibilityWeighted += litArea;
          totalArea += litArea;
        }
        if (vsmArea > 0.0) {
          visibilityWeighted += vsmVisibilityWeighted;
          totalArea += vsmArea;
        }
        if (pcfArea > 0.0) {
          visibilityWeighted += pcfVisibilityWeighted;
          totalArea += pcfArea;
        }
        var result: VssmAdaptiveResult;
        if (totalArea <= 0.0) {
          result.visibility = 1.0;
          result.litRatio = 1.0;
          result.vsmRatio = 0.0;
          result.pcfRatio = 0.0;
          return result;
        }
        result.visibility = visibilityWeighted / totalArea;
        result.litRatio = litArea / totalArea;
        result.vsmRatio = vsmArea / totalArea;
        result.pcfRatio = pcfArea / totalArea;
        return result;
      }

      fn filterShadowVSSMAdaptive(shadowCoord: vec3f, compareDepth: f32, linearCompareDepth: f32, linearDepthBias: f32, filterRadius: f32) -> f32 {
        return filterShadowVSSMAdaptiveResult(shadowCoord, compareDepth, linearCompareDepth, linearDepthBias, filterRadius).visibility;
      }

      fn debugMomentChebyshevColor(moments: vec2f, linearCompareDepth: f32) -> vec3f {
        let depthRange = max(shadowUniforms.controlB.w - shadowUniforms.controlB.z, 0.0001);
        let meanNorm = normalizeLinearDepthToUnit(moments.x);
        let varianceNorm = clamp(momentVariance(moments) / (depthRange * depthRange) * 64.0, 0.0, 1.0);
        let chebyshevVis = chebyshevUpperBound(moments, linearCompareDepth);
        return vec3f(meanNorm, varianceNorm, chebyshevVis);
      }

      fn debugSatDeltaColor(shadowUV: vec2f, linearCompareDepth: f32, filterRadius: i32) -> vec3f {
        let radius = min(max(filterRadius, 0), 4);
        let satMoments = filterShadowMomentsSAT(shadowUV, radius);
        let exactMoments = filterShadowMomentsPoint(shadowUV, radius);
        let satVisibility = chebyshevUpperBound(satMoments, linearCompareDepth);
        let exactVisibility = chebyshevUpperBound(exactMoments, linearCompareDepth);
        let depthRange = max(shadowUniforms.controlB.w - shadowUniforms.controlB.z, 0.0001);
        let meanErr = abs(satMoments.x - exactMoments.x) / depthRange;
        let secondErr = abs(satMoments.y - exactMoments.y) / (depthRange * depthRange);
        let visibilityErr = abs(satVisibility - exactVisibility);
        return vec3f(
          clamp(meanErr * 64.0, 0.0, 1.0),
          clamp(secondErr * 64.0, 0.0, 1.0),
          clamp(visibilityErr, 0.0, 1.0)
        );
      }

      fn exactWholeKernelVisibility(shadowCoord: vec3f, receiverLinearDepth: f32, linearDepthBias: f32, filterRadius: f32) -> f32 {
        let dimsU = textureDimensions(shadowDepthTexture);
        let dims = vec2f(f32(dimsU.x), f32(dimsU.y));
        let centerF = clamp(shadowCoord.xy * dims - vec2f(0.5), vec2f(0.0), dims - vec2f(1.0));
        let rectMinEdge = clamp(centerF - vec2f(filterRadius), vec2f(0.0), dims);
        let rectMaxEdge = clamp(centerF + vec2f(filterRadius) + vec2f(1.0), rectMinEdge + vec2f(1e-4), dims);
        return sampleRectVisibilityExactPCFEdges(rectMinEdge, rectMaxEdge, receiverLinearDepth, linearDepthBias * 1.5);
      }

      fn filterShadowMomentHybrid(shadowCoord: vec3f, linearCompareDepth: f32, linearDepthBias: f32, filterRadius: i32, useSat: bool) -> f32 {
        let radius = max(filterRadius, 0);
        let moments = select(
          filterShadowMomentsPoint(shadowCoord.xy, radius),
          filterShadowMomentsSAT(shadowCoord.xy, radius),
          useSat
        );
        let variance = momentVariance(moments);
        let contactThreshold = max(shadowUniforms.controlD.w, 0.0001);
        let varianceThreshold = max(shadowUniforms.controlD.y, 0.0);
        let depthRange = sampleShadowMinMaxRect(shadowCoord.xy, radius);
        let depthRangeSpan = max(depthRange.y - depthRange.x, 0.0);
        let vsmSafetyMargin = max(contactThreshold, 2.0 * sqrt(max(variance, 0.0)));
        let kernelFullyBeforeReceiver = depthRange.y < (linearCompareDepth - vsmSafetyMargin);
        let kernelRangeIsCompact = depthRangeSpan <= (2.0 * vsmSafetyMargin);
        let chebyshevVis = chebyshevUpperBound(moments, linearCompareDepth);
        let kernelLooksResolved = chebyshevVis <= 0.1 || chebyshevVis >= 0.9;
        if (variance <= varianceThreshold && kernelFullyBeforeReceiver && kernelRangeIsCompact && kernelLooksResolved) {
          return chebyshevVis;
        }
        return exactWholeKernelVisibility(shadowCoord, linearCompareDepth, linearDepthBias, f32(radius));
      }

      fn shadowVisibility(shadingSample: ShadingSample, lightIndex: u32) -> f32 {
        let shadowMode = u32(shadowUniforms.controlA.w + 0.5);
        let shadowLightIndex = u32(shadowUniforms.controlB.x + 0.5);
        if (shadowMode == 0u || lightIndex != shadowLightIndex) {
          return 1.0;
        }

        let lightClip = shadowUniforms.lightViewProj * vec4f(shadingSample.worldPosition, 1.0);
        if (lightClip.w <= 0.0) {
          return 1.0;
        }

        let lightViewPosition = shadowUniforms.lightView * vec4f(shadingSample.worldPosition, 1.0);
        let receiverLinearDepth = max(-lightViewPosition.z, shadowUniforms.controlB.z + 0.0001);
        let receiverMomentDepth = receiverLinearDepth;
        let projCoords = lightClip.xyz / lightClip.w;
        let shadowCoord = vec3f(
          projCoords.x * 0.5 + 0.5,
          projCoords.y * -0.5 + 0.5,
          projCoords.z
        );
        if (shadowCoord.x <= 0.0 || shadowCoord.x >= 1.0 || shadowCoord.y <= 0.0 || shadowCoord.y >= 1.0 || shadowCoord.z <= 0.0 || shadowCoord.z >= 1.0) {
          return 1.0;
        }

        let worldLightDir = normalize(shadingSample.lightSource.position - shadingSample.worldPosition);
        let baseBias = shadowUniforms.controlA.y;
        let ndotl = max(dot(shadingSample.worldNormal, worldLightDir), 0.0);
        let slopeScale = sqrt(max(1.0 - ndotl * ndotl, 0.0)) / max(ndotl, 0.15);
        let bias = baseBias * clamp(1.0 + slopeScale, 1.0, 8.0);
        let compareDepth = shadowCoord.z - bias;
        let blockerDepthBias = max(bias * (shadowUniforms.controlB.w - shadowUniforms.controlB.z), 0.001);

        if (shadowMode == 1u) {
          return compareShadowDepthBilinear(shadowCoord.xy, compareDepth);
        }

        let rawFilterRadius = shadowUniforms.controlA.z;
        let filterRadiusScale = max(rawFilterRadius, 1.0);
        if (shadowMode == 2u) {
          let radius = i32(round(shadowUniforms.controlA.z));
          return filterShadow(shadowCoord, compareDepth, radius);
        }

        if (shadowMode == 4u) {
          let linearCompareDepth = receiverMomentDepth;
          let radius = i32(clamp(round(rawFilterRadius), 0.0, 12.0));
          return filterShadowMomentHybrid(shadowCoord, linearCompareDepth, blockerDepthBias, radius, false);
        }

        let areaLightSize = shadowUniforms.controlB.y;
        let nearPlane = shadowUniforms.controlB.z;
        let lightFrustumWidth = max(shadowUniforms.controlC.x, 0.0001);
        let tanHalfLightFov = max(shadowUniforms.controlC.y, 0.0001);
        let lightSizeUv = areaLightSize / lightFrustumWidth;
        let searchWidthUv = lightSizeUv * max(receiverLinearDepth - nearPlane, 0.0) / receiverLinearDepth;
        let searchRadius = i32(clamp(ceil(searchWidthUv * shadowUniforms.controlA.x), 1.0, 12.0));
        let receiverPlaneWidth = 2.0 * receiverLinearDepth * tanHalfLightFov;
        if (shadowMode == 6u) {
          let blockerCompareDepth = max(receiverMomentDepth, shadowUniforms.controlB.z);
          let linearCompareDepth = receiverMomentDepth;
          let kernelClassification = classifyVssmKernelWithHsm(shadowCoord.xy, searchRadius, linearCompareDepth);
          if (kernelClassification > 0) {
            return 1.0;
          }
          if (kernelClassification < 0) {
            return 0.0;
          }
          let estimatedBlocker = estimateBlockerDepthVSSMSubdivided(shadowCoord.xy, blockerCompareDepth, receiverLinearDepth, blockerDepthBias, searchRadius);
          var blockerDepth = estimatedBlocker.x;
          if (blockerDepth <= 0.0) {
            let blockerInfo = averageBlockerDepth(shadowCoord, receiverLinearDepth, blockerDepthBias, searchRadius);
            if (blockerInfo.y <= 0.0) {
              return 1.0;
            }
            blockerDepth = blockerInfo.x / blockerInfo.y;
          }
          if (blockerDepth >= receiverLinearDepth) {
            return 1.0;
          }
          let vssmPenumbraWidth = max(receiverLinearDepth - blockerDepth, 0.0) * areaLightSize / max(blockerDepth, 0.0001);
          let vssmFilterWidthUv = vssmPenumbraWidth / max(receiverPlaneWidth, 0.0001);
          let vssmFilterRadius = clamp(max(rawFilterRadius, 0.0) + vssmFilterWidthUv * shadowUniforms.controlA.x, 0.0, 16.0);
          return filterShadowVSSMAdaptive(shadowCoord, compareDepth, linearCompareDepth, blockerDepthBias, vssmFilterRadius);
        }
        if (shadowMode == 7u) {
          let blockerCompareDepth = max(receiverMomentDepth, shadowUniforms.controlB.z);
          let linearCompareDepth = receiverMomentDepth;
          let contactThreshold = max(shadowUniforms.controlD.w, 0.0001);
          let kernelClassification = classifyVssmKernelWithHsm(shadowCoord.xy, searchRadius, linearCompareDepth);
          if (kernelClassification > 0) {
            return 1.0;
          }
          if (kernelClassification < 0) {
            return 0.0;
          }
          let estimatedBlocker = estimateBlockerDepthVSSMPaper(shadowCoord.xy, blockerCompareDepth, receiverLinearDepth, blockerDepthBias, searchRadius);
          if (estimatedBlocker.y <= 0.0 || estimatedBlocker.x <= 0.0 || estimatedBlocker.x >= receiverLinearDepth) {
            return 1.0;
          }
          let blockerDepth = estimatedBlocker.x;
          if (abs(receiverLinearDepth - blockerDepth) <= contactThreshold) {
            let contactRadius = i32(clamp(round(max(rawFilterRadius, 1.0)), 1.0, 4.0));
            return filterShadowContactPCF(shadowCoord, compareDepth, contactRadius);
          }
          let vssmPenumbraWidth = max(receiverLinearDepth - blockerDepth, 0.0) * areaLightSize / max(blockerDepth, 0.0001);
          let vssmFilterWidthUv = vssmPenumbraWidth / max(receiverPlaneWidth, 0.0001);
          let vssmFilterRadius = i32(clamp(ceil(max(rawFilterRadius, 0.0) + vssmFilterWidthUv * shadowUniforms.controlA.x), 0.0, 16.0));
          return filterShadowVSSMPaperResult(shadowCoord, compareDepth, linearCompareDepth, vssmFilterRadius).visibility;
        }
        let blockerInfo = averageBlockerDepth(shadowCoord, receiverLinearDepth, blockerDepthBias, searchRadius);
        if (blockerInfo.y <= 0.0) {
          return 1.0;
        }
        let avgBlockerDepth = blockerInfo.x / blockerInfo.y;
        if (avgBlockerDepth >= receiverLinearDepth) {
          return 1.0;
        }
        let penumbraWidth = max(receiverLinearDepth - avgBlockerDepth, 0.0) * areaLightSize / max(avgBlockerDepth, 0.0001);
        let filterWidthUv = penumbraWidth / max(receiverPlaneWidth, 0.0001);
        let filterRadius = i32(clamp(ceil(max(filterRadiusScale, 1.0) + filterWidthUv * shadowUniforms.controlA.x), 1.0, 16.0));
        if (shadowMode == 5u) {
          let linearCompareDepth = receiverMomentDepth;
          return filterShadowMomentHybrid(shadowCoord, linearCompareDepth, blockerDepthBias, filterRadius, true);
        }
        return filterShadow(shadowCoord, compareDepth, filterRadius);
      }

      fn computeRadiance(shadingSample: ShadingSample) -> vec3f {
        var colorResponse = vec3f (0.0);
        let numOfLights = u32(scene.numOfLightSources);
        for (var lightSourceIndex = 0u; lightSourceIndex < numOfLights; lightSourceIndex++) {
          var s = shadingSample;
          s.lightSource = lightSources[lightSourceIndex];
          colorResponse += shadowVisibility(s, lightSourceIndex) * lightShade(s);
        }
        return colorResponse;
      }

      fn shadowDebugColor(shadingSample: ShadingSample) -> vec3f {
        let debugMode = u32(shadowUniforms.controlC.w + 0.5);
        if (debugMode == 0u) {
          return vec3f(-1.0);
        }
        let shadowMode = u32(shadowUniforms.controlA.w + 0.5);
        let shadowLightIndex = u32(shadowUniforms.controlB.x + 0.5);
        let visibility = shadowVisibility(shadingSample, shadowLightIndex);
        if (debugMode == 1u) {
          return vec3f(visibility);
        }

        let lightClip = shadowUniforms.lightViewProj * vec4f(shadingSample.worldPosition, 1.0);
        if (lightClip.w <= 0.0) {
          return vec3f(0.0);
        }
        let lightViewPosition = shadowUniforms.lightView * vec4f(shadingSample.worldPosition, 1.0);
        let receiverLinearDepth = max(-lightViewPosition.z, shadowUniforms.controlB.z + 0.0001);
        let projCoords = lightClip.xyz / lightClip.w;
        let shadowCoord = vec3f(
          projCoords.x * 0.5 + 0.5,
          projCoords.y * -0.5 + 0.5,
          projCoords.z
        );
        if (shadowCoord.x <= 0.0 || shadowCoord.x >= 1.0 || shadowCoord.y <= 0.0 || shadowCoord.y >= 1.0 || shadowCoord.z <= 0.0 || shadowCoord.z >= 1.0) {
          return vec3f(0.0);
        }
        let worldLightDir = normalize(shadingSample.lightSource.position - shadingSample.worldPosition);
        let baseBias = shadowUniforms.controlA.y;
        let ndotl = max(dot(shadingSample.worldNormal, worldLightDir), 0.0);
        let slopeScale = sqrt(max(1.0 - ndotl * ndotl, 0.0)) / max(ndotl, 0.15);
        let bias = baseBias * clamp(1.0 + slopeScale, 1.0, 8.0);
        let compareDepth = shadowCoord.z - bias;
        let areaLightSize = shadowUniforms.controlB.y;
        let nearPlane = shadowUniforms.controlB.z;
        let lightFrustumWidth = max(shadowUniforms.controlC.x, 0.0001);
        let tanHalfLightFov = max(shadowUniforms.controlC.y, 0.0001);
        let lightSizeUv = areaLightSize / lightFrustumWidth;
        let searchWidthUv = lightSizeUv * max(receiverLinearDepth - nearPlane, 0.0) / receiverLinearDepth;
        let searchRadius = i32(clamp(ceil(searchWidthUv * shadowUniforms.controlA.x), 1.0, 12.0));
        let blockerDepthBias = max(bias * (shadowUniforms.controlB.w - shadowUniforms.controlB.z), 0.001);
        let receiverPlaneWidth = 2.0 * receiverLinearDepth * tanHalfLightFov;
        let blockerCompareDepth = max(receiverLinearDepth, shadowUniforms.controlB.z);
        let linearCompareDepth = receiverLinearDepth;
        let rawFilterRadius = shadowUniforms.controlA.z;

        if (debugMode == 3u || debugMode == 4u) {
          if (shadowMode == 4u) {
            let radius = i32(clamp(round(rawFilterRadius), 0.0, 12.0));
            let moments = filterShadowMoments(shadowCoord.xy, radius);
            if (debugMode == 3u) {
              return debugMomentChebyshevColor(moments, linearCompareDepth);
            }
            return vec3f(0.0);
          }

          if (shadowMode == 5u) {
            let blockerInfo = averageBlockerDepth(shadowCoord, receiverLinearDepth, blockerDepthBias, searchRadius);
            if (blockerInfo.y <= 0.0) {
              return vec3f(visibility);
            }
            let avgBlockerDepth = blockerInfo.x / blockerInfo.y;
            if (avgBlockerDepth >= receiverLinearDepth) {
              return vec3f(visibility);
            }
            let penumbraWidth = max(receiverLinearDepth - avgBlockerDepth, 0.0) * areaLightSize / max(avgBlockerDepth, 0.0001);
            let filterWidthUv = penumbraWidth / max(receiverPlaneWidth, 0.0001);
            let filterRadius = i32(clamp(ceil(max(max(rawFilterRadius, 1.0), 1.0) + filterWidthUv * shadowUniforms.controlA.x), 1.0, 16.0));
            if (debugMode == 3u) {
              return debugMomentChebyshevColor(filterShadowMomentsSAT(shadowCoord.xy, filterRadius), linearCompareDepth);
            }
            return debugSatDeltaColor(shadowCoord.xy, linearCompareDepth, filterRadius);
          }

          if (shadowMode == 6u) {
            let kernelClassification = classifyVssmKernelWithHsm(shadowCoord.xy, searchRadius, linearCompareDepth);
            if (kernelClassification > 0 || kernelClassification < 0) {
              return vec3f(visibility);
            }
            let estimatedBlocker = estimateBlockerDepthVSSMSubdivided(shadowCoord.xy, blockerCompareDepth, receiverLinearDepth, blockerDepthBias, searchRadius);
            var blockerDepth = estimatedBlocker.x;
            if (blockerDepth <= 0.0) {
              let blockerInfo = averageBlockerDepth(shadowCoord, receiverLinearDepth, blockerDepthBias, searchRadius);
              if (blockerInfo.y <= 0.0) {
                return vec3f(visibility);
              }
              blockerDepth = blockerInfo.x / blockerInfo.y;
            }
            if (blockerDepth >= receiverLinearDepth) {
              return vec3f(visibility);
            }
            let vssmPenumbraWidth = max(receiverLinearDepth - blockerDepth, 0.0) * areaLightSize / max(blockerDepth, 0.0001);
            let vssmFilterWidthUv = vssmPenumbraWidth / max(receiverPlaneWidth, 0.0001);
            let vssmFilterRadius = clamp(max(rawFilterRadius, 0.0) + vssmFilterWidthUv * shadowUniforms.controlA.x, 0.0, 16.0);
            if (debugMode == 3u) {
              return debugMomentChebyshevColor(filterShadowMomentsSAT(shadowCoord.xy, i32(round(vssmFilterRadius))), linearCompareDepth);
            }
            return debugSatDeltaColor(shadowCoord.xy, linearCompareDepth, i32(round(vssmFilterRadius)));
          }

          if (shadowMode == 7u) {
            let kernelClassification = classifyVssmKernelWithHsm(shadowCoord.xy, searchRadius, linearCompareDepth);
            if (kernelClassification > 0 || kernelClassification < 0) {
              return vec3f(visibility);
            }
            let contactThreshold = max(shadowUniforms.controlD.w, 0.0001);
            let estimatedBlocker = estimateBlockerDepthVSSMPaper(shadowCoord.xy, blockerCompareDepth, receiverLinearDepth, blockerDepthBias, searchRadius);
            if (estimatedBlocker.y <= 0.0 || estimatedBlocker.x <= 0.0 || estimatedBlocker.x >= receiverLinearDepth) {
              return vec3f(visibility);
            }
            let blockerDepth = estimatedBlocker.x;
            if (abs(receiverLinearDepth - blockerDepth) <= contactThreshold) {
              return vec3f(filterShadowContactPCF(shadowCoord, compareDepth, i32(clamp(round(max(rawFilterRadius, 1.0)), 1.0, 4.0))));
            }
            let vssmPenumbraWidth = max(receiverLinearDepth - blockerDepth, 0.0) * areaLightSize / max(blockerDepth, 0.0001);
            let vssmFilterWidthUv = vssmPenumbraWidth / max(receiverPlaneWidth, 0.0001);
            let vssmFilterRadius = i32(clamp(ceil(max(rawFilterRadius, 0.0) + vssmFilterWidthUv * shadowUniforms.controlA.x), 0.0, 16.0));
            if (debugMode == 3u) {
              return debugMomentChebyshevColor(filterShadowMomentsSAT(shadowCoord.xy, vssmFilterRadius), linearCompareDepth);
            }
            return debugSatDeltaColor(shadowCoord.xy, linearCompareDepth, vssmFilterRadius);
          }

          return vec3f(visibility);
        }

        if (debugMode != 2u || (shadowMode != 6u && shadowMode != 7u)) {
          return vec3f(visibility);
        }

        let kernelClassification = classifyVssmKernelWithHsm(shadowCoord.xy, searchRadius, linearCompareDepth);
        if (kernelClassification > 0) {
          return vec3f(0.0, 1.0, 0.0);
        }
        if (kernelClassification < 0) {
          return vec3f(0.0);
        }
        var estimatedBlocker = vec2f(0.0, 0.0);
        if (shadowMode == 6u) {
          estimatedBlocker = estimateBlockerDepthVSSMSubdivided(shadowCoord.xy, blockerCompareDepth, receiverLinearDepth, blockerDepthBias, searchRadius);
        } else {
          estimatedBlocker = estimateBlockerDepthVSSMPaper(shadowCoord.xy, blockerCompareDepth, receiverLinearDepth, blockerDepthBias, searchRadius);
        }
        var blockerDepth = estimatedBlocker.x;
        if (blockerDepth <= 0.0) {
          return vec3f(0.0, 1.0, 0.0);
        }
        if (blockerDepth >= receiverLinearDepth) {
          return vec3f(0.0, 1.0, 0.0);
        }
        let vssmPenumbraWidth = max(receiverLinearDepth - blockerDepth, 0.0) * areaLightSize / max(blockerDepth, 0.0001);
        let vssmFilterWidthUv = vssmPenumbraWidth / max(receiverPlaneWidth, 0.0001);
        var vssmFilterRadius = 0.0;
        if (shadowMode == 6u) {
          vssmFilterRadius = clamp(max(rawFilterRadius, 0.0) + vssmFilterWidthUv * shadowUniforms.controlA.x, 0.0, 16.0);
        } else {
          vssmFilterRadius = f32(i32(clamp(ceil(max(rawFilterRadius, 0.0) + vssmFilterWidthUv * shadowUniforms.controlA.x), 0.0, 16.0)));
        }
        var result: VssmAdaptiveResult;
        if (shadowMode == 6u) {
          result = filterShadowVSSMAdaptiveResult(shadowCoord, compareDepth, linearCompareDepth, blockerDepthBias, vssmFilterRadius);
        } else {
          result = filterShadowVSSMPaperResult(shadowCoord, compareDepth, linearCompareDepth, i32(vssmFilterRadius));
        }
        return vec3f(result.vsmRatio, result.litRatio, result.pcfRatio);
      }





      
      struct ShadowVertexOutput {
        @builtin(position) builtInPos : vec4f,
        @location(0) linearDepth: f32,
      };

      @vertex
        fn shadowVertexMain(input: RasterVertexInput) -> ShadowVertexOutput {
          let mesh = meshes[input.meshIndex];
          let vID = input.vertexIndex;
          let triIndex = vID / 3u;
          let triVertIndex = vID % 3u;
          let triangle = getTriangle(mesh.triOffset + triIndex);
          let vertIndex = mesh.posOffset + triangle[triVertIndex];
          let worldPosition = getVertPos(vertIndex);
          let lightViewPosition = shadowUniforms.lightView * vec4f(worldPosition, 1.0);
          var output: ShadowVertexOutput;
          output.builtInPos = shadowUniforms.lightViewProj * vec4f(worldPosition, 1.0);
          output.linearDepth = max(-lightViewPosition.z, shadowUniforms.controlB.z);
          return output;
        }

      @fragment
        fn shadowFragmentMain(input: ShadowVertexOutput) -> @location(0) vec4f {
          let depth = input.linearDepth;
          let secondMoment = depth * depth;
          let nearPlane = shadowUniforms.controlB.z;
          let depthRange = max(shadowUniforms.controlB.w - nearPlane, 0.0001);
          let normMean = normalizeLinearDepthToUnit(depth);
          let normSecond = clamp(
            (secondMoment - 2.0 * nearPlane * depth + nearPlane * nearPlane) / (depthRange * depthRange),
            0.0,
            1.0
          );
          return vec4f(normMean, normSecond, 0.0, 1.0);
        }

      @vertex
        fn rasterVertexMain(input: RasterVertexInput) -> RasterVertexOutput {
          let cam = scene.camera;
          var mesh = meshes[input.meshIndex];
          let vID = input.vertexIndex;


          let triIndex = vID / 3u;
          let triVertIndex = vID % 3u;
          let triangle = getTriangle(mesh.triOffset + triIndex);
          let vertIndex = mesh.posOffset + triangle[triVertIndex];
          
          var output: RasterVertexOutput;
          output.worldPosition = getVertPos(vertIndex);
          let p = cam.viewMat * cam.modelMat * vec4f(output.worldPosition, 1.0); 
          output.builtInPos = cam.projMat * p;
          output.viewPosition = p.xyz;
          let n = cam.transInvViewMat * vec4f(getVertNormal(vertIndex), 1.0);
          output.normal = normalize(n.xyz);
          output.texCoord = getVertTexCoord(vertIndex);
          output.materialIndex = mesh.materialIndex; 
          return output; 
        }

      @fragment
        fn rasterFragmentMain(input: RasterVertexOutput) -> @location(0) vec4f {
          var shadingSample = ShadingSample();
          shadingSample.worldPosition = input.worldPosition;
          shadingSample.viewPosition = input.viewPosition;
          shadingSample.normal = normalize(input.normal);
          shadingSample.worldNormal = normalize((scene.camera.invViewMat * vec4f(shadingSample.normal, 0.0)).xyz);
          let texCoord = input.texCoord;
          shadingSample.material = genProceduralMaterial(materials[input.materialIndex], input.worldPosition, texCoord);
          let debugColor = shadowDebugColor(shadingSample);
          if (debugColor.x >= 0.0) {
            return vec4f(debugColor, 1.0);
          }
          let colorResponse = computeRadiance(shadingSample);
          return vec4f(colorResponse, 1.0);
        }





      struct RayVertexInput {
        @builtin(vertex_index) vertexIndex: u32
      };
  
      struct RayVertexOutput {
        @builtin(position) pos : vec4f,
      }; 

      struct RayFragmentInput {
        @builtin(position) fragPos : vec4f,
      };





      struct Ray {
        origin: vec3f,
        direction: vec3f,
      };

      struct Hit{
        meshIndex: u32,
        triIndex: u32,
        u: f32,
        v: f32,
        t: f32,
      };

      fn interpolate2f(x0: vec2f, x1: vec2f, x2: vec2f, uvw: vec3f) -> vec2f {
        return uvw.z * x0 + uvw.x * x1 + uvw.y * x2;
      }

      fn interpolate3f(x0: vec3f, x1: vec3f, x2: vec3f, uvw: vec3f) -> vec3f {
        return uvw.z * x0 + uvw.x * x1 + uvw.y * x2;
      }

      fn rayAt(uv: vec2f, camera : Camera) -> Ray {
        var ray : Ray;
        let viewRight = normalize(camera.invViewMat[0].xyz);
        let viewUp = normalize(camera.invViewMat[1].xyz);
        let viewDir = -normalize(camera.invViewMat[2].xyz);
        let eye = camera.invViewMat[3].xyz;
        let w = 2.0 * tan(0.5 * camera.fov); 
        ray.origin = eye;
        ray.direction = normalize(viewDir + ((uv.x - 0.5) * camera.aspectRatio * w) * viewRight + ((uv.y) - 0.5) * w * viewUp);  
        return ray;
      }

      fn intersectTriangle(
        ray: Ray, 
        p0: vec3f, 
        p1: vec3f, 
        p2: vec3f, 
        backFaceCulling: bool,
        tMin: f32,
        tMax: f32,
        hit: ptr<function, Hit>
      ) -> bool {
        const EPSILON = 1e-6;
        let e1 = p1 - p0;
        let e2 = p2 - p0;
        let dxe2 = cross(ray.direction, e2);
        let det = dot(e1, dxe2);
        if ((backFaceCulling && det < EPSILON) || (!backFaceCulling && abs(det) < EPSILON)) {
          return false;
        }
        let invDet = 1.0 / det;
        let op0 = ray.origin - p0;
        (*hit).u = dot(op0, dxe2) * invDet;
        if ((*hit).u < 0.0 || (*hit).u > 1.f) {
          return false;
        }
        let op0xe1 = cross(op0, e1);
        (*hit).t = dot(e2, op0xe1) * invDet;
        if ((*hit).t < tMin || (*hit).t > tMax) {
          return false;
        }
        (*hit).v = dot(ray.direction, op0xe1) * invDet;
        if ((*hit).v >= 0.0 && (*hit).u + (*hit).v <= 1.0) {
          return true;
        }
        return false;
      }

      fn rayTrace(
        ray: Ray, 
        maxDistance: f32,
        anyHit: bool,
        hit: ptr<function, Hit>
      ) -> bool {
        var intersectionFound = false;
        let numOfMeshes = u32(scene.numOfMeshes);
        for (var meshIndex = 0u; meshIndex < numOfMeshes; meshIndex++) {
          let mesh = meshes[meshIndex];
          for (var triIndex = 0u; triIndex < mesh.numOfTriangles; triIndex++) {
            let triangle = getTriangle(mesh.triOffset + triIndex);
            var triHit: Hit;
            triHit.meshIndex = meshIndex;
            triHit.triIndex = triIndex;
            let p0 = getVertPos(mesh.posOffset + triangle.x);
            let p1 = getVertPos(mesh.posOffset + triangle.y);
            let p2 = getVertPos(mesh.posOffset + triangle.z);
            if (intersectTriangle(ray, p0, p1, p2, true, 0.0, maxDistance, &triHit) == true) {
              if (!intersectionFound || (intersectionFound && triHit.t < hit.t)) {
                if (anyHit == true) {
                  return true;
                }
                *hit = triHit;
                intersectionFound = true;
              }
            }
          }
        }
        return intersectionFound;
      }

      fn shadeRT(hit: Hit) -> vec4f {
        let cam = scene.camera;
        let mesh = meshes[hit.meshIndex];
        let tri = getTriangle(mesh.triOffset + hit.triIndex);
        let uvw = vec3f(hit.u, hit.v, 1.0 - hit.u - hit.v);
        let position = interpolate3f(getVertPos(mesh.posOffset + tri.x), 
                                     getVertPos(mesh.posOffset + tri.y), 
                                     getVertPos(mesh.posOffset + tri.z), 
                                     uvw);
        var shadingSample = ShadingSample();
        let normal = normalize(interpolate3f(getVertNormal(mesh.posOffset + tri.x), 
                                             getVertNormal(mesh.posOffset + tri.y), 
                                             getVertNormal(mesh.posOffset + tri.z), 
                                             uvw));
        let texCoord = interpolate2f(getVertTexCoord(mesh.posOffset + tri.x), 
                                     getVertTexCoord(mesh.posOffset + tri.y), 
                                     getVertTexCoord(mesh.posOffset + tri.z), uvw);
        shadingSample.normal = (cam.transInvViewMat * vec4(normal, 1.0)).xyz;
        shadingSample.worldPosition = position;
        shadingSample.worldNormal = normal;
        var colorResponse = vec3f(0.0);
        shadingSample.viewPosition = (cam.viewMat * cam.modelMat * vec4f(position, 1.0)).xyz;
        shadingSample.material = genProceduralMaterial(materials[mesh.materialIndex], position, texCoord);
        let numOfLights = u32(scene.numOfLightSources);
        for (var lightSourceIndex = 0u; lightSourceIndex < numOfLights; lightSourceIndex++) {
          let l = lightSources[lightSourceIndex];
          shadingSample.lightSource = l;
          if (bool(l.rayTracedShadows) == true) {
            var shadowRay : Ray;
            const shadowBias = 0.0001;
            let pos2light = l.position - position;
            let lightDist = length(pos2light);
            shadowRay.direction = normalize(pos2light);
            shadowRay.origin = position + shadowBias * normal;
            var shadowHit : Hit;
            let inShadow = rayTrace(shadowRay, lightDist + EPSILON, true, &shadowHit);
            if (inShadow == false || (inShadow == true && shadowHit.t > lightDist)) {
              colorResponse += lightShade(shadingSample); 
            }
          } else {
            colorResponse += lightShade(shadingSample);
          }
        }
        return vec4f (colorResponse, 1.0);
      }





      @vertex
        fn rayVertexMain(input: RayVertexInput) -> RayVertexOutput {
          var output: RayVertexOutput;
          const screenPos = array<vec2<f32>, 6>(
              vec2f(-1.0, -1.0),
              vec2f( 1.0, -1.0),
              vec2f(-1.0,  1.0),
              vec2f(-1.0,  1.0),
              vec2f( 1.0, -1.0),
              vec2f( 1.0,  1.0),
          );
          output.pos = vec4f(screenPos[input.vertexIndex], 0.0, 1.0);
          return output;
        }

      @fragment
        fn rayFragmentMain(input: RayFragmentInput) -> @location(0) vec4f {
          const MAX_DISTANCE = 1e8;
          let coord = vec2f(input.fragPos.x/1024, 1.0-input.fragPos.y/768);
          let ray = rayAt(coord, scene.camera);
          var colorResponse = vec4f(0.0, 0.0, 0.0, 1.0);
          var hit: Hit;
          if (rayTrace(ray, MAX_DISTANCE, false, &hit) == true) {
            colorResponse = shadeRT(hit);
          }
          return colorResponse;
        }
