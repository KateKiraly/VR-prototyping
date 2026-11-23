// Flowing lava: dark lit crust with glowing animated cracks.
// Uses the flow-map technique (two phases cross-faded) on procedural noise.
// Leave the Flow Map gray for a uniform flow along "Flow Direction", or paint
// an RG flow map to make it curl around obstacles. Enable Bloom for the glow.
Shader "ShaderPack/Nature/LavaFlow"
{
    Properties
    {
        _CrustColor ("Crust Color", Color) = (0.08, 0.05, 0.05, 1)
        [HDR] _LavaColor ("Lava Color", Color) = (4, 1, 0.1, 1)
        [HDR] _HotColor ("Hottest Color", Color) = (6, 3, 0.5, 1)
        _FlowMap ("Flow Map (RG, gray = none)", 2D) = "gray" {}
        _FlowDirection ("Flow Direction (UV)", Vector) = (0.1, 0.05, 0, 0)
        _FlowStrength ("Flow Map Strength", Range(0, 1)) = 0.3
        _FlowSpeed ("Flow Speed", Range(0, 2)) = 0.2
        _NoiseScale ("Pattern Scale", Float) = 4
        _CrackThreshold ("Lava Amount", Range(0, 1)) = 0.45
        _CrackSoftness ("Crack Softness", Range(0.001, 0.3)) = 0.08
        _PulseSpeed ("Glow Pulse Speed", Range(0, 5)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _FlowMap_ST;
            half4  _CrustColor;
            half4  _LavaColor;
            half4  _HotColor;
            float4 _FlowDirection;
            float  _FlowStrength;
            float  _FlowSpeed;
            float  _NoiseScale;
            half   _CrackThreshold;
            half   _CrackSoftness;
            half   _PulseSpeed;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "LavaForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_FlowMap); SAMPLER(sampler_FlowMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; float3 positionWS : TEXCOORD2; };

            float Hash2 (float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
            float ValueNoise2 (float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(Hash2(i), Hash2(i + float2(1, 0)), f.x),
                            lerp(Hash2(i + float2(0, 1)), Hash2(i + float2(1, 1)), f.x), f.y);
            }
            float Fbm2 (float2 p)
            {
                float v = 0.0, a = 0.5;
                [unroll] for (int i = 0; i < 4; i++) { v += a * ValueNoise2(p); p *= 2.07; a *= 0.5; }
                return v / 0.9375;
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _FlowMap);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // Flow vector from the map plus a constant direction
                float2 flow = (SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, IN.uv).rg * 2.0 - 1.0) * _FlowStrength
                              + _FlowDirection.xy;

                // Two phases offset by half a cycle, cross-faded to hide the reset
                float t   = _Time.y * _FlowSpeed;
                float ph0 = frac(t);
                float ph1 = frac(t + 0.5);
                float2 p  = IN.uv * _NoiseScale;
                float n0  = Fbm2(p - flow * ph0 * _NoiseScale);
                float n1  = Fbm2(p - flow * ph1 * _NoiseScale + 17.3);
                float w0  = 1.0 - abs(1.0 - 2.0 * ph0);
                float n   = n0 * w0 + n1 * (1.0 - w0);

                // Low noise = molten lava, high noise = crust
                half lava  = 1.0 - smoothstep(_CrackThreshold - _CrackSoftness, _CrackThreshold + _CrackSoftness, n);
                half pulse = 0.85 + 0.15 * sin(_Time.y * _PulseSpeed + n * 10.0);
                half3 hot  = lerp(_LavaColor.rgb, _HotColor.rgb, lava * lava * lava) * pulse;

                float3 N = normalize(IN.normalWS);
                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half3 crust = _CrustColor.rgb * (light.color * saturate(dot(N, light.direction)) * light.shadowAttenuation + SampleSH(N));

                return half4(lerp(crust, hot, lava), 1.0);
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
