// Snow / moss / dust coverage on surfaces facing a direction (default: up).
// For moss, set Cover Color to green; for "moss on the north side", point Cover Direction there.
Shader "ShaderPack/Surface/SnowCoverage"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _CoverColor ("Cover Color", Color) = (0.95, 0.97, 1, 1)
        _CoverDirection ("Cover Direction (world)", Vector) = (0, 1, 0, 0)
        _CoverThreshold ("Coverage (lower = more)", Range(-1, 1)) = 0.4
        _CoverBlend ("Edge Softness", Range(0.001, 0.5)) = 0.05
        _CoverNoise ("Edge Noise", Range(0, 1)) = 0.3
        _CoverNoiseScale ("Noise Scale", Range(0.1, 20)) = 4
        _CoverHeight ("Thickness (vertex push)", Range(0, 0.2)) = 0.02
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half4  _CoverColor;
            float4 _CoverDirection;
            half   _CoverThreshold;
            half   _CoverBlend;
            half   _CoverNoise;
            float  _CoverNoiseScale;
            float  _CoverHeight;
        CBUFFER_END

        float Hash3 (float3 p)
        {
            p = frac(p * 0.3183099 + 0.1);
            p *= 17.0;
            return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
        }

        float ValueNoise3 (float3 x)
        {
            float3 i = floor(x);
            float3 f = frac(x);
            f = f * f * (3.0 - 2.0 * f);
            return lerp(lerp(lerp(Hash3(i + float3(0,0,0)), Hash3(i + float3(1,0,0)), f.x),
                             lerp(Hash3(i + float3(0,1,0)), Hash3(i + float3(1,1,0)), f.x), f.y),
                        lerp(lerp(Hash3(i + float3(0,0,1)), Hash3(i + float3(1,0,1)), f.x),
                             lerp(Hash3(i + float3(0,1,1)), Hash3(i + float3(1,1,1)), f.x), f.y), f.z);
        }

        // 0 = bare, 1 = fully covered
        float CoverMask (float3 normalWS, float3 posWS)
        {
            float d = dot(normalWS, normalize(_CoverDirection.xyz + 1e-5));
            float n = (ValueNoise3(posWS * _CoverNoiseScale) - 0.5) * _CoverNoise;
            return smoothstep(_CoverThreshold - _CoverBlend, _CoverThreshold + _CoverBlend, d + n);
        }
        ENDHLSL

        Pass
        {
            Name "CoverageForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; float3 positionWS : TEXCOORD2; };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float3 nWS   = TransformObjectToWorldNormal(IN.normalOS);
                float3 posWS = TransformObjectToWorld(IN.positionOS.xyz);
                posWS += nWS * _CoverHeight * CoverMask(nWS, posWS);   // thicken covered areas
                OUT.positionWS  = posWS;
                OUT.positionHCS = TransformWorldToHClip(posWS);
                OUT.normalWS    = nWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                half cover = CoverMask(N, IN.positionWS);

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                albedo = lerp(albedo, _CoverColor.rgb, cover);

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
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float3 posWS    = TransformObjectToWorld(IN.positionOS.xyz);
                posWS += normalWS * _CoverHeight * CoverMask(normalWS, posWS);
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
