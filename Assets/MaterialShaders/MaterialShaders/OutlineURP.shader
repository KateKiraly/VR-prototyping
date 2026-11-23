// Inverted-hull outline. Add it as an EXTRA material on the Mesh Renderer
// (Materials list: [your normal material, Outline material]).
Shader "Custom/OutlineURP"
{
    Properties
    {
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1)
        _OutlineWidth ("Outline Width (pixels)", Range(0, 20)) = 3
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front      // draw only the back faces of the inflated mesh
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _OutlineColor;
                half  _OutlineWidth;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float3 posWS    = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);

                float4 posCS    = TransformWorldToHClip(posWS);
                float2 normalCS = mul((float3x3)GetWorldToHClipMatrix(), normalWS).xy;

                // Push vertices outward in screen space -> constant pixel width at any distance
                float2 offset = normalize(normalCS + 1e-5) * (_OutlineWidth * 2.0 / _ScreenParams.xy);
                posCS.xy += offset * posCS.w;

                OUT.positionHCS = posCS;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }
    }
}
