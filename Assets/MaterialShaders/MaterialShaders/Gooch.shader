// Gooch technical-illustration shading: cool-to-warm instead of dark-to-light.
Shader "ShaderPack/Stylized/Gooch"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.8, 0.3, 0.2, 1)
        _BaseMap ("Base Texture", 2D) = "white" {}
        _CoolColor ("Cool Color", Color) = (0, 0, 0.55, 1)
        _WarmColor ("Warm Color", Color) = (0.3, 0.3, 0, 1)
        _Alpha ("Albedo in Cool", Range(0, 1)) = 0.25
        _Beta ("Albedo in Warm", Range(0, 1)) = 0.5
        _SpecularPower ("Specular Power", Range(4, 256)) = 32
        _EdgeColor ("Edge Color", Color) = (0, 0, 0, 1)
        _EdgeWidth ("Edge Width", Range(0, 1)) = 0.25
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half4  _CoolColor;
            half4  _WarmColor;
            half   _Alpha;
            half   _Beta;
            half   _SpecularPower;
            half4  _EdgeColor;
            half   _EdgeWidth;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "GoochForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
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
                float3 L = GetMainLight().direction;

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;

                half t = (dot(N, L) + 1.0) * 0.5;               // 0 = facing away, 1 = facing light
                half3 kCool = _CoolColor.rgb + _Alpha * albedo;
                half3 kWarm = _WarmColor.rgb + _Beta  * albedo;
                half3 col   = lerp(kCool, kWarm, t);

                half spec = pow(saturate(dot(reflect(-L, N), V)), _SpecularPower);
                col = lerp(col, 1.0, spec);

                half edge = 1.0 - smoothstep(_EdgeWidth - 0.05, _EdgeWidth + 0.05, saturate(dot(N, V)));
                col = lerp(col, _EdgeColor.rgb, edge * _EdgeColor.a);
                return half4(col, 1.0);
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
