Shader "Custom/FresnelTransparentURP"
{
    Properties
    {
        _BaseColor ("Base Color (alpha = center opacity)", Color) = (0, 0.5, 1, 0.05)
        _BaseMap ("Base Texture", 2D) = "white" {}
        [HDR] _FresnelColor ("Fresnel Color", Color) = (0, 1, 1, 1)
        _FresnelPower ("Fresnel Power", Range(0.1, 10)) = 3
        _FresnelIntensity ("Fresnel Intensity", Range(0, 5)) = 1.5
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull Mode", Float) = 2   // 2 = Back, 0 = Off (show inside faces too)
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Transparent"
            "Queue"="Transparent"
            "RenderPipeline"="UniversalPipeline"
            "IgnoreProjector"="True"
        }

        Pass
        {
            Name "ForwardUnlitTransparent"
            Tags { "LightMode"="UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha   // standard alpha blending (use "Blend One One" for additive glow)
            ZWrite Off
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                half4  _FresnelColor;
                half   _FresnelPower;
                half   _FresnelIntensity;
                half   _Cull;
            CBUFFER_END

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

            half4 frag (Varyings IN, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                N = IS_FRONT_VFACE(facing, N, -N);   // flip normal on back faces when Cull is Off
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                // 0 facing the camera, 1 at the silhouette
                half fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower) * _FresnelIntensity;

                half4 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                half3 col   = baseCol.rgb + _FresnelColor.rgb * fresnel;
                half  alpha = saturate(baseCol.a + fresnel * _FresnelColor.a);

                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
}
