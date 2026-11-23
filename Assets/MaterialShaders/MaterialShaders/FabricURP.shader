// Cloth / velvet look: soft wrap-around diffuse + view-dependent sheen + weave normal map.
Shader "Custom/FabricURP"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.6, 0.1, 0.15, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        [Normal] _NormalMap ("Weave Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0, 2)) = 1
        _Wrap ("Diffuse Wrap (softness)", Range(0, 1)) = 0.5
        _SheenColor ("Sheen Color", Color) = (1, 0.8, 0.85, 1)
        _SheenPower ("Sheen Power", Range(1, 10)) = 4
        _SheenIntensity ("Sheen Intensity", Range(0, 3)) = 1
        _AmbientStrength ("Ambient Strength", Range(0, 2)) = 1
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
            half   _Wrap;
            half4  _SheenColor;
            half   _SheenPower;
            half   _SheenIntensity;
            half   _AmbientStrength;
        CBUFFER_END
        ENDHLSL

        // ---------- Main fabric lighting pass ----------
        Pass
        {
            Name "FabricForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

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

            half4 frag (Varyings IN) : SV_Target
            {
                // Normal from the weave map
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv), _NormalStrength);
                float3 N  = normalize(TransformTangentToWorld(nTS,
                              half3x3(IN.tangentWS, IN.bitangentWS, IN.normalWS)));
                float3 V  = normalize(GetWorldSpaceViewDir(IN.positionWS));

                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float3 L = normalize(light.direction);
                half atten = light.shadowAttenuation * light.distanceAttenuation;

                // Wrap lighting: light bleeds past the terminator like soft cloth
                half wrapNdotL = saturate((dot(N, L) + _Wrap) / (1.0 + _Wrap));
                half3 lightCol = light.color * wrapNdotL * atten;

                half4 albedo  = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                half3 ambient = SampleSH(N) * _AmbientStrength;

                // Sheen: fibres catch light at grazing view angles
                half sheen = pow(1.0 - saturate(dot(N, V)), _SheenPower) * _SheenIntensity;
                half3 sheenCol = _SheenColor.rgb * sheen * (lightCol + ambient * 0.5);

                half3 col = albedo.rgb * (lightCol + ambient) + sheenCol;
                return half4(col, 1.0);
            }
            ENDHLSL
        }

        // ---------- Shadow casting ----------
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

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            float4 ShadowVert (Attributes IN) : SV_POSITION
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
