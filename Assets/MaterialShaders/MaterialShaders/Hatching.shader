// Pencil cross-hatching: darker areas get more layers of procedural ink lines.
Shader "ShaderPack/Stylized/Hatching"
{
    Properties
    {
        _BaseColor ("Paper Tint", Color) = (1, 1, 1, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _InkColor ("Ink Color", Color) = (0.1, 0.1, 0.15, 1)
        _LineDensity ("Line Density", Range(5, 200)) = 60
        _LineWidth ("Line Width", Range(0.05, 0.9)) = 0.3
        _Threshold1 ("Layer 1 below (light)", Range(0, 1)) = 0.75
        _Threshold2 ("Layer 2 below", Range(0, 1)) = 0.5
        _Threshold3 ("Layer 3 below (dark)", Range(0, 1)) = 0.25
        [Toggle] _ScreenSpace ("Screen-Space Lines", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half4  _InkColor;
            float  _LineDensity;
            float  _LineWidth;
            half   _Threshold1;
            half   _Threshold2;
            half   _Threshold3;
            half   _ScreenSpace;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "HatchingForward"
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
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            // 1 on an ink line, 0 between lines (anti-aliased)
            half HatchLine (float2 p, float angle)
            {
                float s, c;
                sincos(angle, s, c);
                float x  = p.x * c - p.y * s;
                float d  = abs(frac(x) - 0.5);
                float aa = fwidth(x);
                float w  = _LineWidth * 0.5;
                return 1.0 - smoothstep(w - aa, w + aa, d);
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half shade = saturate(saturate(dot(N, light.direction)) * light.shadowAttenuation * 0.8 + 0.2);

                float2 p = (_ScreenSpace > 0.5) ? IN.positionHCS.xy * _LineDensity / 1000.0
                                                : IN.uv * _LineDensity;

                half l1 = HatchLine(p,  0.785398) * step(shade, _Threshold1);
                half l2 = HatchLine(p, -0.785398) * step(shade, _Threshold2);
                half l3 = HatchLine(p,  0.0)      * step(shade, _Threshold3);
                half ink = max(l1, max(l2, l3));

                half3 paper = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                return half4(lerp(paper, _InkColor.rgb, ink * _InkColor.a), 1.0);
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
