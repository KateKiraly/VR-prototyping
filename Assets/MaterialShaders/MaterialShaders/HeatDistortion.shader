// Heat haze: wobbles whatever is behind it. Put it on a quad above a fire,
// on an exhaust, or in a particle system (vertex alpha fades it).
// REQUIRES: URP Asset -> Opaque Texture ON.
Shader "ShaderPack/FX/HeatDistortion"
{
    Properties
    {
        _Strength ("Distortion Strength", Range(0, 0.1)) = 0.02
        _NoiseScale ("Noise Scale", Float) = 6
        _Speed ("Rise Speed", Float) = 1.5
        [Toggle] _UseQuadMask ("Soft Quad Edges (off = fade at silhouette)", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }

        Pass
        {
            Name "HeatForward"
            Tags { "LightMode"="UniversalForward" }
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Strength;
                float _NoiseScale;
                float _Speed;
                half  _UseQuadMask;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; float4 color : COLOR; };
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float4 screenPos   : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float3 positionWS  : TEXCOORD3;
                float4 color       : COLOR;
            };

            float Hash2 (float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
            float ValueNoise2 (float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(Hash2(i), Hash2(i + float2(1, 0)), f.x),
                            lerp(Hash2(i + float2(0, 1)), Hash2(i + float2(1, 1)), f.x), f.y);
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.screenPos   = ComputeScreenPos(pos.positionCS);
                OUT.uv          = IN.uv;
                OUT.color       = IN.color;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float t = _Time.y * _Speed;
                float2 n = float2(ValueNoise2(IN.uv * _NoiseScale + float2(0.0, -t)),
                                  ValueNoise2(IN.uv * _NoiseScale * 1.3 + float2(5.2, -t * 1.2))) * 2.0 - 1.0;

                half mask;
                if (_UseQuadMask > 0.5)
                    mask = sin(PI * saturate(IN.uv.x)) * sin(PI * saturate(IN.uv.y));
                else
                {
                    float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                    mask = pow(abs(dot(normalize(IN.normalWS), V)), 2.0);
                }
                mask *= IN.color.a;

                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;
                return half4(SampleSceneColor(screenUV + n * _Strength * mask), 1.0);
            }
            ENDHLSL
        }
    }
}
