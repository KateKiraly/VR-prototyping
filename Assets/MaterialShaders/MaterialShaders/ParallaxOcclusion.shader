// Parallax Occlusion Mapping: fakes real depth on flat surfaces (bricks, cobblestones)
// by ray-marching a height map in tangent space.
Shader "ShaderPack/Surface/ParallaxOcclusion"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        [Normal] _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0, 2)) = 1
        _HeightMap ("Height Map (white = high)", 2D) = "white" {}
        _HeightScale ("Depth", Range(0, 0.15)) = 0.04
        [IntRange] _Steps ("Ray Steps (quality)", Range(4, 64)) = 24
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _NormalStrength;
            float  _HeightScale;
            float  _Steps;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "POMForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
            TEXTURE2D(_HeightMap); SAMPLER(sampler_HeightMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 tangentWS   : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float3 positionWS  : TEXCOORD4;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs   nrm = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.normalWS    = nrm.normalWS;
                OUT.tangentWS   = nrm.tangentWS;
                OUT.bitangentWS = nrm.bitangentWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            float SampleDepth (float2 uv, float2 dx, float2 dy)
            {
                return 1.0 - SAMPLE_TEXTURE2D_GRAD(_HeightMap, sampler_HeightMap, uv, dx, dy).r;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 T  = normalize(IN.tangentWS);
                float3 B  = normalize(IN.bitangentWS);
                float3 N0 = normalize(IN.normalWS);
                float3 V  = normalize(GetWorldSpaceViewDir(IN.positionWS));

                // ---- Parallax occlusion ray-march ----
                float3 viewTS = normalize(float3(dot(V, T), dot(V, B), dot(V, N0)));
                float  steps  = max(_Steps, 1.0);
                float  layerDepth = 1.0 / steps;
                float2 deltaUV = (viewTS.xy / max(viewTS.z, 0.05)) * _HeightScale / steps;

                float2 uv = IN.uv;
                float2 dx = ddx(IN.uv);
                float2 dy = ddy(IN.uv);
                float currentLayer = 0.0;
                float depth = SampleDepth(uv, dx, dy);

                [loop] for (int i = 0; i < 64; i++)
                {
                    if (i >= (int)steps || currentLayer >= depth) break;
                    uv -= deltaUV;
                    depth = SampleDepth(uv, dx, dy);
                    currentLayer += layerDepth;
                }

                // Refine between the last two samples
                float2 prevUV = uv + deltaUV;
                float after   = depth - currentLayer;
                float before  = SampleDepth(prevUV, dx, dy) - currentLayer + layerDepth;
                float w = after / (after - before + 1e-5);
                uv = lerp(uv, prevUV, saturate(w));

                // ---- Shading with the offset UV ----
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D_GRAD(_NormalMap, sampler_NormalMap, uv, dx, dy), _NormalStrength);
                float3 N  = normalize(TransformTangentToWorld(nTS, half3x3(T, B, N0)));

                half3 albedo = SAMPLE_TEXTURE2D_GRAD(_BaseMap, sampler_BaseMap, uv, dx, dy).rgb * _BaseColor.rgb;
                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half3 lit = light.color * saturate(dot(N, light.direction)) * light.shadowAttenuation + SampleSH(N);
                return half4(albedo * lit, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            struct ShadowAttributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };

            float4 ShadowVert (ShadowAttributes IN) : SV_POSITION
            {
                float3 posWS    = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float4 posCS    = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, _LightDirection));
                #if UNITY_REVERSED_Z
                    posCS.z = min(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    posCS.z = max(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return posCS;
            }
            half4 ShadowFrag () : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
