// Triplanar mapping: textures objects without UVs by projecting along X, Y and Z.
// Optional separate top texture (e.g. grass on top, rock on the sides).
Shader "ShaderPack/Surface/Triplanar"
{
    Properties
    {
        _BaseColor ("Tint", Color) = (1, 1, 1, 1)
        _MainTex ("Side Texture", 2D) = "white" {}
        [Toggle] _UseTopTex ("Use Top Texture", Float) = 0
        _TopTex ("Top Texture", 2D) = "white" {}
        _Tiling ("Tiling (per unit)", Float) = 1
        _BlendSharpness ("Blend Sharpness", Range(1, 16)) = 4
        [Toggle] _ObjectSpace ("Object Space (texture moves with object)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half  _UseTopTex;
            float _Tiling;
            half  _BlendSharpness;
            half  _ObjectSpace;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "TriplanarForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_TopTex);  SAMPLER(sampler_TopTex);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionOS  : TEXCOORD2;
                float3 normalOS    : TEXCOORD3;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionOS  = IN.positionOS.xyz;
                OUT.normalOS    = IN.normalOS;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 p = lerp(IN.positionWS, IN.positionOS, _ObjectSpace) * _Tiling;
                float3 n = normalize(lerp(IN.normalWS, IN.normalOS, _ObjectSpace));

                float3 w = pow(abs(n), _BlendSharpness);
                w /= (w.x + w.y + w.z);

                half3 cx    = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, p.zy).rgb;
                half3 cyMain= SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, p.xz).rgb;
                half3 cyTop = SAMPLE_TEXTURE2D(_TopTex,  sampler_TopTex,  p.xz).rgb;
                half3 cz    = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, p.xy).rgb;
                half3 cy    = lerp(cyMain, cyTop, step(0.0, n.y) * _UseTopTex);

                half3 albedo = (cx * w.x + cy * w.y + cz * w.z) * _BaseColor.rgb;

                float3 N = normalize(IN.normalWS);
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
