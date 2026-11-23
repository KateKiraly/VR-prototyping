// Fake subsurface scattering: light glowing through thin parts (ears, leaves, wax, jade).
// Put the main light BEHIND the object to see it. Translucency map: white = thin.
Shader "ShaderPack/Surface/FakeSubsurface"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.9, 0.75, 0.65, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _ThicknessMap ("Translucency Map (white = thin)", 2D) = "white" {}
        [HDR] _SubsurfaceColor ("Subsurface Color", Color) = (1, 0.3, 0.2, 1)
        _Distortion ("Normal Distortion", Range(0, 1)) = 0.3
        _SSSPower ("Scatter Power", Range(1, 16)) = 4
        _SSSScale ("Scatter Strength", Range(0, 5)) = 1.5
        _Wrap ("Diffuse Wrap", Range(0, 1)) = 0.3
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half4  _SubsurfaceColor;
            half   _Distortion;
            half   _SSSPower;
            half   _SSSScale;
            half   _Wrap;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "SSSForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);
            TEXTURE2D(_ThicknessMap); SAMPLER(sampler_ThicknessMap);

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

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                half  trans  = SAMPLE_TEXTURE2D(_ThicknessMap, sampler_ThicknessMap, IN.uv).r;

                // Front lighting (soft wrap)
                half wrapNdotL = saturate((dot(N, L) + _Wrap) / (1.0 + _Wrap));
                half3 diffuse  = albedo * (light.color * wrapNdotL * light.shadowAttenuation + SampleSH(N));

                // Back lighting through the object (not shadowed, or it would cancel itself)
                float3 H  = normalize(L + N * _Distortion);
                half  vdh = pow(saturate(dot(V, -H)), _SSSPower) * _SSSScale;
                half3 sss = vdh * trans * _SubsurfaceColor.rgb * light.color * light.distanceAttenuation;

                return half4(diffuse + sss * albedo, 1.0);
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
