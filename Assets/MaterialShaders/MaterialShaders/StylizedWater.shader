// Stylized water: depth-based color, shoreline foam, refraction, vertex waves,
// scrolling normal maps, fresnel reflection and specular.
// REQUIRES: URP Asset -> Depth Texture ON and Opaque Texture ON. Use a subdivided plane.
Shader "ShaderPack/Nature/StylizedWater"
{
    Properties
    {
        [Header(Color)]
        _ShallowColor ("Shallow Color (alpha = opacity)", Color) = (0.3, 0.85, 0.9, 0.6)
        _DeepColor ("Deep Color (alpha = opacity)", Color) = (0.05, 0.2, 0.45, 0.95)
        _DepthMaxDistance ("Depth for Deep Color", Range(0.1, 20)) = 3

        [Header(Surface)]
        [Normal] _NormalMap ("Ripple Normal Map", 2D) = "bump" {}
        _NormalStrength ("Ripple Strength", Range(0, 1)) = 0.4
        _NormalTiling ("Ripple Tiling", Float) = 0.2
        _NormalSpeed ("Ripple Speed", Float) = 0.05
        _RefractionStrength ("Refraction", Range(0, 0.1)) = 0.02

        [Header(Waves)]
        _WaveAmplitude ("Wave Height", Range(0, 1)) = 0.1
        _WaveFrequency ("Wave Frequency", Float) = 1
        _WaveSpeed ("Wave Speed", Float) = 1

        [Header(Foam)]
        _FoamColor ("Foam Color", Color) = (1, 1, 1, 1)
        _FoamDistance ("Shore Foam Distance", Range(0, 3)) = 0.6
        _FoamCutoff ("Foam Cutoff", Range(0, 1)) = 0.75
        _FoamNoiseScale ("Foam Noise Scale", Float) = 4
        _FoamSpeed ("Foam Speed", Float) = 0.3

        [Header(Lighting)]
        _ReflectionColor ("Reflection Color (alpha = amount)", Color) = (0.8, 0.9, 1, 0.5)
        _FresnelPower ("Fresnel Power", Range(0.5, 10)) = 5
        _Glossiness ("Glossiness", Range(8, 1024)) = 256
        _SpecularStrength ("Specular Strength", Range(0, 4)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "WaterForward"
            Tags { "LightMode"="UniversalForward" }
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _ShallowColor;
                half4 _DeepColor;
                float _DepthMaxDistance;
                half  _NormalStrength;
                float _NormalTiling;
                float _NormalSpeed;
                float _RefractionStrength;
                float _WaveAmplitude;
                float _WaveFrequency;
                float _WaveSpeed;
                half4 _FoamColor;
                float _FoamDistance;
                float _FoamCutoff;
                float _FoamNoiseScale;
                float _FoamSpeed;
                half4 _ReflectionColor;
                half  _FresnelPower;
                half  _Glossiness;
                half  _SpecularStrength;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float4 screenPos   : TEXCOORD2;
            };

            float Hash2 (float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
            float ValueNoise2 (float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(Hash2(i), Hash2(i + float2(1, 0)), f.x),
                            lerp(Hash2(i + float2(0, 1)), Hash2(i + float2(1, 1)), f.x), f.y);
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float3 posWS = TransformObjectToWorld(IN.positionOS.xyz);

                // Two crossing sine waves + analytic normal
                float t = _Time.y * _WaveSpeed;
                float a = posWS.x * _WaveFrequency + t;
                float b = posWS.z * _WaveFrequency * 0.8 + t * 1.3;
                posWS.y += sin(a) * _WaveAmplitude + cos(b) * _WaveAmplitude * 0.5;
                float dydx =  cos(a) * _WaveAmplitude * _WaveFrequency;
                float dydz = -sin(b) * _WaveAmplitude * 0.5 * _WaveFrequency * 0.8;

                OUT.positionWS  = posWS;
                OUT.normalWS    = normalize(float3(-dydx, 1.0, -dydz));
                OUT.positionHCS = TransformWorldToHClip(posWS);
                OUT.screenPos   = ComputeScreenPos(OUT.positionHCS);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;
                float  t = _Time.y;

                // Ripples: two normal map samples scrolling in different directions
                float2 uvA = IN.positionWS.xz * _NormalTiling + float2(t, t * 0.7) * _NormalSpeed;
                float2 uvB = IN.positionWS.xz * _NormalTiling * 1.3 + float2(-t * 0.8, t * 0.5) * _NormalSpeed;
                half3 nA = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvA), _NormalStrength);
                half3 nB = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvB), _NormalStrength);
                half3 nTS = normalize(half3(nA.xy + nB.xy, nA.z * nB.z));
                float3 N = normalize(IN.normalWS + float3(nTS.x, 0.0, nTS.y));

                // Depth below the surface
                float surfaceEye = IN.screenPos.w;
                float depthDiff  = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams) - surfaceEye;

                // Refraction (skip if the offset sample is in front of the water)
                float2 refrUV  = screenUV + nTS.xy * _RefractionStrength;
                float  refrEye = LinearEyeDepth(SampleSceneDepth(refrUV), _ZBufferParams);
                if (refrEye < surfaceEye) refrUV = screenUV;
                else depthDiff = refrEye - surfaceEye;
                half3 sceneCol = SampleSceneColor(refrUV);

                half4 waterCol = lerp(_ShallowColor, _DeepColor, saturate(depthDiff / _DepthMaxDistance));
                half3 col = lerp(sceneCol, waterCol.rgb, waterCol.a);

                // Reflection + specular
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower);
                col = lerp(col, _ReflectionColor.rgb, fresnel * _ReflectionColor.a);
                half spec = pow(saturate(dot(N, normalize(light.direction + V))), _Glossiness) * _SpecularStrength;
                col += spec * light.color * light.shadowAttenuation;

                // Shoreline foam (more foam where the water is shallow)
                float foamNoise = ValueNoise2(IN.positionWS.xz * _FoamNoiseScale + t * _FoamSpeed);
                float foamCut   = saturate(depthDiff / max(_FoamDistance, 1e-4)) * _FoamCutoff;
                half  foam      = smoothstep(foamCut - 0.02, foamCut + 0.02, foamNoise);
                col = lerp(col, _FoamColor.rgb, foam * _FoamColor.a);

                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }
}
