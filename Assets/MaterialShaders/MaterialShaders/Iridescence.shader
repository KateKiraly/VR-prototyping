// Iridescence / thin-film: rainbow colors that shift with viewing angle
// (soap bubbles, beetle shells, oil slicks, holographic foil).
Shader "ShaderPack/Surface/Iridescence"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.05, 0.05, 0.08, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _IridescenceStrength ("Iridescence Strength", Range(0, 2)) = 1
        _BaseIridescence ("Iridescence Everywhere", Range(0, 1)) = 0.2
        _FilmFrequency ("Film Thickness (color bands)", Range(0.1, 5)) = 1.5
        _HueShift ("Hue Shift", Range(0, 1)) = 0
        _FresnelPower ("Fresnel Power", Range(0.1, 8)) = 2
        _Glossiness ("Glossiness", Range(8, 256)) = 64
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _IridescenceStrength;
            half   _BaseIridescence;
            half   _FilmFrequency;
            half   _HueShift;
            half   _FresnelPower;
            half   _Glossiness;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "IridescenceForward"
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

            half4 frag (Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float3 L = light.direction;

                half NdotV = saturate(dot(N, V));
                half NdotL = saturate(dot(N, L)) * light.shadowAttenuation;
                half NdotH = saturate(dot(N, normalize(L + V)));

                // Cosine palette: angle -> rainbow
                half t = (1.0 - NdotV) * _FilmFrequency + _HueShift;
                half3 rainbow = 0.5 + 0.5 * cos(6.28318 * (t + half3(0.0, 0.333, 0.667)));

                half fres = pow(1.0 - NdotV, _FresnelPower);
                half spec = pow(NdotH, _Glossiness) * NdotL;

                half3 albedo  = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                half3 diffuse = albedo * (light.color * NdotL + SampleSH(N));
                half3 irid    = rainbow * (fres * _IridescenceStrength + spec * light.color
                                           + _BaseIridescence * (NdotL * 0.5 + 0.5));

                return half4(diffuse + irid, 1.0);
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
