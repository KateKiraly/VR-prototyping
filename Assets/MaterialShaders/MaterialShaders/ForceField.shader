// Energy shield: fresnel edge, glowing line where it intersects other geometry,
// animated hex pattern. REQUIRES: URP Asset -> Depth Texture ON. Use on a sphere.
Shader "ShaderPack/FX/ForceField"
{
    Properties
    {
        [HDR] _FieldColor ("Field Color", Color) = (0.2, 0.6, 1.5, 1)
        _BaseAlpha ("Base Opacity", Range(0, 1)) = 0.05
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 3
        _FresnelStrength ("Fresnel Strength", Range(0, 3)) = 1
        _IntersectWidth ("Intersection Width", Range(0.01, 2)) = 0.3
        _IntersectStrength ("Intersection Strength", Range(0, 5)) = 2
        _PatternScale ("Hex Pattern Scale", Float) = 12
        _PatternStrength ("Hex Pattern Strength", Range(0, 1)) = 0.3
        _PulseSpeed ("Pulse Speed", Float) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }

        Pass
        {
            Name "ForceFieldForward"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha One
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _FieldColor;
                half  _BaseAlpha;
                half  _FresnelPower;
                half  _FresnelStrength;
                float _IntersectWidth;
                half  _IntersectStrength;
                float _PatternScale;
                half  _PatternStrength;
                float _PulseSpeed;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
                float4 screenPos   : TEXCOORD3;
            };

            // Distance to the nearest hexagon edge (0 on the edge)
            float HexEdge (float2 p)
            {
                p.x *= 1.1547;
                p.y += fmod(floor(p.x), 2.0) * 0.5;
                p = abs(frac(p) - 0.5);
                return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = IN.uv;
                OUT.screenPos   = ComputeScreenPos(pos.positionCS);
                return OUT;
            }

            half4 frag (Varyings IN, FRONT_FACE_TYPE facing : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                N = IS_FRONT_VFACE(facing, N, -N);
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                half fres = pow(1.0 - saturate(dot(N, V)), _FresnelPower) * _FresnelStrength;

                // Intersection glow: bright where scene geometry is just behind the shield
                float2 screenUV  = IN.screenPos.xy / IN.screenPos.w;
                float  sceneEye  = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
                float  depthDiff = sceneEye - IN.screenPos.w;
                half intersect   = pow(1.0 - saturate(depthDiff / _IntersectWidth), 3.0) * _IntersectStrength;

                // Pulsing hex grid (UV x2 horizontally to suit a sphere's UVs)
                half hex = 1.0 - smoothstep(0.0, 0.08, HexEdge(IN.uv * float2(2.0, 1.0) * _PatternScale));
                hex *= 0.5 + 0.5 * sin(_Time.y * _PulseSpeed + IN.uv.y * 10.0);

                half alpha = saturate(_BaseAlpha + fres + intersect + hex * _PatternStrength) * _FieldColor.a;
                return half4(_FieldColor.rgb, alpha);
            }
            ENDHLSL
        }
    }
}
