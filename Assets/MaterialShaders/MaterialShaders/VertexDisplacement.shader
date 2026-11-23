// Vertex displacement: pushes vertices along their normals with waves, noise
// and a breathing pulse; colors by how far each point moved.
// Works best on dense meshes (e.g. an icosphere with several subdivisions).
Shader "ShaderPack/Mesh/VertexDisplacement"
{
    Properties
    {
        _LowColor ("Low Color", Color) = (0.1, 0.1, 0.4, 1)
        [HDR] _HighColor ("High Color", Color) = (1, 0.4, 0.8, 1)

        [Header(Waves)]
        _WaveAmplitude ("Wave Amplitude", Range(0, 0.5)) = 0.05
        _WaveFrequency ("Wave Frequency", Range(0, 20)) = 6
        _WaveSpeed ("Wave Speed", Range(0, 10)) = 2

        [Header(Noise)]
        _NoiseAmplitude ("Noise Amplitude", Range(0, 0.5)) = 0.1
        _NoiseScale ("Noise Scale", Range(0, 10)) = 2
        _NoiseSpeed ("Noise Speed", Range(0, 5)) = 0.5

        [Header(Pulse)]
        _PulseAmplitude ("Pulse Amplitude", Range(0, 0.3)) = 0.03
        _PulseSpeed ("Pulse Speed", Range(0, 10)) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _LowColor;
            half4 _HighColor;
            float _WaveAmplitude;
            float _WaveFrequency;
            float _WaveSpeed;
            float _NoiseAmplitude;
            float _NoiseScale;
            float _NoiseSpeed;
            float _PulseAmplitude;
            float _PulseSpeed;
        CBUFFER_END

        float Hash3 (float3 p)
        {
            p = frac(p * 0.3183099 + 0.1);
            p *= 17.0;
            return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
        }

        float ValueNoise3 (float3 x)
        {
            float3 i = floor(x);
            float3 f = frac(x);
            f = f * f * (3.0 - 2.0 * f);
            return lerp(lerp(lerp(Hash3(i + float3(0,0,0)), Hash3(i + float3(1,0,0)), f.x),
                             lerp(Hash3(i + float3(0,1,0)), Hash3(i + float3(1,1,0)), f.x), f.y),
                        lerp(lerp(Hash3(i + float3(0,0,1)), Hash3(i + float3(1,0,1)), f.x),
                             lerp(Hash3(i + float3(0,1,1)), Hash3(i + float3(1,1,1)), f.x), f.y), f.z);
        }

        float Displacement (float3 posOS)
        {
            float t = _Time.y;
            float wave  = sin(posOS.y * _WaveFrequency + t * _WaveSpeed) * _WaveAmplitude;
            float noise = (ValueNoise3(posOS * _NoiseScale + t * _NoiseSpeed) - 0.5) * 2.0 * _NoiseAmplitude;
            float pulse = sin(t * _PulseSpeed) * _PulseAmplitude;
            return wave + noise + pulse;
        }
        ENDHLSL

        Pass
        {
            Name "DisplaceForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings   { float4 positionHCS : SV_POSITION; float3 normalWS : TEXCOORD0; float3 positionWS : TEXCOORD1; float height : TEXCOORD2; };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float d = Displacement(IN.positionOS.xyz);
                float3 posOS = IN.positionOS.xyz + IN.normalOS * d;
                VertexPositionInputs pos = GetVertexPositionInputs(posOS);
                OUT.positionHCS = pos.positionCS;
                OUT.positionWS  = pos.positionWS;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);   // approximate: normals not recomputed
                float range = max(_WaveAmplitude + _NoiseAmplitude + _PulseAmplitude, 1e-4);
                OUT.height = saturate(d / range * 0.5 + 0.5);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                Light light = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half3 lit = light.color * saturate(dot(N, light.direction)) * light.shadowAttenuation + SampleSH(N);
                half3 albedo = lerp(_LowColor.rgb, _HighColor.rgb, IN.height);
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
                float3 posOS    = IN.positionOS.xyz + IN.normalOS * Displacement(IN.positionOS.xyz);
                float3 posWS    = TransformObjectToWorld(posOS);
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
