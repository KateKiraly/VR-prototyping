// Dissolve / burn-away with a glowing edge. Procedural 3D noise in object space,
// so it needs no texture and no UVs. Animate "Dissolve Amount" 0 -> 1.
Shader "ShaderPack/Surface/Dissolve"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _DissolveAmount ("Dissolve Amount", Range(0, 1)) = 0.3
        _NoiseScale ("Noise Scale", Range(0.1, 30)) = 6
        _EdgeWidth ("Edge Width", Range(0, 0.2)) = 0.05
        [HDR] _EdgeColor ("Edge Color", Color) = (4, 1.2, 0.2, 1)
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull Mode", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            float  _DissolveAmount;
            float  _NoiseScale;
            float  _EdgeWidth;
            half4  _EdgeColor;
            half   _Cull;
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

        // Fractal noise remapped to roughly 0..1
        float DissolveNoise (float3 posOS)
        {
            float3 p = posOS * _NoiseScale;
            float v = 0.0, a = 0.5;
            [unroll] for (int i = 0; i < 4; i++) { v += a * ValueNoise3(p); p *= 2.03; a *= 0.5; }
            return saturate((v / 0.9375 - 0.25) * 2.0);
        }
        ENDHLSL

        Pass
        {
            Name "DissolveForward"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float3 positionOS  : TEXCOORD3;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.positionOS  = IN.positionOS.xyz;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag (Varyings IN, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float n = DissolveNoise(IN.positionOS);
                clip(n - _DissolveAmount);

                float3 N = normalize(IN.normalWS);
                N = IS_FRONT_VFACE(facing, N, -N);

                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half3 lit = light.color * saturate(dot(N, light.direction)) * light.shadowAttenuation + SampleSH(N);

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                half edge = (1.0 - step(_DissolveAmount + _EdgeWidth, n)) * step(0.001, _DissolveAmount);

                return half4(albedo * lit + _EdgeColor.rgb * edge, 1.0);
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
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            struct ShadowAttributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct ShadowVaryings   { float4 positionCS : SV_POSITION; float3 positionOS : TEXCOORD0; };

            ShadowVaryings ShadowVert (ShadowAttributes IN)
            {
                ShadowVaryings OUT;
                float3 posWS    = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float4 posCS    = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, _LightDirection));
                #if UNITY_REVERSED_Z
                    posCS.z = min(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    posCS.z = max(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                OUT.positionCS = posCS;
                OUT.positionOS = IN.positionOS.xyz;
                return OUT;
            }

            half4 ShadowFrag (ShadowVaryings IN) : SV_Target
            {
                clip(DissolveNoise(IN.positionOS) - _DissolveAmount);
                return 0;
            }
            ENDHLSL
        }
    }
}
